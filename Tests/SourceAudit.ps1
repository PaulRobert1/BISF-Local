# Development-only source audit; not imported by the runtime.
function Get-BISFSourceViolations {
    param([string]$Source,[switch]$AllowModuleLoader)
    $tokens=$null; $parseErrors=$null
    $ast=[Management.Automation.Language.Parser]::ParseInput($Source,[ref]$tokens,[ref]$parseErrors)
    foreach ($e in $parseErrors) { 'Parse: '+$e.Message }
    $commands=$ast.FindAll({param($n) $n -is [Management.Automation.Language.CommandAst]},$true)
    foreach ($command in $commands) {
        $name=$command.GetCommandName()
        if ($null -eq $name) {
            if (-not ($AllowModuleLoader -and $command.InvocationOperator -eq 'Dot' -and $command.Extent.Text -eq '. $file')) { 'Dynamic command: '+$command.Extent.Text }
        } elseif ($name -match '(?i)(\.(exe|com|bat|cmd)$|^(Start-Process|Invoke-Expression|iex|cmd|wmic|netsh|bcdedit|gpupdate|Get-WmiObject|gwmi|Invoke-WebRequest|Invoke-RestMethod|iwr|irm|curl|wget|Install-Module|Find-Module|Save-Module|Update-Module|Install-Package|Find-Package|Start-BitsTransfer|Test-NetConnection|Test-Connection|Resolve-DnsName)$)') {
            'Forbidden command: '+$name
        }
    }
    if ($Source -match '(?i)(System\.)?Net\.(WebClient|WebRequest|Http\.HttpClient|Sockets\.|Dns\b)') { 'Forbidden network API: runtime must work offline.' }
    if ($Source -match '(?i)(Diagnostics\.Process|ProcessStartInfo|HKLM:[^\r\n]*[\\/]Policies[\\/]|AlwaysOff|rss=disable|DisableTaskOffload)') { 'Forbidden legacy operation or process API.' }
}
