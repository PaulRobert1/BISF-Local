"""Inspect the built PE resource tree without requiring Wine or Windows."""
import pathlib
import struct
import sys
import xml.etree.ElementTree as ET


def manifest_from_pe(path):
    data = path.read_bytes()
    u16 = lambda offset: struct.unpack_from('<H', data, offset)[0]
    u32 = lambda offset: struct.unpack_from('<I', data, offset)[0]
    assert data[:2] == b'MZ', 'Not a Windows executable'
    pe = u32(0x3c)
    assert data[pe:pe + 4] == b'PE\0\0', 'Missing PE header'
    assert u16(pe + 4) == 0x8664, 'Launcher must remain x64'
    optional = pe + 24
    assert u16(optional) == 0x20b, 'Launcher must remain PE32+'
    assert u16(optional + 68) == 3, 'Launcher must remain a console application'
    resource_rva, resource_size = struct.unpack_from('<II', data, optional + 128)
    assert resource_rva and resource_size, 'Launcher has no embedded manifest resource; normal launch cannot request UAC'
    sections = optional + u16(pe + 20)

    def file_offset(rva, size=1):
        for index in range(u16(pe + 6)):
            section = sections + index * 40
            virtual_size, address, raw_size, raw = struct.unpack_from('<IIII', data, section + 8)
            if address <= rva and rva + size <= address + min(virtual_size, raw_size):
                assert raw + rva - address + size <= len(data), 'Truncated section'
                return raw + rva - address
        raise AssertionError('Resource RVA is not backed by section data')

    base = file_offset(resource_rva, resource_size)

    def entry(directory, identifier):
        assert directory + 16 <= resource_size, 'Resource directory out of bounds'
        count = u16(base + directory + 12) + u16(base + directory + 14)
        assert directory + 16 + count * 8 <= resource_size, 'Resource entries out of bounds'
        for index in range(count):
            name, target = struct.unpack_from('<II', data, base + directory + 16 + index * 8)
            if name == identifier:
                return target
        raise AssertionError('Missing resource ID %d' % identifier)

    resource_type = entry(0, 24)  # RT_MANIFEST
    assert resource_type & 0x80000000, 'Manifest type must point to a directory'
    resource_id = entry(resource_type & 0x7fffffff, 1)  # process manifest
    assert resource_id & 0x80000000, 'Manifest ID must point to a language directory'
    language = resource_id & 0x7fffffff
    assert u16(base + language + 12) == 0 and u16(base + language + 14) == 1, 'Expected one manifest language'
    target = u32(base + language + 20)
    assert not target & 0x80000000 and target + 16 <= resource_size, 'Invalid manifest data entry'
    payload_rva, size = struct.unpack_from('<II', data, base + target)
    offset = file_offset(payload_rva, size)
    return data[offset:offset + size]


if __name__ == '__main__':
    root = pathlib.Path(__file__).resolve().parents[1]
    exe = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else root / 'BISF-Local.exe'
    manifest = ET.fromstring(manifest_from_pe(exe).rstrip(b'\0'))
    levels = manifest.findall('.//{urn:schemas-microsoft-com:asm.v3}requestedExecutionLevel')
    assert len(levels) == 1, 'Expected one requested execution level'
    assert levels[0].attrib == {'level': 'requireAdministrator', 'uiAccess': 'false'}, 'Launcher must request standard administrator consent'
    source = root / 'Packaging' / 'Launcher.manifest'
    assert ET.tostring(manifest) == ET.tostring(ET.parse(source).getroot()), 'Built manifest differs from source'
    print('PASS: x64 console PE contains process manifest requireAdministrator, uiAccess=false, matching source')
