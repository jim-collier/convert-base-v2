; Single-file Windows installer for convert-base-v2.
; Built by cicd/utility/package.bash via makensis, one per architecture. The
; payload is the already-cross-compiled static .exe (Go needs no runtime), so
; this just drops it, puts it on PATH, and registers an uninstaller. Re-running
; overwrites an existing install (that is the "update if already installed"
; path). Defines come from the packager:
;   APPVERSION  version string (with leading v stripped)
;   APPARCH     x86_64 | arm64  (display only)
;   EXEPATH     path to the source .exe to embed
;   OUTFILE     installer path to write

Unicode true
!include "MUI2.nsh"
!include "LogicLib.nsh"
!include "WinMessages.nsh"

!ifndef APPVERSION
  !define APPVERSION "0.0.0"
!endif
!ifndef APPARCH
  !define APPARCH "x86_64"
!endif
!ifndef EXEPATH
  !error "EXEPATH not defined (pass -DEXEPATH=...)"
!endif
!ifndef OUTFILE
  !define OUTFILE "convert-base-v2-setup.exe"
!endif

!define APPNAME   "convert-base-v2"
!define PUBLISHER "Jim Collier"
!define ENVKEY    "SYSTEM\CurrentControlSet\Control\Session Manager\Environment"
!define ARPKEY    "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APPNAME}"

Name "${APPNAME} ${APPVERSION} (${APPARCH})"
OutFile "${OUTFILE}"
InstallDir "$PROGRAMFILES64\${APPNAME}"
InstallDirRegKey HKLM "Software\${APPNAME}" "InstallDir"
RequestExecutionLevel admin
SetCompressor /SOLID lzma

!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "English"

; StrContains: pushes needle then haystack; pops the needle back if present, "" if not.
Function StrContains
  Exch $R1            ; haystack
  Exch
  Exch $R0            ; needle
  Push $R2
  Push $R3
  Push $R4
  StrLen $R2 $R0
  StrCpy $R3 0
  loop:
    StrCpy $R4 $R1 $R2 $R3
    StrCmp $R4 $R0 found
    StrCmp $R4 "" notfound
    IntOp $R3 $R3 + 1
    Goto loop
  found:
    StrCpy $R0 $R0
    Goto done
  notfound:
    StrCpy $R0 ""
  done:
  Pop $R4
  Pop $R3
  Pop $R2
  Pop $R1
  Exch $R0
FunctionEnd

Section "Install"
  SetOutPath "$INSTDIR"
  File "/oname=${APPNAME}.exe" "${EXEPATH}"
  WriteRegStr HKLM "Software\${APPNAME}" "InstallDir" "$INSTDIR"
  WriteUninstaller "$INSTDIR\uninstall.exe"

  ; Add/Remove Programs entry.
  WriteRegStr   HKLM "${ARPKEY}" "DisplayName"     "${APPNAME}"
  WriteRegStr   HKLM "${ARPKEY}" "DisplayVersion"  "${APPVERSION}"
  WriteRegStr   HKLM "${ARPKEY}" "Publisher"       "${PUBLISHER}"
  WriteRegStr   HKLM "${ARPKEY}" "InstallLocation" "$INSTDIR"
  WriteRegStr   HKLM "${ARPKEY}" "UninstallString" "$\"$INSTDIR\uninstall.exe$\""
  WriteRegDWORD HKLM "${ARPKEY}" "NoModify" 1
  WriteRegDWORD HKLM "${ARPKEY}" "NoRepair" 1

  ; Put the install dir on the system PATH, once.
  ReadRegStr $0 HKLM "${ENVKEY}" "Path"
  Push "$INSTDIR"
  Push "$0"
  Call StrContains
  Pop $1
  ${If} $1 == ""
    ${If} $0 == ""
      StrCpy $0 "$INSTDIR"
    ${Else}
      StrCpy $0 "$0;$INSTDIR"
    ${EndIf}
    WriteRegExpandStr HKLM "${ENVKEY}" "Path" "$0"
    SendMessage ${HWND_BROADCAST} ${WM_WININICHANGE} 0 "STR:Environment" /TIMEOUT=5000
  ${EndIf}
SectionEnd

Section "Uninstall"
  Delete "$INSTDIR\${APPNAME}.exe"
  Delete "$INSTDIR\uninstall.exe"
  RMDir  "$INSTDIR"
  DeleteRegKey HKLM "${ARPKEY}"
  DeleteRegKey HKLM "Software\${APPNAME}"
SectionEnd
