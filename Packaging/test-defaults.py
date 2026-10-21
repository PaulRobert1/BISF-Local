from pathlib import Path
import xml.etree.ElementTree as ET
r=Path(__file__).resolve().parents[1];x=ET.parse(r/'GlobalConfig.xml').getroot()
for path in ['Cleanup/WindowsTemp','Cleanup/CurrentUserTemp','Cleanup/UserProfiles','Cleanup/RecycleBin','LogCleanup/WindowsEventLogs','Explorer/RemoveQuickAccess','Explorer/ClassicContextMenu','Finalization/RemoveOperatorProfile','Servicing/ComponentCleanup']:
 assert x.findtext(path)=='true',path
for path in ['LogCleanup/BISFLogs','ConfigurationManager/PrepareIdentityReset','ConfigurationManager/CloneTrustedRootKeyReset','Personalization/Enabled','Citrix/VDA/StopBeforeShutdown']:
 assert x.findtext(path)=='false',path
assert x.findtext('FinalAction')=='Shutdown'
assert x.findtext('Preflight/BlockPendingReboot')=='true'
assert x.findtext('Preflight/BlockOtherLoadedProfiles')=='true'
assert "[string]$Mode='Prepare'" in (r/'Invoke-BISF.ps1').read_text()
print('PASS: update cleanup and automatic finalization enabled, ConfigMgr disabled, safety checks retained')
