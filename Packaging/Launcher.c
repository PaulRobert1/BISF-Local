/* GPL-3.0-or-later. Offline x64 launcher; framework and policy remain authoritative. */
#define UNICODE
#define _UNICODE
#include "winapi-minimal.h"
static WCHAR module[32768], script[32768], host[32768], command[32768];
static void say(const char *text) { DWORD n; WriteFile(GetStdHandle(STD_OUTPUT_HANDLE),text,lstrlenA(text),&n,NULL); }
void entry(void) {
 DWORD n=GetModuleFileNameW(NULL,module,32768), code=1; WCHAR *p,*args=GetCommandLineW();
 STARTUPINFOW si={0}; PROCESS_INFORMATION pi={0};
 if(!n || n>=32768) {say("Cannot resolve launcher location.\r\n");ExitProcess(1);}
 if(*args==L'"'){args++;while(*args && *args!=L'"')args++;if(*args)args++;}
 else {while(*args && *args!=L' ' && *args!=L'\t')args++;}
 while(*args==L' ' || *args==L'\t')args++;
 if(!lstrcmpW(args,L"--help") || !lstrcmpW(args,L"/?")) {
 say("BISF Local: runs adjacent Invoke-BISF.ps1 using Windows PowerShell 5.1.\r\nDefault: Prepare; enabled cleanup and shutdown after operator sign-out. Use an elevated console for preparation.\r\nBISF-Local.exe -Mode Validate\r\nBISF-Local.exe -Mode Prepare -WhatIf\r\nBISF-Local.exe -Mode Prepare\r\nBISF-Local.exe -Mode VerifyClone\r\nKeep the entire package together. Execution policy is not bypassed.\r\n");ExitProcess(0);}
 p=module+lstrlenW(module);while(p>module && p[-1]!=L'\\')p--;*p=0;
 if(lstrlenW(module)>32000){say("Package path too long.\r\n");ExitProcess(1);}
 lstrcpyW(script,module);lstrcatW(script,L"Invoke-BISF.ps1");
 n=GetFileAttributesW(script);if(n==INVALID_FILE_ATTRIBUTES || (n&FILE_ATTRIBUTE_DIRECTORY)){say("Adjacent Invoke-BISF.ps1 missing. Extract the entire package first.\r\n");ExitProcess(1);}
 n=GetSystemDirectoryW(host,32768);if(!n || n>32000){ExitProcess(1);}
 lstrcatW(host,L"\\WindowsPowerShell\\v1.0\\powershell.exe");
 if(lstrlenW(host)+lstrlenW(script)+lstrlenW(args)+64>=32768){say("Command line too long.\r\n");ExitProcess(1);}
 lstrcpyW(command,L"\"");lstrcatW(command,host);lstrcatW(command,L"\" -NoLogo -NoProfile -File \"");lstrcatW(command,script);lstrcatW(command,L"\" ");lstrcatW(command,args);
 si.cb=sizeof(si);
 if(!CreateProcessW(host,command,NULL,NULL,TRUE,0,NULL,NULL,&si,&pi)){say("Cannot start Windows PowerShell 5.1.\r\n");ExitProcess(1);}
 CloseHandle(pi.hThread);
 if(WaitForSingleObject(pi.hProcess,INFINITE)==WAIT_OBJECT_0)GetExitCodeProcess(pi.hProcess,&code);
 CloseHandle(pi.hProcess);ExitProcess(code);
}
