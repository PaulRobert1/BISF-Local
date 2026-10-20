import os,subprocess,tempfile,pathlib,shutil
root=pathlib.Path(__file__).resolve().parents[1]
exe=root/'BISF-Local.exe'
assert exe.is_file(),'Launcher has not been built'
env=dict(os.environ,WINEPREFIX='/tmp/bisf-local-launcher-wine-test',WINEDEBUG='-all')
r=subprocess.run(['wine',str(exe),'--help'],env=env,capture_output=True,text=True,timeout=90)
assert r.returncode==0 and 'Invoke-BISF.ps1' in r.stdout,(r.returncode,r.stdout,r.stderr)
with tempfile.TemporaryDirectory(prefix='bisf launcher ') as d:
 p=pathlib.Path(d);shutil.copy2(exe,p/exe.name)
 r=subprocess.run(['wine',str(p/exe.name)],env=env,capture_output=True,text=True,timeout=30)
 assert r.returncode==1 and 'missing' in r.stdout.lower(),(r.returncode,r.stdout)
print('PASS: help and missing adjacent script refused')
subprocess.run(['clang','--target=x86_64-w64-windows-gnu','-fuse-ld=lld','-nostdlib','-fno-stack-protector','-Wl,--entry,entry','-Wl,--subsystem,console',str(root/'Packaging/test-host.c'),'-L/usr/x86_64-w64-mingw32/sys-root/mingw/lib','-lkernel32','-o',str(pathlib.Path('/tmp/bisf-local-test-host.exe'))],check=True)
host=pathlib.Path(env['WINEPREFIX'])/'drive_c/windows/system32/WindowsPowerShell/v1.0/powershell.exe'
host.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(pathlib.Path('/tmp/bisf-local-test-host.exe'),host)
with tempfile.TemporaryDirectory(prefix='bisf path spaces ') as d:
 p=pathlib.Path(d);shutil.copy2(exe,p/exe.name);(p/'Invoke-BISF.ps1').write_text('# dummy: test host never executes this')
 for args in [[],['-Mode','Prepare','-WhatIf','-ConfigPath','C:\\Config space\\custom.xml']]:
  r=subprocess.run(['wine',str(p/exe.name),*args],env=env,capture_output=True,timeout=30)
  out=r.stdout.decode('utf-16le')
  assert r.returncode==37 and '-NoLogo -NoProfile -File "' in out and 'Invoke-BISF.ps1"' in out,(r.returncode,out)
  assert 'ExecutionPolicy' not in out
  if args:assert '-Mode Prepare -WhatIf -ConfigPath "C:\\Config space\\custom.xml"' in out,out
print('PASS: quoted package/config paths, default invocation, flags, no policy bypass, child exit 37 propagated')
