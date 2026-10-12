# BIS-F Local, unofficial derivative. Modified 2026-10-12. GPL-3.0; see LICENSE.
function Test-BISFPathWithin {
    param([string]$Path, [string]$Parent)
    $p = [IO.Path]::GetFullPath($Path).TrimEnd([char[]]'\/')
    $r = [IO.Path]::GetFullPath($Parent).TrimEnd([char[]]'\/')
    $p.Equals($r, [StringComparison]::OrdinalIgnoreCase) -or $p.StartsWith($r + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)
}
function Test-BISFNoReparsePath {
    param([string]$Path)
    $current = [IO.Path]::GetFullPath($Path)
    while (-not [string]::IsNullOrEmpty($current)) {
        if (Test-Path -LiteralPath $current) {
            $item = Get-Item -LiteralPath $current -Force -ErrorAction Stop
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Refusing reparse point: $current" }
        }
        $parent = [IO.Path]::GetDirectoryName($current)
        if ($parent -eq $current) { break }
        $current = $parent
    }
}
function Get-BISFCleanupCandidates {
    param([string]$Root, [int]$MinimumAgeDays, [string[]]$ProtectedPaths)
    $roots = Get-BISFTempRoots
    $full = [IO.Path]::GetFullPath($Root).TrimEnd([char[]]'\/')
    $approved = @($roots.WindowsTemp,$roots.CurrentUserTemp | ForEach-Object { [IO.Path]::GetFullPath($_).TrimEnd([char[]]'\/') })
    if ($full -notin $approved -or $MinimumAgeDays -lt 1) { throw 'Cleanup requires an approved temporary root and positive minimum age.' }
    Test-BISFNoReparsePath $full
    $cutoff = [DateTime]::UtcNow.AddDays(-$MinimumAgeDays)
    $queue = New-Object 'System.Collections.Generic.Queue[string]'
    $queue.Enqueue($full)
    while ($queue.Count -gt 0) {
        $dir = $queue.Dequeue()
        Test-BISFNoReparsePath $dir
        $blocked = $false
        foreach ($p in $ProtectedPaths) { if (Test-BISFPathWithin $dir $p) { $blocked = $true; break } }
        if ($blocked) { continue }
        foreach ($item in Get-ChildItem -LiteralPath $dir -Force -ErrorAction Stop) {
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
            $blocked = $false
            foreach ($p in $ProtectedPaths) { if (Test-BISFPathWithin $item.FullName $p) { $blocked = $true; break } }
            if ($blocked) { continue }
            if ($item.PSIsContainer) { $queue.Enqueue($item.FullName) }
            elseif ($item.LastWriteTimeUtc -lt $cutoff) {
                [pscustomobject]@{Path=$item.FullName;Root=$full;Cutoff=$cutoff;LastWriteTimeUtc=$item.LastWriteTimeUtc;Length=$item.Length;ProtectedPaths=$ProtectedPaths}
            }
        }
    }
}
function Remove-BISFTempFiles {
    param([object[]]$Candidates)
    foreach ($c in $Candidates) {
        Test-BISFNoReparsePath $c.Path
        if (-not (Test-BISFPathWithin $c.Path $c.Root)) { throw 'Cleanup candidate escaped its root.' }
        foreach ($p in $c.ProtectedPaths) { if (Test-BISFPathWithin $c.Path $p) { throw 'Cleanup candidate is protected.' } }
        $item = Get-Item -LiteralPath $c.Path -Force -ErrorAction Stop
        if ($item.PSIsContainer -or $item.LastWriteTimeUtc -ge $c.Cutoff -or $item.LastWriteTimeUtc -ne $c.LastWriteTimeUtc -or $item.Length -ne $c.Length) {
            throw "Cleanup candidate changed since enumeration: $($c.Path)"
        }
        Remove-Item -LiteralPath $c.Path -Force -ErrorAction Stop
    }
}
function Wait-BISFService {
    param([string]$Status)
    $svc = Get-Service -Name CcmExec -ErrorAction Stop
    $svc.WaitForStatus([System.ServiceProcess.ServiceControllerStatus]$Status, [TimeSpan]::FromSeconds(60))
}
function Remove-BISFSmsCertificates {
    $store = New-Object Security.Cryptography.X509Certificates.X509Store('SMS','LocalMachine')
    try {
        $store.Open([Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite -bor [Security.Cryptography.X509Certificates.OpenFlags]::OpenExistingOnly)
        foreach ($certificate in @($store.Certificates)) { $store.Remove($certificate) }
    } finally { $store.Close() }
}
function Restore-BISFCMService {
    param([string]$PreviousState)
    if ($PreviousState -eq 'Running') { Start-Service -Name CcmExec -ErrorAction Stop; Wait-BISFService 'Running' }
    elseif ($PreviousState -eq 'Stopped') { Stop-Service -Name CcmExec -ErrorAction Stop; Wait-BISFService 'Stopped' }
}
function Invoke-BISFCMPrepare {
    $previous = [string](Get-Service -Name CcmExec -ErrorAction Stop).Status
    if ($previous -notin @('Running','Stopped')) { throw "CcmExec must be stable before preparation (currently $previous)." }
    try {
        Stop-Service -Name CcmExec -ErrorAction Stop
        Wait-BISFService 'Stopped'
        Remove-BISFSmsCertificates
        $ini = Join-Path $env:SystemRoot 'SMSCFG.ini'
        if (Test-Path -LiteralPath $ini) { Remove-Item -LiteralPath $ini -Force -ErrorAction Stop }
        $previous
    } catch {
        $original = $_
        try { Restore-BISFCMService $previous }
        catch { Write-Warning "CcmExec restoration also failed: $($_.Exception.Message)" }
        throw $original
    }
}
function Invoke-BISFCMCloneReset {
    # Query materializes before deleting: provider errors cannot become empty success.
    $instances = @(Get-CimInstance -Namespace 'root\ccm\locationservices' -ClassName TrustedRootKey -ErrorAction Stop)
    foreach ($instance in $instances) { Remove-CimInstance -InputObject $instance -ErrorAction Stop }
}
