#include "winapi-minimal.h"
void entry(void) {WCHAR *s=GetCommandLineW();DWORD n;WriteFile(GetStdHandle(STD_OUTPUT_HANDLE),s,lstrlenW(s)*2,&n,NULL);ExitProcess(37);}
