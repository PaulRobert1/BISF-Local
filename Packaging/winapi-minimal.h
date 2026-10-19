/* Minimal Windows x64 ABI declarations for the launcher, no third-party runtime. */
typedef unsigned long DWORD; typedef unsigned short WORD; typedef int BOOL;
typedef unsigned short WCHAR; typedef void *HANDLE;
#define NULL ((void *)0)
#define TRUE 1
#define INVALID_FILE_ATTRIBUTES ((DWORD)-1)
#define FILE_ATTRIBUTE_DIRECTORY 16
#define STD_OUTPUT_HANDLE ((DWORD)-11)
#define INFINITE ((DWORD)-1)
#define WAIT_OBJECT_0 0
#define API __declspec(dllimport)
typedef struct { DWORD cb; WCHAR *lpReserved,*lpDesktop,*lpTitle; DWORD dwX,dwY,dwXSize,dwYSize,dwXCountChars,dwYCountChars,dwFillAttribute,dwFlags; WORD wShowWindow,cbReserved2; unsigned char *lpReserved2; HANDLE hStdInput,hStdOutput,hStdError; } STARTUPINFOW;
typedef struct { HANDLE hProcess,hThread; DWORD dwProcessId,dwThreadId; } PROCESS_INFORMATION;
API DWORD GetModuleFileNameW(HANDLE,WCHAR*,DWORD);
API WCHAR *GetCommandLineW(void);
API int lstrlenW(const WCHAR*); API int lstrlenA(const char*);
API int lstrcmpW(const WCHAR*,const WCHAR*);
API WCHAR *lstrcpyW(WCHAR*,const WCHAR*); API WCHAR *lstrcatW(WCHAR*,const WCHAR*);
API HANDLE GetStdHandle(DWORD); API BOOL WriteFile(HANDLE,const void*,DWORD,DWORD*,void*);
API void ExitProcess(DWORD);
API DWORD GetFileAttributesW(const WCHAR*); API DWORD GetSystemDirectoryW(WCHAR*,DWORD);
API BOOL CreateProcessW(const WCHAR*,WCHAR*,void*,void*,BOOL,DWORD,void*,const WCHAR*,STARTUPINFOW*,PROCESS_INFORMATION*);
API BOOL CloseHandle(HANDLE); API DWORD WaitForSingleObject(HANDLE,DWORD);
API BOOL GetExitCodeProcess(HANDLE,DWORD*);
