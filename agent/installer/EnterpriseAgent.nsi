; =============================================================================
;  EnterpriseAgent_Setup.exe — yagona, interaktivsiz Windows o'rnatuvchi.
;  Linux'da yig'iladi:  makensis -D... agent/installer/EnterpriseAgent.nsi
;  (agent/build-agent.sh barcha -D parametrlarni avtomatik beradi)
;
;  Ichida:
;   - MeshAgent (x64 / x86 / ARM64) — server tomonidan generatsiya qilingan,
;     .msh (MeshServer URL, MeshID, ServerID=SHA384 pin) EXE ICHIGA TIKILGAN
;   - postinstall.ps1 — powercfg, firewall, service recovery (5s), watchdog
;
;  Parametrlar (hammasi ixtiyoriy):
;   (yo'q)       o'rnatish; shu versiya o'rnatilgan va ishlayotgan bo'lsa — hech narsa qilmaydi
;   /FORCE       qayta o'rnatish
;   /UNINSTALL   to'liq o'chirish (agent, firewall qoidalari, watchdog)
;  Exit code: 0 = OK, 1 = agent o'rnatilmadi, 2 = xizmat ishga tushmadi, 3 = admin huquqi yo'q
;  Log: C:\ProgramData\<BRAND_KEY>\install.log
; =============================================================================
Unicode true
ManifestDPIAware true
RequestExecutionLevel admin
SilentInstall silent
SetCompressor /SOLID lzma
CRCCheck on

!include "LogicLib.nsh"
!include "x64.nsh"
!include "FileFunc.nsh"
!include "WinVer.nsh"

; ---- build-agent.sh beradigan qiymatlar (standartlar faqat lokal test uchun) ----
!ifndef BRAND
  !define BRAND "Enterprise"
!endif
!ifndef BRAND_KEY
  !define BRAND_KEY "EnterpriseAgent"
!endif
!ifndef SERVICE_NAME
  !define SERVICE_NAME "EnterpriseAgent"
!endif
!ifndef PUBLISHER
  !define PUBLISHER "Enterprise IT"
!endif
!ifndef COPYRIGHT
  !define COPYRIGHT "Enterprise IT"
!endif
!ifndef VERSION
  !define VERSION "1.0.0.0"
!endif
!ifndef SERVER_HOST
  !error "SERVER_HOST aniqlanmagan (-DSERVER_HOST=...)"
!endif
!ifndef SERVER_PORT
  !define SERVER_PORT "443"
!endif
!ifndef AGENT_X64
  !error "AGENT_X64 aniqlanmagan (-DAGENT_X64=path\to\meshagent64.exe)"
!endif
!ifndef OUTFILE
  !define OUTFILE "EnterpriseAgent_Setup.exe"
!endif
!ifndef POSTINSTALL
  !define POSTINSTALL "postinstall.ps1"
!endif

Name "${BRAND} Agent"
OutFile "${OUTFILE}"
!ifdef ICON
  Icon "${ICON}"
!endif

VIProductVersion "${VERSION}"
VIFileVersion "${VERSION}"
VIAddVersionKey "ProductName"     "${BRAND} Agent"
VIAddVersionKey "CompanyName"     "${PUBLISHER}"
VIAddVersionKey "FileDescription" "${BRAND} Agent Setup"
VIAddVersionKey "FileVersion"     "${VERSION}"
VIAddVersionKey "ProductVersion"  "${VERSION}"
VIAddVersionKey "LegalCopyright"  "${COPYRIGHT}"

!define REGKEY "SOFTWARE\${BRAND_KEY}\Agent"
Var LogFile
Var Log
Var Params

Function .onInit
  SetShellVarContext all          ; $APPDATA -> C:\ProgramData
  ${If} ${RunningX64}
    SetRegView 64
  ${EndIf}
  CreateDirectory "$APPDATA\${BRAND_KEY}"
  StrCpy $LogFile "$APPDATA\${BRAND_KEY}\install.log"
  FileOpen $Log $LogFile a
  FileSeek $Log 0 END
  ${GetTime} "" "L" $0 $1 $2 $3 $4 $5 $6
  FileWrite $Log "$\r$\n===== ${BRAND} Agent Setup ${VERSION} | $2-$1-$0 $4:$5:$6 =====$\r$\n"
  ${GetParameters} $Params
  FileWrite $Log "params: $Params$\r$\n"

  UserInfo::GetAccountType
  Pop $0
  ${If} $0 != "admin"
    FileWrite $Log "ERROR: administrator huquqi yo'q$\r$\n"
    FileClose $Log
    SetErrorLevel 3
    Quit
  ${EndIf}
FunctionEnd

Function ExtractPayload
  InitPluginsDir
  SetOutPath "$PLUGINSDIR"
  ${If} ${IsNativeARM64}
    !ifdef AGENT_ARM64
      File "/oname=agent.exe" "${AGENT_ARM64}"
      FileWrite $Log "arch: ARM64$\r$\n"
    !else
      File "/oname=agent.exe" "${AGENT_X64}"
      FileWrite $Log "arch: ARM64 (x64 emulyatsiya)$\r$\n"
    !endif
  ${ElseIf} ${RunningX64}
    File "/oname=agent.exe" "${AGENT_X64}"
    FileWrite $Log "arch: x64$\r$\n"
  ${Else}
    !ifdef AGENT_X86
      File "/oname=agent.exe" "${AGENT_X86}"
      FileWrite $Log "arch: x86$\r$\n"
    !else
      FileWrite $Log "ERROR: x86 agent installer ichida yo'q$\r$\n"
      FileClose $Log
      SetErrorLevel 1
      Quit
    !endif
  ${EndIf}
  File "/oname=postinstall.ps1" "${POSTINSTALL}"
  ; 64-bit tizimda 64-bit PowerShell/sc/powercfg ishlatilsin (WOW64 redirection o'chiriladi)
  ${If} ${RunningX64}
    ${DisableX64FSRedirection}
  ${EndIf}
FunctionEnd

; nsExec natijasini log faylga yozish: $0 = exit code
!macro RUN cmd
  nsExec::ExecToStack '${cmd}'
  Pop $0
  Pop $1
  FileWrite $Log `> ${cmd}$\r$\n$1$\r$\nexit=$0$\r$\n`
!macroend

!define PS '"$WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "$PLUGINSDIR\postinstall.ps1"'
!define PSARGS '-ServiceName "${SERVICE_NAME}" -Brand "${BRAND}" -BrandKey "${BRAND_KEY}" -ServerHost "${SERVER_HOST}" -ServerPort ${SERVER_PORT} -LogFile "$LogFile"'

Section "Install"
  ; ---------------- /UNINSTALL ----------------
  ClearErrors
  ${GetOptions} $Params "/UNINSTALL" $2
  ${IfNot} ${Errors}
    Call ExtractPayload
    FileWrite $Log "mode: uninstall$\r$\n"
    FileClose $Log
    nsExec::ExecToStack '${PS} ${PSARGS} -Uninstall'
    Pop $0
    Pop $1
    FileOpen $Log $LogFile a
    FileSeek $Log 0 END
    !insertmacro RUN '"$PLUGINSDIR\agent.exe" -fulluninstall --meshServiceName="${SERVICE_NAME}"'
    DeleteRegKey HKLM "${REGKEY}"
    FileWrite $Log "uninstall done$\r$\n"
    FileClose $Log
    SetErrorLevel 0
    Return
  ${EndIf}

  ; ---------------- idempotentlik (GPO/startup skriptdan qayta ishga tushganda) ----------------
  ClearErrors
  ${GetOptions} $Params "/FORCE" $2
  ${If} ${Errors}
    ReadRegStr $3 HKLM "${REGKEY}" "InstallerVersion"
    ReadRegStr $4 HKLM "${REGKEY}" "ServerHost"
    ${If} $3 == "${VERSION}"
    ${AndIf} $4 == "${SERVER_HOST}"
      nsExec::ExecToStack '"$SYSDIR\sc.exe" query "${SERVICE_NAME}"'
      Pop $0
      Pop $1
      Push $1
      Push "RUNNING"
      Call StrContains
      Pop $5
      ${If} $5 != ""
        FileWrite $Log "versiya ${VERSION} allaqachon o'rnatilgan va ishlayapti — o'tkazildi (/FORCE bilan qayta o'rnatish)$\r$\n"
        FileClose $Log
        SetErrorLevel 0
        Return
      ${EndIf}
    ${EndIf}
  ${EndIf}

  ; ---------------- o'rnatish ----------------
  Call ExtractPayload
  FileWrite $Log "mode: install -> ${SERVER_HOST}:${SERVER_PORT}$\r$\n"
  ; MeshAgent o'zi: eski versiyani to'xtatadi/o'chiradi, Program Files ga ko'chiradi,
  ; xizmatni yaratadi (nom/kompaniya .msh dan), WebRTC firewall qoidasini qo'shadi va ishga tushiradi.
  !insertmacro RUN '"$PLUGINSDIR\agent.exe" -fullinstall'

  ; Tizim optimizatsiyasi va tekshiruv (log faylga o'zi yozadi)
  FileClose $Log
  nsExec::ExecToStack '${PS} ${PSARGS}'
  Pop $0
  Pop $1
  FileOpen $Log $LogFile a
  FileSeek $Log 0 END
  FileWrite $Log "postinstall exit=$0$\r$\n"

  ${If} $0 == 0
    WriteRegStr HKLM "${REGKEY}" "InstallerVersion" "${VERSION}"
    WriteRegStr HKLM "${REGKEY}" "ServerHost" "${SERVER_HOST}"
    WriteRegStr HKLM "${REGKEY}" "ServiceName" "${SERVICE_NAME}"
  ${EndIf}
  FileClose $Log
  SetErrorLevel $0
SectionEnd

; StrContains: stack -> (haystack, needle) => needle yoki ""
Function StrContains
  Exch $R1 ; needle
  Exch
  Exch $R2 ; haystack
  Push $R3
  Push $R4
  Push $R5
  StrLen $R3 $R1
  StrCpy $R4 0
  loop:
    StrCpy $R5 $R2 $R3 $R4
    StrCmp $R5 $R1 found
    StrCmp $R5 "" notfound
    IntOp $R4 $R4 + 1
    Goto loop
  found:
    StrCpy $R1 $R1
    Goto done
  notfound:
    StrCpy $R1 ""
  done:
  Pop $R5
  Pop $R4
  Pop $R3
  Pop $R2
  Exch $R1
FunctionEnd
