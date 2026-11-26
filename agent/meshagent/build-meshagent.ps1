<#
  build-meshagent.ps1 — IXTIYORIY: MeshAgent'ni manba koddan o'z brendingiz bilan kompilyatsiya qilish.

  Qachon kerak?  Ko'p hollarda KERAK EMAS. MeshCentral server agentni yuklab berishda:
    - xizmat nomi / ko'rinadigan nom / kompaniya  -> agentCustomization (.msh orqali)
    - EXE VERSIONINFO + ikonka                      -> agentFileInfo (PE resurslarini qayta yozadi)
    - o'z codesign sertifikati bilan imzo            -> avtomatik
  Agent binarining ICHIDAGI satrlarni (standart xizmat nomi "Mesh Agent", sertifikat CN,
  resurs ikonkalari) o'zgartirish yoki agentga o'z kodingizni qo'shish kerak bo'lsa — shu skript.

  Talab: Windows 10/11 yoki Server 2022, Visual Studio 2022 (Desktop C++ workload, ARM64 tools),
         Git, Node.js (manifest uchun). CI: .github/workflows/meshagent-windows.yml

  Natija: agent\custom-bin\MeshService64.exe, MeshService.exe, MeshServiceARM64.exe + custom-manifest.json
          -> keyingi server image build'ida avtomatik image ichiga kiradi (server/Dockerfile 7-qadam).
#>
param(
  [string] $RepoRoot = (Resolve-Path "$PSScriptRoot\..\.."),
  [string] $Tag      = ("corp-" + (Get-Date -Format 'yyyyMMdd-HHmm'))
)
$ErrorActionPreference = 'Stop'

# --- upstream.lock va brand.env ---------------------------------------------------
function Read-EnvFile($path) {
  $h = @{}
  Get-Content $path | Where-Object { $_ -match '^\s*([A-Z0-9_]+)=(.*)$' } | ForEach-Object {
    $h[$Matches[1]] = $Matches[2].Trim().Trim('"')
  }
  return $h
}
$lock  = Read-EnvFile "$RepoRoot\upstream.lock"
$brand = Read-EnvFile "$RepoRoot\branding\brand.env"
$svc   = $brand['AGENT_SERVICE_NAME']
$disp  = $brand['AGENT_DISPLAY_NAME']

$work = Join-Path $env:TEMP "meshagent-build"
if (Test-Path $work) { Remove-Item $work -Recurse -Force }
git init -q $work
git -C $work remote add origin $lock['MESHAGENT_REPO']
git -C $work fetch -q --depth 1 origin $lock['MESHAGENT_REF']
git -C $work checkout -q FETCH_HEAD

# --- Patch'lar (patches/meshagent/*.patch) ---------------------------------------------
Get-ChildItem "$RepoRoot\patches\meshagent\*.patch" -ErrorAction SilentlyContinue | Sort-Object Name | ForEach-Object {
  Write-Host "apply $($_.Name)"; git -C $work apply --whitespace=nowarn $_.FullName
}

# --- Brending: standart xizmat nomi va VERSIONINFO --------------------------------------
# DIQQAT: agentcore.c dagi "Mesh Agent" taqqoslashlari (sertifikat CN tanlovi) o'zgartirilmaydi —
# biz nocertstore=1 ishlatamiz, shuning uchun bu kod yo'li ishlamaydi.
$sm = "$work\meshservice\ServiceMain.c"
(Get-Content $sm -Raw) -replace 'TCHAR\* serviceFile = TEXT\("Mesh Agent"\);', "TCHAR* serviceFile = TEXT(`"$svc`");" |
  Set-Content $sm -Encoding UTF8 -NoNewline

foreach ($rc in Get-ChildItem "$work\meshservice\*.rc*") {
  $t = Get-Content $rc.FullName -Raw
  $t = $t -replace 'VALUE "FileDescription", "[^"]*"', "VALUE `"FileDescription`", `"$disp`""
  $t = $t -replace 'VALUE "ProductName", "[^"]*"',     "VALUE `"ProductName`", `"$disp`""
  $t = $t -replace 'VALUE "CompanyName", "[^"]*"',     "VALUE `"CompanyName`", `"$($brand['COMPANY_NAME'])`""
  $t = $t -replace 'VALUE "LegalCopyright", "[^"]*"',  "VALUE `"LegalCopyright`", `"$($brand['AGENT_COPYRIGHT'])`""
  Set-Content $rc.FullName $t -Encoding Unicode -NoNewline
}
Copy-Item "$RepoRoot\branding\assets\agent.ico" "$work\meshservice\MeshService.ico" -Force

# --- Build ------------------------------------------------------------------------
$vs = & "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe" -latest -requires Microsoft.Component.MSBuild -find MSBuild\**\Bin\MSBuild.exe | Select-Object -First 1
if (-not $vs) { throw "MSBuild (Visual Studio 2022) topilmadi" }
foreach ($plat in 'x64', 'x86', 'ARM64') {
  & $vs "$work\MeshAgent-2022.sln" /m /p:Configuration=Release /p:Platform=$plat /t:MeshService-2022 /v:minimal
  if ($LASTEXITCODE -ne 0) { throw "build failed: $plat" }
}

# --- Natija + manifest ------------------------------------------------------------------
$out = "$RepoRoot\agent\custom-bin"
New-Item -ItemType Directory -Force $out | Out-Null
$files = 'MeshService64.exe', 'MeshService.exe', 'MeshServiceARM64.exe' | ForEach-Object {
  Copy-Item "$work\Release\$_" "$out\$_" -Force; "$out\$_"
}
# MeshCentral o'zining agents/release-manifest.js formatida manifest (SHA384)
$mc = Join-Path $env:TEMP "mc-manifest"
if (-not (Test-Path "$mc\agents\release-manifest.js")) {
  git init -q $mc; git -C $mc remote add origin $lock['MESHCENTRAL_REPO']
  git -C $mc fetch -q --depth 1 origin $lock['MESHCENTRAL_REF']; git -C $mc checkout -q FETCH_HEAD
}
node "$mc\agents\release-manifest.js" --repository "corp/MeshAgent" --tag $Tag @files |
  Set-Content "$out\custom-manifest.json" -Encoding ASCII
Write-Host "OK -> $out (tag $Tag). Endi: git add agent/custom-bin; git commit; CI server image'ni qayta yig'adi."
