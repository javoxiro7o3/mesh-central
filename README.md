# Korxona MeshCentral — custom fork, air-gapped server, tayyor Windows installer

MeshCentral (`Ylianst/MeshCentral`) va MeshAgent (`Ylianst/MeshAgent`) asosida
korxona uchun **white-label**, **internetsiz (LAN / WireGuard)** ishlaydigan
masofaviy boshqaruv platformasi:

| Nima | Qanday |
|---|---|
| Server | `sudo ./setup.sh` — bitta komanda: Docker, TLS, config, admin, guruh, installer |
| Agent | `agent/out/EnterpriseAgent_Setup.exe` — so'rovsiz o'rnatuvchi, server manzili + SHA384 pin ichida |
| Yangilash | `sudo ./update.sh` (yoki CI) — server yangilanadi, agentlar o'zi yangilanadi |
| Root CA | **Kerak emas.** Filial kompyuterlarining Trust Store'iga hech narsa yozilmaydi |

```
                     LAN / WireGuard (10.8.0.0/24)                    Docker host (markaziy server)
 ┌──────────────────────────┐                     ┌───────────────────────────────────────────────────────┐
 │ Filial PC (Win 10/11     │  wss://SERVER:443   │ nginx :443 (TLS, self-signed / korxona CA)            │
 │ Home/Pro)                │ ───────────────────▶│   │  /dl/  -> agent/out (installer tarqatish)         │
 │  EnterpriseAgent (SYSTEM)│   ServerID SHA384   │   ▼  http 172.31.250.20:4430  (tlsOffload)            │
 │  .msh EXE ichida         │   pinning           │ meshcentral (Node 24, rebranded, offline npm, agents) │
 │  KVM / Files / Terminal  │◀── WebRTC (UDP) ───▶│   ▼                                                   │
 └──────────────────────────┘                     │ mongodb 7 (yoki NeDB)      data/  — volume'lar        │
                                                  └───────────────────────────────────────────────────────┘
```

> **Talablar va bosqichma-bosqich o'rnatish (server + filial kompyuterlari):** [`docs/ORNATISH.md`](docs/ORNATISH.md)

---

## Repozitoriya tuzilmasi

```
.
├── setup.sh                     # 2-bosqich: serverni noldan ko'tarish (1 komanda)
├── update.sh                    # 4-bosqich: yangilash / rollback / offline bundle
├── upstream.lock                # upstream (yoki sizning fork) repo + aniq commit
├── docker-compose.yml           # nginx + meshcentral + mongodb
├── .env.example                 # server sozlamalari (setup.sh .env yaratadi, sirlarni generatsiya qiladi)
├── branding/
│   ├── brand.env                # BARCHA nomlar/ranglar/matnlar (bitta joy)
│   ├── assets/                  # title.png, login.png, welcome.jpg, agent.ico
│   ├── web/public/              # meshcentral-web overlay: favicon, logoback, styles/custom.css
│   └── generate-placeholders.py # vaqtinchalik logolar generatori
├── server/
│   ├── Dockerfile               # clone@commit -> patch -> rebrand -> translate/minify -> offline deps -> agent binarlari
│   ├── config.json.template     # maksimal sozlangan, air-gapped config
│   ├── entrypoint.sh
│   └── nginx/nginx.conf
├── scripts/
│   ├── rebrand.js               # views/emails/translate.json dagi "MeshCentral" -> BRAND_NAME (xavfsiz regex)
│   ├── pin-optional-modules.js  # ish vaqtida npm'dan o'rnatiladigan modullarni build'ga ko'chiradi
│   ├── fetch-agent-binaries.sh  # agent binarlarini GitHub Releases'dan SHA384 tekshiruvi bilan
│   ├── render-config.sh         # template + .env + brand.env -> data/meshcentral-data/config.json
│   ├── gen-tls.sh               # nginx sertifikati (faqat serverda)
│   ├── bootstrap.sh             # admin akkaunt + qurilma guruhi
│   ├── make-offline-bundle.sh   # air-gapped server uchun images+repo arxivi
│   └── lib.sh
├── agent/
│   ├── build-agent.sh           # 3-bosqich: serverdan agent -> ServerID tekshiruvi -> NSIS -> .exe
│   ├── installer/
│   │   ├── EnterpriseAgent.nsi  # yagona silent installer (x64/x86/ARM64)
│   │   ├── postinstall.ps1      # powercfg, firewall, recovery 5s, watchdog
│   │   └── Dockerfile           # makensis + osslsigncode builder (air-gapped uchun)
│   ├── meshagent/build-meshagent.ps1  # ixtiyoriy: MeshAgent'ni manbadan brend bilan kompilyatsiya
│   └── custom-bin/              # o'sha build natijasi (bo'sh bo'lsa rasmiy agentlar ishlatiladi)
├── patches/meshcentral|meshagent/   # config bilan hal bo'lmaydigan kod o'zgarishlari (.patch)
└── .github/workflows/
    ├── server-image.yml         # lint -> build -> smoke test -> GHCR push -> (ixtiyoriy) deploy + offline bundle
    ├── meshagent-windows.yml    # ixtiyoriy: VS2022 bilan agent build -> PR
    └── upstream-sync.yml        # haftalik: upstream yangi reliz -> upstream.lock PR
```

---

## 1-bosqich. Git repo va manba kod strukturasi

### 1.1. Repozitoriyalar

```bash
# GitHub'da Fork tugmasi bilan (yoki ichki Gitea/GitLab'ga mirror):
#   Ylianst/MeshCentral  ->  <org>/MeshCentral
#   Ylianst/MeshAgent    ->  <org>/MeshAgent      (faqat agentni o'zingiz kompilyatsiya qilsangiz)
# Shu repo (platforma/IaC) — alohida: <org>/mesh-central
```

Keyin `upstream.lock` dagi `MESHCENTRAL_REPO` / `MESHAGENT_REPO` ni fork URL'laringizga almashtiring.

**Nega "overlay + patch" modeli, to'liq fork ichida tahrirlash emas?** Upstream juda tez
yangilanadi (oyiga bir necha reliz). Brending va air-gap sozlamalari bu yerda **config + build
qadamlari** sifatida saqlanadi, upstream koddagi o'zgarishlar esa `patches/` dagi kichik `.patch`
fayllarda. Natijada yangi upstream versiyaga o'tish = `upstream.lock` dagi bitta commit'ni
almashtirish (buni `upstream-sync.yml` avtomatik PR qiladi). Fork ichida to'g'ridan-to'g'ri kod
o'zgartirmoqchi bo'lsangiz ham ishlaydi: o'z fork'ingizda `corp/main` branch'ini yuritib,
`MESHCENTRAL_REF` ni shu branch/commit'ga qarating — Dockerfile istalgan ref'ni oladi.

### 1.2. Brending nuqtalari (aniq fayl yo'llari)

**A. Config darajasi (kod o'zgartirmasdan, upstream yangilanishida saqlanadi)** — `server/config.json.template`:

| Nima | Kalit | Manba |
|---|---|---|
| Sarlavha, subtitle | `domains."".title`, `title2` | `brand.env` |
| Yuqori logotip / login logotip / login rasmi | `titlePicture`, `loginPicture`, `welcomePicture` | `branding/assets/*` → `meshcentral-data/branding/` |
| Footer, login matni | `footer`, `loginFooter`, `welcomeText` | `brand.env` |
| Agent xizmat nomi, ko'rinadigan nom, kompaniya, fayl nomi, ranglar | `agentCustomization.*` | `.msh` ga yoziladi |
| Agent EXE VERSIONINFO + ikonka | `agentFileInfo.*` (`icon: branding/agent.ico`) | server PE resurslarini qayta yozib, o'z sertifikati bilan imzolaydi |
| Masofaviy sessiya oynasi sarlavhasi, privacy bar | `consentMessages.Title`, `desktopPrivacyBarText` | `brand.env` |
| "My Server" dagi Upgrade tugmasi | `myServer.Upgrade: false` | — |

**B. Web overlay (`meshcentral-web/`, upstream fayllari ustidan)** — `branding/web/public/`:

| Fayl | Nima |
|---|---|
| `favicon.ico`, `favicon-16x16.png`, `favicon-32x32.png` | brauzer ikonkasi |
| `android-chrome-192x192.png`, `android-chrome-512x512.png` | PWA / mobil |
| `images/logoback.png` | mobil fon logotipi |
| `styles/custom.css` | ranglar/dizayn (MeshCentral har sahifadan keyin avtomatik yuklaydi) |
| `branding/web/views/<nom>.handlebars` (ixtiyoriy) | butun sahifa shablonini almashtirish (upstream `views/` dan nusxa olib) |

**C. Build vaqtida upstream kodida (avtomatik, `scripts/rebrand.js`)**:

| Upstream fayli | Nima o'zgaradi |
|---|---|
| `views/default.handlebars`, `views/default3.handlebars` (klassik / zamonaviy UI) | ko'rinadigan "MeshCentral" matnlari → `BRAND_NAME` (~40 ta har birida) |
| `views/login.handlebars`, `default-mobile`, `player`, `agentinvite` | shu |
| `emails/*.html`, `emails/*.txt` | e-mail shablonlaridagi nom |
| `translate/translate.json` | kalit + 25 tildagi tarjimalar (aks holda tarjimalar uzilib qoladi) |
| `views/translations/*`, `*-min.handlebars` | `translate.js minifyall/translateall` bilan qayta generatsiya |

JS identifikatorlar (`MeshCentralTheme`, `MeshCentralServerUpdate` ...) va URL ichidagi nomlar tegilmaydi.

**D. MeshAgent manba kodi (ixtiyoriy, `agent/meshagent/build-meshagent.ps1`)**:

| Upstream fayli | Nima |
|---|---|
| `meshservice/ServiceMain.c` (`serviceFile = TEXT("Mesh Agent")`) | standart xizmat nomi |
| `meshservice/MeshService64.rc`, `MeshService.rc.in` (`VERSIONINFO`) | FileDescription/ProductName/CompanyName |
| `meshservice/MeshService.ico` | ikonka |
| `meshcore/agentcore.c` | sertifikat CN logikasi — **tegmang**, `nocertstore=1` bilan keraksiz |

Ko'p hollarda D **kerak emas**: A bandidagi `agentCustomization` + `agentFileInfo` server tomonida
rasmiy agentni to'liq brendlaydi (sinovda: VERSIONINFO'da "Enterprise Agent", fayl nomi
`EnterpriseAgent64-Filiallar.exe`, xizmat `EnterpriseAgent`).

### 1.3. Tashqi bog'liqliklar va "cheklovlar"

MeshCentral va MeshAgent **Apache-2.0** — litsenziya kaliti, foydalanuvchi/qurilma limiti yoki
pullik funksiya **yo'q**, shuning uchun "olib tashlanadigan cheklov" ham yo'q. Apache-2.0 talabi:
`LICENSE` fayli va kod ichidagi copyright sarlavhalari saqlanishi kerak (`rebrand.js` ularga
tegmaydi; `AGENT_COPYRIGHT` da "Based on MeshAgent, Apache-2.0" qoldirilgan). "MeshCentral"
tovar belgisini o'z mahsulotingiz nomi sifatida ishlatmaslik uchun rebrand aynan foydali.

Internetga chiqadigan barcha nuqtalar (manba kodda tekshirilgan, MeshCentral 1.3.2) va ularning yechimi:

| Mexanizm (upstream fayl) | Nima qiladi | Yechim |
|---|---|---|
| `meshcentral.js` `getLatestServerVersion` | `npm view meshcentral` | `selfUpdate:false`, `myServer.Upgrade:false`, `NPM_CONFIG_OFFLINE=true` |
| `meshcentral.js` `InstallModules` | config'ga qarab npm'dan modul o'rnatadi | modullar build'da `package.json` ga pin qilinadi (`pin-optional-modules.js`) |
| `agentbuilds.js` (1.3.x yangi) | agent binarlarini GitHub Releases'dan yuklaydi, har 24 soatda tekshiradi | binarlar image ichida (`fetch-agent-binaries.sh`), `agentDownloads.enabled:false` |
| `meshcentral.js` timestamp | agent imzosiga `timestamp.sectigo.com` | `agentTimeStampServer:false` |
| `firebase.js` | `alt.meshcentral.com` push relay | `publicPushNotifications:false` (standart ham o'chiq) |
| `trustedProxy: "CloudFlare"` | cloudflare.com IP ro'yxati | ishlatilmaydi (aniq IP berilgan) |
| `settings.plugins` | plugin yuklash | `plugins.enabled:false` |
| `geoLocation` / `ipLocation` | xarita, IP joylashuvi | `false` |

**`LANonly` ishlatilmaydi** — u agentlarni multicast orqali serverni qidirishga majburlaydi
(`MeshServer=local`), multicast esa WireGuard / routed filial tarmoqlaridan o'tmaydi. Buning
o'rniga aniq `SERVER_HOST` (IP yoki ichki DNS) va `agentAllowedIP` / `userAllowedIP` allowlist ishlatiladi.

---

## 2-bosqich. Markaziy server: bitta komanda

### 2.1. Internet bor server (yoki build vaqtida internet bor)

```bash
git clone https://github.com/<org>/mesh-central.git /opt/mesh-central
cd /opt/mesh-central
sudo ./setup.sh --host 10.8.0.1          # agentlar ulanadigan IP/DNS (bo'lmasa wg0 -> default IP avtomatik)
```

`setup.sh` qiladi:
1. Docker Engine + compose (yo'q bo'lsa), `jq`, `openssl`, `envsubst`
2. `.env` (`.env.example` dan), barcha parol/kalitlarni generatsiya qiladi
3. `data/` papkalari (uid 1000)
4. `scripts/gen-tls.sh` — nginx sertifikati (faqat serverda)
5. `scripts/render-config.sh` — `config.json` + brending fayllari
6. image build (`server/Dockerfile`) yoki `--bundle` dan `docker load`
7. `scripts/bootstrap.sh` — admin (server to'xtagan holatda `--createaccount`), stack, qurilma guruhi (`meshctrl`)
8. `agent/build-agent.sh` — tayyor `EnterpriseAgent_Setup.exe`

### 2.2. Air-gapped server

```bash
# Internet bor mashinada / CI'da (server-image workflow -> "offline_bundle"):
./scripts/make-offline-bundle.sh            # -> dist/corp-mesh-offline-<tag>.tar.gz (bir necha yuz MB)
# Fleshka/ichki fayl serveri orqali ko'chirib, serverda (Docker oldindan o'rnatilgan bo'lsin):
tar -xzf corp-mesh-offline-<tag>.tar.gz repo.tar && mkdir mesh-central && tar -xf repo.tar -C mesh-central
cd mesh-central && sudo ./setup.sh --bundle ../corp-mesh-offline-<tag>.tar.gz --host 10.8.0.1
```

Bundle ichida: custom meshcentral image (npm modullar, tarjimalar, agent binarlari bilan), `mongo:7.0`,
`nginx:1.27-alpine`, `corp/nsis-builder` (installer'ni serverda yig'ish uchun) va repo.

### 2.3. `config.json` — asosiy qarorlar

`server/config.json.template` (izohlar fayl ichida). Muhimlari:

| Kalit | Qiymat | Nega |
|---|---|---|
| `cert` | `SERVER_HOST` | `.msh` dagi `MeshServer=wss://SERVER_HOST:443/agent.ashx` |
| `port` / `aliasPort` / `tlsOffload` | 4430 / 443 / nginx IP | nginx TLS'ni tugatadi, MeshCentral faqat ichki tarmoqda HTTP |
| `domains."".certUrl` | `file:///opt/meshcentral/tls/server.crt` | MeshCentral nginx sertifikati hash'ini biladi — agent autentifikatsiyasi proksi orqali ishlaydi |
| `agentSignLock` | `true` | imzolangan agent faqat shu serverga ulanadi |
| `agentConfig` | `["nocertstore=1"]` | agent o'z kalitini Windows sertifikat omboriga emas, o'z DB fayliga yozadi |
| `agentNoProxy` | `true` | filialdagi tizim proksisi agentni chalg'itmaydi (`ignoreProxyFile=1`) |
| `webRTC`, `allowHighQualityDesktop`, `desktopMultiplex` | `true` | LAN/VPN'da eng yuqori KVM sifati |
| `agentPong`/`browserPong` | 60 | nginx (330s) va VPN NAT timeout'lari uzmasligi uchun |
| `autoBackup` | 24 soat, 14 kun, parolli zip, `mongodump` | `data/meshcentral-backups/` |
| `userConsentFlags` | `desktopnotify`, `desktopprivacybar` | foydalanuvchi ekranida ulanish ko'rinadi (so'rov emas). Korxona siyosatiga qarab o'zgartiring |
| `newAccounts` | `false` | faqat admin akkaunt yaratadi |

`DB_ENGINE=nedb` qilinsa (`.env`), `render-config.sh` `mongoDb` kalitlarini olib tashlaydi va
`dbEncryptKey` bilan shifrlangan NeDB ishlatiladi; `COMPOSE_PROFILES=` bo'sh — mongodb konteyneri ko'tarilmaydi.

---

## 2-talab: Root CA'siz xavfsizlik modeli (qanday ishlaydi)

1. Server birinchi ishga tushganda **o'z** sertifikatlarini yaratadi: `agentserver-cert-public.crt`
   (server shaxsi), `codesign-cert-public.crt` (agent imzosi), `webserver-cert-*` va h.k. —
   `data/meshcentral-data/` da.
2. `.msh` (installer ichidagi agent EXE'ga tikilgan) da `ServerID` = **agent-server sertifikati
   ochiq kalitining SHA384 hash'i**. `build-agent.sh` buni mustaqil tekshiradi:
   `openssl x509 -pubkey | openssl rsa -RSAPublicKey_out -outform DER | openssl dgst -sha384`.
3. Agent `wss://` ga ulanadi va TLS sertifikatini **Windows zanjiri orqali tekshirmaydi**; buning
   o'rniga server o'z agent-kaliti bilan imzolangan javob beradi (TLS sertifikat hash'i + nonce),
   agent uni `ServerID` bilan solishtiradi. MITM proksi bu imzoni soxtalashtira olmaydi.
4. nginx orqali: MeshCentral `certUrl` dan nginx sertifikatini o'qiydi (sinov logida:
   `Loaded web certificate from "file:///…/server.crt" … SHA384 cert hash: …`), shuning uchun
   agent ko'rgan TLS hash'ni server biladi va autentifikatsiya muvaffaqiyatli bo'ladi.
5. `nocertstore=1` — agent o'z node-sertifikatini `CurrentUser\MY` (SYSTEM) omboriga ham
   yozmaydi (MeshAgent `meshcore/agentcore.c` → `wincrypto_open`), hammasi agent DB faylida.
6. Natija: filial kompyuterida **hech qanday sertifikat omboriga** (Root, My, CA) yozuv yo'q;
   korxonaning boshqa PKI/TLS tizimlari bilan konflikt bo'lmaydi.

Administratorlar brauzeri self-signed nginx sertifikatini ko'rib ogohlantiradi — buni faqat
administrator kompyuterlarida hal qiling: korxona CA'dan sertifikat oling (`data/tls/server.crt`
+ `server.key` ga qo'ying, `sudo ./update.sh --config`) yoki `server.crt` ni faqat admin
kompyuterlariga import qiling. Agentlar uchun hech narsa o'zgarmaydi.

---

## 3-bosqich. `EnterpriseAgent_Setup.exe` build pipeline

```bash
sudo agent/build-agent.sh                        # .env dagi DEFAULT_GROUP
sudo agent/build-agent.sh --group "Samarqand"    # boshqa guruh -> EnterpriseAgent_Setup_Samarqand.exe
```

Pipeline:

```
meshctrl listdevicegroups ──▶ MeshID (64 belgi)
          │
GET /meshagents?id=4|3|43&meshid=…   ◀── server: agentFileInfo (VERSIONINFO+ikonka) -> codesign
          │                              -> .msh EXE ichiga tikiladi
GET /meshsettings?id=…  ──▶ ServerID == SHA384(agentserver-cert pubkey) ?  MeshServer == wss://HOST:PORT ?
          │
makensis EnterpriseAgent.nsi  (+ postinstall.ps1, agent.ico, x64/x86/ARM64)
          │
[osslsigncode — CODESIGN_PFX bo'lsa]
          ▼
agent/out/EnterpriseAgent_Setup.exe  (+ .sha256, .build-info.json, <guruh>.msh)
          └── https://SERVER/dl/EnterpriseAgent_Setup.exe  (nginx, LAN ichida)
```

**Installer filial kompyuterida nima qiladi** (`EnterpriseAgent.nsi` + `postinstall.ps1`):

| Qadam | Tafsilot |
|---|---|
| Arxitektura | ARM64 → ARM64 agent, x64 → x64, aks holda x86 |
| Agent | `agent.exe -fullinstall` — `.msh` EXE ichidan; `%ProgramFiles%\<COMPANY_NAME>\<AGENT_SERVICE_NAME>\`, xizmat `EnterpriseAgent` (LocalSystem, auto) |
| Recovery | `sc failure … actions= restart/5000/restart/5000/restart/5000` (keyingi nosozliklarda ham 5 s), `sc failureflag 1` |
| Watchdog | Task Scheduler `EnterpriseAgent-Watchdog` (SYSTEM): startup + har 1 daqiqa — qo'lda to'xtatilgan xizmatni qaytaradi |
| Quvvat | barcha sxemalarda AC (va DC) Sleep=0, Hibernate=0, Hybrid sleep=off, wake timers=on; `powercfg /hibernate off`; Fast Startup off; NIC "turn off to save power" off |
| Firewall | `"<Brand> Agent"` guruhi: agent EXE → server TCP 443 out (IP bo'lsa faqat shu IP), WebRTC UDP in/out |
| Tekshiruv | xizmat Running, 30 s ichida server bilan TCP Established |
| Idempotentlik | shu versiya va server bilan o'rnatilgan va ishlayotgan bo'lsa — hech narsa qilmaydi (GPO startup skript uchun) |
| Log | `C:\ProgramData\EnterpriseAgent\install.log` |
| Exit code | 0 OK · 1 agent o'rnatilmadi · 2 xizmat ishlamadi · 3 admin emas |

Parametrlar: `/FORCE` (qayta o'rnatish), `/UNINSTALL` (agent + firewall + watchdog).

**"Hech narsa so'ramaydi"**: installer UI'siz (`SilentInstall silent`). Yagona istisno — Windows
UAC: foydalanuvchi qo'lda ishga tushirsa admin tasdig'i so'raladi (buni hech qanday installer
chetlab o'tolmaydi va o'tmasligi kerak). Ommaviy tarqatishda SYSTEM nomidan ishga tushiring —
UAC chiqmaydi:

```bat
:: GPO (Computer Configuration > Policies > Windows Settings > Scripts > Startup):
\\fileserver\it$\EnterpriseAgent_Setup.exe
:: yoki PsExec / SCCM / Intune Win32 app (install: EnterpriseAgent_Setup.exe, uninstall: ... /UNINSTALL)
psexec \\PC-01 -s -c EnterpriseAgent_Setup.exe
```

**Windows Home**: RDP serveri yo'qligi ahamiyatsiz — MeshCentral Desktop o'zining KVM
(agent ekranni o'zi oladi, WebRTC/WebSocket orqali) ishlatadi; Files va Terminal (PowerShell/CMD,
SYSTEM huquqi) agent xizmati orqali. Home'da gpedit yo'q — barcha sozlamalar `powercfg`, `sc`,
`netsh`/NetSecurity, Task Scheduler orqali, ular Home'da bor. Faqat brauzerdagi "RDP" (`mstsc`)
tugmasi Pro/Enterprise uchun ishlaydi.

**Kod imzosi (ixtiyoriy)**: `.env` ga `CODESIGN_PFX=/root/codesign.pfx` va `CODESIGN_PASS=...`
qo'shsangiz installer Authenticode bilan imzolanadi (SmartScreen va AV uchun foydali). Bu
filiallarga Root CA o'rnatishni talab qilmaydi. Microsoft Defender MeshAgent'ni "RemoteAdmin"
sifatida belgilasa — installer o'zi istisno qo'shmaydi (bu xavfli amaliyot); ruxsatni markaziy
Defender/Intune siyosatida installer imzosi yoki SHA256 bo'yicha bering.

---

## 4-bosqich. Yangilash (CI/CD)

| O'zgarish | Siz qilasiz | Avtomatik bo'ladi |
|---|---|---|
| Logo / nom / rang | `branding/` ni o'zgartirib push | CI image build; serverda `sudo ./update.sh` (yoki auto-deploy). Agentlar: yangi brend keyingi agent yangilanishida, installer qayta yig'iladi |
| Faqat config (`.env`, template) | `sudo ./update.sh --config` | config qayta yaratiladi, restart, installer qayta yig'iladi |
| Upstream yangi reliz | `upstream-sync` PR'ni ko'rib merge | build + smoke test; deploy |
| Kod patch | `patches/meshcentral/000N-*.patch` qo'shib push | build patch'ni qo'llaydi (qo'llanmasa — build to'xtaydi) |
| O'z MeshAgent build | `meshagent-windows` workflow'ni ishga tushirib PR merge | image yangi agent bilan; **server ulangan barcha agentlarni o'zi yangilaydi** |

Server tomoni:

```bash
sudo ./update.sh                    # git pull -> zaxira (mongodump + config) -> build -> restart -> installer
sudo ./update.sh --image <tag>      # CI GHCR/registry'ga push qilgan image bilan
sudo ./update.sh --bundle FILE      # air-gapped
sudo ./update.sh --rollback         # oldingi image (DB zaxirasi: data/meshcentral-backups/pre-update-*)
```

Agentlarni qayta o'rnatish **kerak emas**: MeshCentral har ulanishda agent binari hash'ini
o'zidagi bilan solishtiradi va farq bo'lsa agentni o'zi yangilaydi. Server manzili (`SERVER_HOST`)
yoki agent-server sertifikati (`data/meshcentral-data/agentserver-cert-*`) o'zgarsa — eski
agentlar ulana olmaydi; shuning uchun `data/meshcentral-data/*.key|*.crt` ni zaxiralang va
manzil sifatida o'zgarmas DNS nom ishlatish tavsiya etiladi.

CI (`.github/workflows/server-image.yml`): `shellcheck` → image build → smoke test (agent
binarlari, offline modullar, tarjimalar image ichida) → `ghcr.io/<org>/corp-meshcentral:<sha>` →
`AUTO_DEPLOY=true` va `production` environment tasdig'idan keyin LAN'dagi self-hosted runner
(`mesh-server` label) `update.sh --image <sha>` ni bajaradi va yangi installer'ni artefakt qiladi.
Air-gapped server uchun runner o'rniga workflow'ni `offline_bundle: true` bilan qo'lda ishga
tushirib, bundle'ni ko'chirasiz.

---

## Sinovdan o'tkazilgan (shu repo bilan, MeshCentral 1.3.2 @ `01f2d97`)

- `rebrand.js`: 708 almashtirish (views, emails, translate.json); JS identifikatorlar o'zgarmadi;
  `translate.js minifyall/translateall` muvaffaqiyatli, tarjima qilingan sahifalarda brend nomi bor.
- `pin-optional-modules.js` + `npm ci`: mongodb 4.17.2, saslprep 1.3.1, ssh2 1.17.0, image-size 2.0.2,
  wildleek 2.0.0, nodemailer 6.10.1, https-proxy-agent 7.0.6 — `meshcentral.js` dagi versiyalar bilan aynan.
- `fetch-agent-binaries.sh`: Windows x64/x86/ARM64 + Linux x64/ARM64, SHA384 manifest bilan mos.
- `render-config.sh` → MeshCentral `NPM_CONFIG_OFFLINE=true` bilan ishga tushdi, `certUrl` file:// yuklandi,
  `--createaccount`, `meshctrl adddevicegroup`, `/meshagents`, `/meshsettings` ishladi.
- `.msh`: `MeshServer=wss://<host>:443/agent.ashx`, `nocertstore=1`, `meshServiceName=EnterpriseAgent`;
  `ServerID` openssl hisobi bilan aynan mos; `.msh` EXE ichida; VERSIONINFO brendlangan; Authenticode imzo bor.
- `makensis` (3.09): 3 arxitekturali `EnterpriseAgent_Setup.exe` (~4.1 MB) yig'ildi.
- `shellcheck` toza; `docker compose config` ikkala profil bilan to'g'ri.

Sinovdan **o'tkazilmagan** (bu muhitda Docker daemon va Windows yo'q): `docker build` to'liq
ishga tushirish, nginx konteyneri, `postinstall.ps1` va installer'ning haqiqiy Windows'dagi bajarilishi.
Birinchi ishga tushirishni test VM'da (Windows 10/11 Home va Pro) qiling va
`C:\ProgramData\EnterpriseAgent\install.log` ni tekshiring.
