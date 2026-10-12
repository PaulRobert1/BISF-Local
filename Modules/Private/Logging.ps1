# BIS-F Local, unofficial derivative. Modified 2026-10-12. GPL-3.0; see LICENSE.
function New-BISFLogger {
    param($Config, [string]$Mode)
    $logger = [pscustomobject]@{ Enabled = [bool]$Config.Logging.Enabled; LogFile = $null }
    if ($logger.Enabled) {
        [void][IO.Directory]::CreateDirectory($Config.Logging.Path)
        $logger.LogFile = Join-Path $Config.Logging.Path ('BISF-{0}-{1}-{2}.log' -f $Mode, [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss'), [guid]::NewGuid().ToString('N'))
        $stream = [IO.File]::Open($logger.LogFile, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::Read)
        $stream.Dispose()
    }
    $logger
}
function Write-BISFLog {
    param($Logger, [string]$Level, [string]$Operation, [string]$Message)
    $line = '{0} [{1}] [{2}] {3}' -f [DateTime]::UtcNow.ToString('o'), $Level, $Operation, ($Message -replace '[\r\n]+',' ')
    Write-Host $line
    if ($null -ne $Logger -and $Logger.Enabled) {
        [IO.File]::AppendAllText($Logger.LogFile, $line + [Environment]::NewLine, (New-Object Text.UTF8Encoding($false)))
    }
}
function Close-BISFLogger { param($Logger) }
