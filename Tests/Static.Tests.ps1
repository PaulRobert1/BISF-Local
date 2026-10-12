BeforeAll {
    Set-StrictMode -Version Latest
    $root=Split-Path $PSScriptRoot -Parent
    if (Test-Path "$PSScriptRoot/SourceAudit.ps1") { . "$PSScriptRoot/SourceAudit.ps1" }
}
Describe 'Source-only runtime audit' {
    It 'detects forbidden external and dynamic execution: <Source>' -ForEach @(
        @{Source='Start-Process tool.exe'},@{Source='& "wmic.exe" x'},
        @{Source='Invoke-Expression $command'},@{Source='& $command'},
        @{Source='[Diagnostics.Process]::Start("tool")'},
        @{Source='Set-ItemProperty HKLM:\Software\Policies\BISF -Name X -Value 1'},
        @{Source='netsh int tcp set global rss=disable'}
    ) {
        @(Get-BISFSourceViolations -Source $Source).Count | Should -BeGreaterThan 0
    }
    It 'allows PowerShell cmdlets and the fixed scheduled PowerShell host' {
        @(Get-BISFSourceViolations -Source 'Get-CimInstance -ClassName Win32_OperatingSystem').Count | Should -Be 0
        @(Get-BISFSourceViolations -Source 'New-ScheduledTaskAction -Execute (Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe")').Count | Should -Be 0
    }
    It 'parses all runtime scripts and rejects forbidden runtime operations' {
        $files=@(Get-Item "$root/Invoke-BISF.ps1") + @(Get-ChildItem "$root/Modules" -Recurse -File | Where-Object Extension -in '.ps1','.psm1')
        $files.Count | Should -BeGreaterThan 5
        foreach ($f in $files) {
            $violations=@(Get-BISFSourceViolations -Source (Get-Content $f.FullName -Raw) -AllowModuleLoader:($f.Extension -eq '.psm1'))
            $violations | Should -BeNullOrEmpty -Because $f.Name
        }
    }
    It 'contains no executable or compiled payload' {
        @(Get-ChildItem $root -Recurse -File | Where-Object { $_.FullName -notmatch '[\\/]\.git[\\/]' -and $_.Extension -in '.exe','.dll','.com','.bat','.cmd','.msi' }).Count | Should -Be 0
    }
}
