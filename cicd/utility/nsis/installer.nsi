
# Copyright (c) 2026 Bubbles
# Licensed under The MIT License (MIT). Full text at:
#	https://mit-license.org/
# SPDX-License-Identifier: MIT
; Single-file Windows installer for convert-base-v2.
; Built by cicd/utility/package.bash via makensis, one per architecture. The
; payload is the already-cross-compiled static .exe (Go needs no runtime), so
; this just drops it, puts it on PATH, and registers an uninstaller. Re-running
; overwrites an existing install (that is the "update if already installed"
; path). Defines come from the packager:
;   APPVERSION  version string (with leading v stripped)
;   APPVERNUM   the same as four numbers, for the Details tab (optional)
;   COPYRIGHT   LegalCopyright on the Details tab (optional)
;   ICONPATH    .ico for the installer and uninstaller (optional)
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

!ifdef ICONPATH
  !define MUI_ICON   "${ICONPATH}"
  !define MUI_UNICON "${ICONPATH}"
!endif

!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "English"

!ifdef APPVERNUM
  VIProductVersion "${APPVERNUM}"
  VIFileVersion    "${APPVERNUM}"
  VIAddVersionKey /LANG=${LANG_ENGLISH} "ProductName"     "${APPNAME}"
  VIAddVersionKey /LANG=${LANG_ENGLISH} "CompanyName"     "${PUBLISHER}"
  VIAddVersionKey /LANG=${LANG_ENGLISH} "FileDescription" "${APPNAME} installer (${APPARCH})"
  VIAddVersionKey /LANG=${LANG_ENGLISH} "FileVersion"     "${APPVERSION}"
  VIAddVersionKey /LANG=${LANG_ENGLISH} "ProductVersion"  "${APPVERSION}"
  !ifdef COPYRIGHT
    VIAddVersionKey /LANG=${LANG_ENGLISH} "LegalCopyright" "${COPYRIGHT}"
  !endif
!endif

; PathEdit: push "add" or "remove", then call. Adds $INSTDIR to the end of the
; machine PATH once, or takes every copy of it out. A PATH can be far longer
; than an NSIS string, which ReadRegStr reads back as "", so the value stays in
; native memory and only single entries become NSIS strings (2026102519371715).
; Anything unexpected leaves the PATH as it was. Clobbers $0-$9 and $R0-$R2.
!macro PathEditFn un
Function ${un}PathEdit
  Exch $R9
  StrCpy $1 0
  StrCpy $4 0
  StrCpy $5 0
  StrCpy $R0 0
  ; 0x80000002 is HKLM, 3 is query and set value.
  System::Call 'advapi32::RegOpenKeyExW(p 0x80000002, t "${ENVKEY}", i 0, i 3, *p .r1) i .r0'
  ${If} $0 <> 0
    DetailPrint "PATH left as it was: can't open the key ($0)."
    Goto done
  ${EndIf}
  System::Call 'advapi32::RegQueryValueExW(p r1, t "Path", p 0, *i .r2, p 0, *i .r3) i .r0'
  ${If} $0 = 2
    StrCpy $2 2   ; no PATH at all: REG_EXPAND_SZ, empty
    StrCpy $3 0
  ${ElseIf} $0 <> 0
  ${OrIf} $2 < 1
  ${OrIf} $2 > 2
    DetailPrint "PATH left as it was: can't read it ($0, type $2)."
    Goto done
  ${EndIf}
  ; Room for the old value, a ;, $INSTDIR and a terminator, zero filled.
  StrLen $0 "$INSTDIR"
  IntOp $0 $0 + 4
  IntOp $0 $0 * 2
  IntOp $0 $0 + $3
  System::Alloc $0
  Pop $4
  System::Alloc $0
  Pop $5
  ${If} $4 = 0
  ${OrIf} $5 = 0
    DetailPrint "PATH left as it was: out of memory."
    Goto done
  ${EndIf}
  ${If} $3 > 0
    System::Call 'advapi32::RegQueryValueExW(p r1, t "Path", p 0, p 0, p r4, *i r3 r3) i .r0'
    ${If} $0 <> 0
      DetailPrint "PATH left as it was: can't read it ($0)."
      Goto done
    ${EndIf}
  ${EndIf}

  ; Copy each entry but ours to $5. With none of ours, that is the old value.
  StrCpy $6 $4      ; entry start
  StrCpy $9 $5      ; write point
  StrCpy $R2 0      ; entries kept
  ${Do}
    System::Call 'shlwapi::StrChrW(p r6, i 59) p .r7'
    ${If} $7 = 0
      System::Call 'kernel32::lstrlenW(p r6) i .r8'
    ${Else}
      IntOp $8 $7 - $6
      IntOp $8 $8 / 2
    ${EndIf}
    StrCpy $R1 ""
    ${If} $8 > 0
    ${AndIf} $8 < ${NSIS_MAX_STRLEN}
      IntOp $0 $8 + 1
      System::Call 'kernel32::lstrcpynW(t .R1, p r6, i r0)'
    ${EndIf}
    ${If} $R1 == "$INSTDIR"
    ${OrIf} $R1 == "$INSTDIR\"
      IntOp $R0 $R0 + 1
    ${Else}
      ${If} $R2 > 0
        System::Call 'kernel32::RtlMoveMemory(p r9, t ";", i 2)'
        IntOp $9 $9 + 2
      ${EndIf}
      IntOp $0 $8 * 2
      System::Call 'kernel32::RtlMoveMemory(p r9, p r6, i r0)'
      IntOp $9 $9 + $0
      IntOp $R2 $R2 + 1
    ${EndIf}
    ${If} $7 = 0
      ${Break}
    ${EndIf}
    IntOp $6 $7 + 2
  ${Loop}

  ${If} $R9 == "add"
    ${If} $R0 > 0
      Goto done
    ${EndIf}
    ; $8 is the last entry's length, so 0 means empty or ending in ;.
    ${If} $8 > 0
      System::Call 'kernel32::lstrcatW(p r4, t ";")'
    ${EndIf}
    System::Call 'kernel32::lstrcatW(p r4, t "$INSTDIR")'
    StrCpy $7 $4
  ${Else}
    ${If} $R0 = 0
      Goto done
    ${EndIf}
    StrCpy $7 $5
  ${EndIf}
  System::Call 'kernel32::lstrlenW(p r7) i .r0'
  IntOp $0 $0 + 1
  IntOp $0 $0 * 2
  System::Call 'advapi32::RegSetValueExW(p r1, t "Path", i 0, i r2, p r7, i r0) i .r0'
  ${If} $0 <> 0
    DetailPrint "Couldn't write the PATH ($0)."
  ${Else}
    SendMessage ${HWND_BROADCAST} ${WM_WININICHANGE} 0 "STR:Environment" /TIMEOUT=5000
  ${EndIf}

  done:
  ${If} $1 <> 0
    System::Call 'advapi32::RegCloseKey(p r1)'
  ${EndIf}
  ${If} $4 <> 0
    System::Free $4
  ${EndIf}
  ${If} $5 <> 0
    System::Free $5
  ${EndIf}
  Pop $R9
FunctionEnd
!macroend
!insertmacro PathEditFn ""
!insertmacro PathEditFn "un."

Section "Install"
  SetOutPath "$INSTDIR"
  File "/oname=${APPNAME}.exe" "${EXEPATH}"
  WriteRegStr HKLM "Software\${APPNAME}" "InstallDir" "$INSTDIR"
  WriteUninstaller "$INSTDIR\uninstall.exe"

  ; Add/Remove Programs entry.
  WriteRegStr   HKLM "${ARPKEY}" "DisplayName"     "${APPNAME}"
  WriteRegStr   HKLM "${ARPKEY}" "DisplayVersion"  "${APPVERSION}"
  WriteRegStr   HKLM "${ARPKEY}" "Publisher"       "${PUBLISHER}"
  WriteRegStr   HKLM "${ARPKEY}" "DisplayIcon"     "$INSTDIR\${APPNAME}.exe"
  WriteRegStr   HKLM "${ARPKEY}" "InstallLocation" "$INSTDIR"
  WriteRegStr   HKLM "${ARPKEY}" "UninstallString" "$\"$INSTDIR\uninstall.exe$\""
  WriteRegDWORD HKLM "${ARPKEY}" "NoModify" 1
  WriteRegDWORD HKLM "${ARPKEY}" "NoRepair" 1

  Push "add"
  Call PathEdit
SectionEnd

Section "Uninstall"
  Push "remove"
  Call un.PathEdit
  Delete "$INSTDIR\${APPNAME}.exe"
  Delete "$INSTDIR\uninstall.exe"
  RMDir  "$INSTDIR"
  DeleteRegKey HKLM "${ARPKEY}"
  DeleteRegKey HKLM "Software\${APPNAME}"
SectionEnd
