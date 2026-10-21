# BIS-F Local, unofficial GPL-3.0 derivative. Normal interactive operator sign-out.
# This module never deletes a profile, forces application closure or powers off.
function Initialize-BISFSessionNative {
    if ('BISF.Local.SessionNative' -as [type]) { return }
    Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
namespace BISF.Local {
    public static class SessionNative {
        [DllImport("wtsapi32.dll", EntryPoint="WTSQuerySessionInformationW", CharSet=CharSet.Unicode, ExactSpelling=true, SetLastError=true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool QuerySession(IntPtr server, int sessionId, int infoClass, out IntPtr buffer, out uint bytes);
        [DllImport("wtsapi32.dll")]
        private static extern void WTSFreeMemory(IntPtr buffer);
        [DllImport("user32.dll", SetLastError=true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool ExitWindowsEx(uint flags, uint reason);
        public static void RequestNormalLogoff() {
            // EWX_LOGOFF=0. No force, force-if-hung, shutdown or reboot flags.
            // Planned application maintenance reason, per ExitWindowsEx guidance.
            // Success means accepted, not that sign-out completed.
            if (!ExitWindowsEx(0, 0x80040001U))
                throw new Win32Exception(Marshal.GetLastWin32Error(), "Windows rejected normal operator sign-out.");
        }
        private static IntPtr Query(int sessionId, int infoClass, out uint bytes) {
            IntPtr buffer;
            if (!QuerySession(IntPtr.Zero, sessionId, infoClass, out buffer, out bytes)) {
                int error = Marshal.GetLastWin32Error();
                if (buffer != IntPtr.Zero) WTSFreeMemory(buffer);
                throw new Win32Exception(error, "Cannot query operator Windows session.");
            }
            if (buffer == IntPtr.Zero) throw new InvalidOperationException("Windows returned no session information.");
            return buffer;
        }
        public static string QueryString(int sessionId, int infoClass) {
            uint bytes;
            IntPtr buffer = Query(sessionId, infoClass, out bytes);
            try {
                if (bytes < 2 || bytes % 2 != 0 || bytes > Int32.MaxValue)
                    throw new InvalidOperationException("Invalid Windows session string.");
                return Marshal.PtrToStringUni(buffer, checked((int)bytes / 2)).TrimEnd('\0');
            } finally { WTSFreeMemory(buffer); }
        }
        public static int QueryConnectionState(int sessionId) {
            uint bytes;
            IntPtr buffer = Query(sessionId, 8, out bytes); // WTSConnectState
            try {
                if (bytes != 4) throw new InvalidOperationException("Invalid Windows session connection state.");
                return Marshal.ReadInt32(buffer);
            } finally { WTSFreeMemory(buffer); }
        }
    }
}
'@ -ErrorAction Stop
}
function Get-BISFNativeProcessSession {
    $process=Get-Process -Id $PID -ErrorAction Stop
    try {
        [pscustomobject]@{
            UserInteractive=[Environment]::UserInteractive
            SessionId=[int]$process.SessionId
            SID=Get-BISFCurrentUserSid
        }
    } finally { $process.Dispose() }
}
function Get-BISFNativeSessionOwner {
    param([int]$SessionId)
    Initialize-BISFSessionNative
    $name=[BISF.Local.SessionNative]::QueryString($SessionId,5) # WTSUserName
    $domain=[BISF.Local.SessionNative]::QueryString($SessionId,7) # WTSDomainName
    if ([string]::IsNullOrWhiteSpace($name) -or [string]::IsNullOrWhiteSpace($domain)) {
        throw 'Unable to identify the operator session owner.'
    }
    $account=New-Object Security.Principal.NTAccount -ArgumentList $domain,$name
    [pscustomobject]@{
        SID=[string]$account.Translate([Security.Principal.SecurityIdentifier]).Value
        ConnectionState=[BISF.Local.SessionNative]::QueryConnectionState($SessionId)
    }
}
function Get-BISFOperatorSession {
    param([Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$ExpectedSid)
    $process=@(Get-BISFNativeProcessSession)
    if ($process.Count -ne 1) { throw 'Unable to uniquely identify the operator process session.' }
    $process=$process[0]
    if (-not $process.UserInteractive -or [int]$process.SessionId -le 0) {
        throw 'Operator preparation requires an interactive user session outside service session zero.'
    }
    if ([string]$process.SID -ne $ExpectedSid) { throw 'Operator process SID changed; automatic sign-out refused.' }
    $owner=@(Get-BISFNativeSessionOwner -SessionId ([int]$process.SessionId))
    if ($owner.Count -ne 1) { throw 'Unable to uniquely identify the operator session owner.' }
    if ([string]$owner[0].SID -ne $ExpectedSid) {
        throw 'Operator session owner does not match the preparation account; automatic sign-out refused. Sign in directly as the preparation administrator.'
    }
    if ([int]$owner[0].ConnectionState -ne 0) { throw 'Operator session is not active; automatic sign-out refused.' } # WTSActive
    [pscustomobject]@{SessionId=[int]$process.SessionId;SID=$ExpectedSid}
}
function Invoke-BISFNativeOperatorSignOut {
    Initialize-BISFSessionNative
    [BISF.Local.SessionNative]::RequestNormalLogoff()
}
function Request-BISFOperatorSignOut {
    param(
        [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$ExpectedSid,
        [Parameter(Mandatory=$true)][ValidateRange(1,2147483647)][int]$ExpectedSessionId
    )
    $session=Get-BISFOperatorSession -ExpectedSid $ExpectedSid
    if ($session.SessionId -ne $ExpectedSessionId) { throw 'Operator session changed; automatic sign-out refused.' }
    # Fixed native normal-logoff API keeps the runtime offline and PowerShell-only.
    # No external process, force, delay or poweroff flags are available here.
    Invoke-BISFNativeOperatorSignOut
    # Acceptance is asynchronous. Only the SYSTEM worker can establish profile
    # unload, remove it, and shut down; applications or the user may cancel sign-out.
}
