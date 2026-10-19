from pathlib import Path
import xml.etree.ElementTree as ET
r=Path(__file__).resolve().parents[1];x=ET.parse(r/'GlobalConfig.xml').getroot()
for path in ['Cleanup/WindowsTemp','Cleanup/CurrentUserTemp','Cleanup/UserProfiles','Cleanup/RecycleBin','LogCleanup/WindowsEventLogs','LogCleanup/BISFLogs','Finalization/RemoveOperatorProfile']:
 assert x.findtext(path)=='true',path
for path in ['ConfigurationManager/PrepareIdentityReset','ConfigurationManager/CloneTrustedRootKeyReset','Personalization/Enabled','Citrix/VDA/StopBeforeShutdown','Servicing/ComponentCleanup']:
 assert x.findtext(path)=='false',path
assert x.findtext('FinalAction')=='Shutdown'
assert x.findtext('Preflight/BlockPendingReboot')=='true'
assert x.findtext('Preflight/BlockOtherLoadedProfiles')=='true'
assert "[string]$Mode='Prepare'" in (r/'Invoke-BISF.ps1').read_text()
print('PASS: preparation defaults, ConfigMgr disabled, incompatible actions disabled, safety checks retained')
