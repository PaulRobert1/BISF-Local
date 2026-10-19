# Native Windows PowerShell 5.1 regression test. Never runs the real framework module.
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$dir=Join-Path ([IO.Path]::GetTempPath()) ('BISF entry test '+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path (Join-Path $dir 'Modules')|Out-Null
Copy-Item (Join-Path $root 'BISF-Local.exe'),(Join-Path $root 'Invoke-BISF.ps1') $dir
'<test/>'|Set-Content (Join-Path $dir 'GlobalConfig.xml')
'<test/>'|Set-Content (Join-Path $dir 'custom config.xml')
@'
function Invoke-BISFLocal {
 param($ConfigPath,$ScriptRoot,$Mode,$WhatIf,$Confirm)
 if(-not [IO.Path]::IsPathRooted($ScriptRoot) -or -not [IO.File]::Exists($ConfigPath)){throw 'Invalid entry paths'}
 [pscustomobject]@{Mode=$Mode;ConfigPath=$ConfigPath;ScriptRoot=$ScriptRoot}|ConvertTo-Json -Compress|Write-Host
 [pscustomobject]@{ExitCode=37}
}
Export-ModuleMember -Function Invoke-BISFLocal
'@|Set-Content (Join-Path $dir 'Modules\BISF.Local.psm1')
$cases=@(
 @{Name='Default';Args=$null;Config='GlobalConfig.xml';Mode='Validate'},
 @{Name='Explicit';Args=('-Mode Validate -ConfigPath "'+$dir+'\custom config.xml"');Config='custom config.xml';Mode='Validate'}
)
foreach($case in $cases){
 $out=Join-Path $dir ($case.Name+'.out');$err=Join-Path $dir ($case.Name+'.err')
 $startArguments=@{FilePath=(Join-Path $dir 'BISF-Local.exe');WorkingDirectory=$env:SystemRoot;Wait=$true;PassThru=$true;RedirectStandardOutput=$out;RedirectStandardError=$err}
 if($case.Args){$startArguments.ArgumentList=$case.Args}
 $p=Start-Process @startArguments
 if($p.ExitCode -ne 37){throw "Entry test failed ($($case.Name)); exit $($p.ExitCode); evidence: $dir"}
 $result=([string](Get-Content $out -Raw))|ConvertFrom-Json
 if($result.Mode -ne $case.Mode -or $result.ScriptRoot -ne $dir -or $result.ConfigPath -ne (Join-Path $dir $case.Config)){throw "Incorrect entry paths: $dir"}
 [pscustomobject]@{Case=$case.Name;Status='PASS';PowerShell=$PSVersionTable.PSVersion.ToString();ExitCode=$p.ExitCode}|ConvertTo-Json -Compress
}
# Evidence deliberately retained under the unique temporary test directory.
