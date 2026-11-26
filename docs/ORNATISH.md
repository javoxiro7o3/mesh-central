# O'rnatish va ishga tushirish qo'llanmasi

Bu hujjat ikki qismdan iborat:

- **I qism — Talablar.** Ishni boshlashdan oldin nimalar tayyor bo'lishi kerak.
- **II qism — To'liq o'rnatish.** Server va filial kompyuterlarini noldan ishchi holatga keltirish.

Arxitektura, brending nuqtalari va xavfsizlik modeli haqida: [`README.md`](../README.md).

Serverni avval internetli tarmoqda sinab, keyin yopiq tarmoqqa ko'chirmoqchi bo'lsangiz:
[`KOCHIRISH.md`](KOCHIRISH.md) (Qo'llanma 2).

---

# I QISM. TALABLAR

## 1. Markaziy server

### 1.1. Uskuna (tavsiya)

| Qurilmalar soni | CPU | RAM | Disk | DB |
|---|---|---|---|---|
| 100 tagacha | 2 vCPU | 4 GB | 40 GB | NeDB yoki MongoDB |
| 100 – 1 000 | 4 vCPU | 8 GB | 100 GB SSD | MongoDB |
| 1 000 – 3 000 | 8 vCPU | 16 GB | 200 GB SSD | MongoDB |

Diskning katta qismini zaxiralar (`data/meshcentral-backups/`, 14 kun) va, yoqilsa, sessiya
yozuvlari egallaydi. Sessiya yozuvini (`_sessionRecording`) yoqsangiz diskni 2–3 baravar oshiring.

### 1.2. Operatsion tizim va dasturlar

| Komponent | Talab |
|---|---|
| OS | Ubuntu 22.04 / 24.04 LTS, Debian 12 yoki Rocky/RHEL 9 (x86_64) |
| Docker Engine | 24+ |
| Docker Compose plugin | **2.20+** (`depends_on: required: false` uchun) |
| Utilitalar | `git`, `curl`, `jq`, `openssl`, `envsubst` (paket: `gettext-base` / `gettext`) |
| Huquq | `root` yoki `sudo` |

Internet bor serverda `setup.sh` Docker va utilitalarni o'zi o'rnatadi. Air-gapped serverda
ular **oldindan** o'rnatilgan bo'lishi kerak (2.3-bo'lim).

### 1.3. Tarmoq

| Yo'nalish | Port | Kimdan | Majburiy |
|---|---|---|---|
| Kiruvchi | **443/tcp** | filial kompyuterlari (agentlar) va administratorlar | ha |
| Kiruvchi | 80/tcp | administratorlar (faqat 443 ga yo'naltiradi) | yo'q |
| Kiruvchi | 51820/udp | WireGuard (server VPN hub bo'lsa) | sizning VPN sxemangizga bog'liq |
| Chiquvchi | — | ish vaqtida internetga chiqish **kerak emas** | — |

- Serverda **o'zgarmas manzil** bo'lishi shart: statik IP (masalan WireGuard `10.8.0.1`) yoki
  ichki DNS nomi (`rmm.corp.local`). Bu manzil har bir agentga tikiladi — keyin o'zgartirish
  hamma agentni qayta o'rnatishni talab qiladi. **DNS nom tavsiya etiladi.**
- Har bir filial tarmog'idan serverning 443-portiga **to'g'ridan-to'g'ri marshrut** bo'lishi kerak
  (agentlar tizim proksisini e'tiborsiz qoldiradi — `agentNoProxy`).
- Filial tarmoqlari `.env` dagi `AGENT_ALLOWED_IP` ichida bo'lishi kerak.

### 1.4. Build mashinasi (faqat air-gapped server uchun)

Image'lar internetga ega mashinada yig'ilib, serverga ko'chiriladi. Shu mashinada kerak:

- Docker Engine 24+, `git`, `jq`, 15 GB bo'sh disk
- Quyidagi manzillarga kirish: `github.com`, `objects.githubusercontent.com`,
  `registry.npmjs.org`, `registry-1.docker.io`, `dl-cdn.alpinelinux.org`, `deb.debian.org`

Bu rolni GitHub Actions ham bajara oladi (`server-image` workflow, `offline_bundle: true`).

## 2. Filial kompyuterlari (client)

| Talab | Qiymat |
|---|---|
| OS | Windows 10 (1809+) yoki 11 — **Home, Pro, Enterprise**; Windows Server 2016+ |
| Arxitektura | x64, x86 yoki ARM64 (installer o'zi tanlaydi) |
| PowerShell | 5.1 (Windows bilan birga keladi) |
| Huquq | o'rnatish administrator yoki SYSTEM nomidan |
| Tarmoq | `SERVER_HOST:443` ga TCP ulanish |
| Sertifikat | **hech narsa o'rnatish kerak emas** (Root CA yo'q) |
| Antivirus | Defender/AV agentni "remote admin tool" deb belgilashi mumkin — markaziy siyosatda ruxsat bering (5.6-bo'lim) |

## 3. Sizdan nima talab qilinadi

**Majburiy hech narsa yo'q.** Repo to'liq sozlangan holda keladi:

| Narsa | Holati |
|---|---|
| Upstream MeshCentral | `upstream.lock` da aniq commit (1.3.2) — fork kerak emas |
| Brending | standart nomlar (`Korxona RMM`, xizmat `EnterpriseAgent`) va vaqtinchalik logolar tayyor |
| Server manzili | `setup.sh` serverning IP'sini o'zi aniqlaydi |
| Parollar, kalitlar, sertifikatlar | `setup.sh` o'zi generatsiya qiladi va `.env` ga yozadi |
| Admin akkaunti, qurilma guruhi | avtomatik yaratiladi (`admin`, `Filiallar`) |
| Filial IP diapazonlari | standart: barcha xususiy tarmoqlar (`10/8`, `172.16/12`, `192.168/16`) |
| Windows installer | avtomatik yig'iladi |

### Ixtiyoriy: o'zingizga moslash

O'rnatishdan **oldin** o'zgartirsangiz — darhol qo'llanadi; keyin o'zgartirsangiz —
`sudo ./update.sh --config` (matn/rasm) yoki `sudo ./update.sh` (nomlar view'larga build vaqtida yoziladi).

| Nima | Qayerda |
|---|---|
| Korxona va mahsulot nomi, agent xizmati nomi, ranglar | `branding/brand.env` |
| Logotiplar (o'lchamlar quyida) | `branding/assets/`, `branding/web/public/` |
| Server manzilini aniq berish (DNS nom tavsiya) | `setup.sh --host rmm.corp.local` |
| Filial va admin IP diapazonlarini cheklash | `.env` → `AGENT_ALLOWED_IP`, `USER_ALLOWED_IP` |
| Installer'ni code-signing sertifikati bilan imzolash | `.env` → `CODESIGN_PFX`, `CODESIGN_PASS` |
| Korxona CA bergan TLS sertifikati | `data/tls/server.crt` + `server.key`, keyin `sudo ./update.sh --config` |

Logotip fayllari (nomlari aynan shunday bo'lsin):

| Fayl | O'lcham | Qayerda ko'rinadi |
|---|---|---|
| `branding/assets/title.png` | 450×66 | web-panel yuqori chap burchagi |
| `branding/assets/login.png` | 600×150 (shaffof fon) | login sahifasi |
| `branding/assets/welcome.jpg` | 900×400 | login sahifasidagi rasm |
| `branding/assets/agent.ico` | 16…256 px, ko'p o'lchamli ICO | agent EXE va installer ikonkasi |
| `branding/web/public/favicon.ico` | 16/32/48 | brauzer tab |
| `branding/web/public/favicon-16x16.png`, `favicon-32x32.png` | 16, 32 | brauzer |
| `branding/web/public/android-chrome-192x192.png`, `-512x512.png` | 192, 512 | mobil / PWA |
| `branding/web/public/images/logoback.png` | 512×512 | mobil fon |

## 4. Tayyorgarlik nazorat ro'yxati

- [ ] Server: Ubuntu 22.04/24.04 (yoki Debian 12 / Rocky 9) o'rnatilgan, statik IP
- [ ] 443 port bo'sh: `ss -ltnp | grep ':443'` hech narsa ko'rsatmaydi
- [ ] Filiallardan serverga 443/tcp ochiq (VPN, marshrut, firewall)
- [ ] Sinov uchun kamida bitta Windows **Home** va bitta **Pro** kompyuter (yoki VM)

---

# II QISM. TO'LIQ O'RNATISH VA ISHGA TUSHIRISH

> Korxona tarmog'ingiz internetga ulanmagan bo'lsa: serverni avval shu qo'llanma bo'yicha
> **internetli** mashinada o'rnatib sinang, keyin [`KOCHIRISH.md`](KOCHIRISH.md) bo'yicha
> yopiq tarmoqqa ko'chiring.

## 1-qadam. Server firewall'i

Ubuntu/Debian (ufw):

```bash
sudo ufw allow 443/tcp && sudo ufw allow 80/tcp && sudo ufw allow OpenSSH && sudo ufw enable
```

Rocky/RHEL (firewalld):

```bash
sudo firewall-cmd --permanent --add-service=https --add-service=http && sudo firewall-cmd --reload
```

> Docker o'zi `iptables` qoidalarini qo'shadi; yuqoridagilar host firewall'i yoqilgan bo'lsa kerak.

## 2-qadam. Markaziy serverni o'rnatish (bitta buyruq)

### 2.1. O'rnatish

```bash
curl -fsSL https://raw.githubusercontent.com/javoxiro7o3/mesh-central/HEAD/install.sh | sudo bash
```

Bu buyruq: `git` o'rnatadi → repo'ni `/opt/mesh-central` ga oladi → `setup.sh` ni ishga tushiradi.
`setup.sh` esa Docker'ni o'rnatadi, parollarni generatsiya qiladi, TLS sertifikat, config, image
(10–20 daqiqa), admin, qurilma guruhi va Windows installer'ni tayyorlaydi va oxirida
**selftest** bilan hammasini tekshiradi.

Server manzilini aniq berish (masalan DNS nom yoki WireGuard IP):

```bash
curl -fsSL https://raw.githubusercontent.com/javoxiro7o3/mesh-central/HEAD/install.sh | sudo bash -s -- --host rmm.corp.local
```

100 tagacha qurilma uchun MongoDB o'rniga yengilroq NeDB (o'rnatishdan **oldin**):

```bash
sudo mkdir -p /opt/mesh-central && sudo git clone https://github.com/javoxiro7o3/mesh-central.git /opt/mesh-central
```

```bash
cd /opt/mesh-central && sudo cp .env.example .env && sudo sed -i 's/^DB_ENGINE=.*/DB_ENGINE=nedb/' .env && sudo ./setup.sh
```

Oxirida shunday blok chiqadi:

```
==================== TAYYOR ====================
 Web-panel : https://192.168.1.50:443/
 Login     : admin
 Parol     : Xk3...Aa1!  (avtomatik — .env da saqlangan, birinchi kirishda almashtiring)
 Installer : agent/out/EnterpriseAgent_Setup.exe
 Zaxira    : data/meshcentral-backups/ (har 24 soatda)
==================================================
SELFTEST: 13/13 OK
```

Parolni keyin ham ko'rish mumkin:

```bash
sudo grep ADMIN_PASSWORD /opt/mesh-central/.env
```

### 2.2. Serverni tekshirish

Bitta buyruq bilan to'liq tekshiruv (o'rnatish oxirida avtomatik ham ishlaydi):

```bash
cd /opt/mesh-central && sudo scripts/selftest.sh
```

U tekshiradi: konteynerlar sog'lom; web-panel nginx orqali HTTPS'da ochiladi va brend nomi
ko'rinadi; installer tayyor va `/dl/` orqali yuklanadi; installer ichidagi ServerID va server
manzili to'g'ri; **haqiqiy MeshAgent** (Linux versiyasi, shu serverning o'zida vaqtincha)
server manzili orqali ulanib online bo'ladi; server internetga chiqishga urinmagan.
Oxirida `SELFTEST: N/N OK` chiqishi kerak.

Qo'lda tekshirish:

```bash
cd /opt/mesh-central && sudo docker compose ps
```

Kutilgan holat: `meshcentral`, `nginx` (va `mongodb`) — `Up … (healthy)`.

```bash
curl -sk https://127.0.0.1/health.ashx
```

Javob: `ok`. (`.env` da `SERVER_BIND` berilgan bo'lsa, `127.0.0.1` o'rniga shu IP'ni yozing.)

```bash
sudo docker compose logs --tail 30 meshcentral
```

Logda bo'lishi kerak:
- `MeshCentral HTTP server running on port 4430, alias port 443.`
- `Loaded web certificate from "file:///opt/meshcentral/tls/server.crt"`
- `Code signed MeshService64.exe.`

`Agent downloads are disabled and meshagent_arm, … are missing` ogohlantirishi — **normal**:
Windows va Linux x64/ARM64 dan boshqa platformalar agentlari ataylab qo'shilmagan.

### 2.3. Web-panelga birinchi kirish

1. Administrator kompyuterida brauzerda `https://rmm.corp.local/` ni oching.
2. Self-signed sertifikat ogohlantirishi chiqadi — bu **faqat administrator brauzerlariga**
   taalluqli. Variantlar:
   - "Advanced → Proceed" (test uchun);
   - `data/tls/server.crt` ni faqat admin kompyuterlarining "Trusted Root" omboriga import qilish;
   - korxona CA'sidan sertifikat olib, `data/tls/server.crt` + `server.key` ga qo'yish va
     `sudo ./update.sh --config`.
   Filial kompyuterlariga bularning hech biri kerak emas.
3. `.env` dagi `ADMIN_USER` / `ADMIN_PASSWORD` bilan kiring.

**Muhim — akkauntlar siyosati:** `ADMIN_USER` akkaunti avtomatlashtirish (installer build,
`meshctrl`) uchun ishlatiladi. Shuning uchun:

- unga **2FA yoqmang** va parolini UI'da o'zgartirsangiz `.env` dagi `ADMIN_PASSWORD` ni ham yangilang;
- har bir xodim uchun alohida shaxsiy akkaunt yarating ("My Users" → "Add User"), ularga
  2FA yoqing va kerakli qurilma guruhlariga huquq bering;
- kundalik ishni shaxsiy akkauntlar bilan qiling.

### 2.4. Qo'shimcha qurilma guruhlari (ixtiyoriy)

Har bir filial uchun alohida guruh va alohida installer:

1. Web-panel → "My Devices" → "Add Device Group" (masalan `Samarqand`).
2. Serverda:

```bash
sudo agent/build-agent.sh --group "Samarqand"
```

Natija: `agent/out/EnterpriseAgent_Setup_Samarqand.exe`.

## 3-qadam. Installer'ni yig'ish va tekshirish

`setup.sh` installer'ni avtomatik yig'adi. Qayta yig'ish:

```bash
cd /opt/mesh-central && sudo agent/build-agent.sh
```

Skript har safar tekshiradi va xato bo'lsa to'xtaydi:

- `ServerID SHA384 pin agent-sertifikat bilan mos`
- `MeshServer URL to'g'ri` (`wss://<SERVER_HOST>:443/agent.ashx`)
- `nocertstore=1`

Natija fayllari (`agent/out/`):

| Fayl | Vazifasi |
|---|---|
| `EnterpriseAgent_Setup.exe` | tarqatiladigan installer |
| `EnterpriseAgent_Setup.exe.sha256` | yaxlitlik tekshiruvi |
| `EnterpriseAgent_Setup.build-info.json` | guruh, server, ServerID, versiya, git commit |
| `Filiallar.msh` | audit uchun (tarqatilmaydi, `/dl/` orqali yopiq) |

Installer LAN ichida yuklab olish uchun avtomatik joylashadi:
`https://rmm.corp.local/dl/EnterpriseAgent_Setup.exe`.

**Installer versiyasi:** `branding/brand.env` dagi `AGENT_FILE_VERSION`. Installer shu versiya
allaqachon o'rnatilgan kompyuterda hech narsa qilmaydi. GPO orqali hammaga majburiy qayta
o'rnatish kerak bo'lsa — versiyani oshiring (`1.0.0.0` → `1.0.1.0`) va qayta yig'ing.

## 4-qadam. Filial kompyuterlariga o'rnatish

Installer UI'siz ishlaydi va hech narsa so'ramaydi. Yagona istisno — foydalanuvchi o'zi ishga
tushirsa Windows UAC administrator tasdig'ini so'raydi. Ommaviy o'rnatishda SYSTEM nomidan
ishga tushiradigan usulni tanlang (B, C, D).

### A. Qo'lda (bitta kompyuter, test)

1. `https://rmm.corp.local/dl/EnterpriseAgent_Setup.exe` dan yuklab oling yoki fleshkada olib boring.
2. Administrator sifatida buyruq satrini oching va:

```bat
EnterpriseAgent_Setup.exe
```

Natija kodini ko'rish:

```bat
echo %ERRORLEVEL%
```

`0` — muvaffaqiyat. Boshqa kodlar: `1` agent o'rnatilmadi, `2` xizmat ishga tushmadi, `3` admin huquqi yo'q.

### B. Group Policy (domen kompyuterlari)

1. Installer'ni barcha kompyuterlar o'qiy oladigan papkaga qo'ying:
   `\\fileserver\it$\rmm\EnterpriseAgent_Setup.exe` ("Domain Computers" — Read).
2. GPMC → yangi GPO → `Computer Configuration → Policies → Windows Settings → Scripts (Startup/Shutdown) → Startup`
   → "Add" → Script name: `\\fileserver\it$\rmm\EnterpriseAgent_Setup.exe`.
3. GPO'ni filial kompyuterlari OU'siga bog'lang.
4. Kompyuterlar qayta yuklanganda SYSTEM nomidan o'rnatiladi; keyingi yuklanishlarda installer
   versiyani ko'rib hech narsa qilmaydi.

### C. PsExec (domen bo'lmasa ham, admin paroli ma'lum bo'lsa)

```bat
psexec \\PC-FILIAL-01 -s -c -f EnterpriseAgent_Setup.exe
```

Ko'p kompyuterga (`kompyuterlar.txt` — har qatorda bitta nom):

```bat
psexec @kompyuterlar.txt -s -c -f EnterpriseAgent_Setup.exe
```

### D. Intune / SCCM (MECM)

- Intune: `IntuneWinAppUtil.exe` bilan `.intunewin` qiling → Win32 app.
  - Install command: `EnterpriseAgent_Setup.exe`
  - Uninstall command: `EnterpriseAgent_Setup.exe /UNINSTALL`
  - Install behavior: **System**
  - Detection rule: Registry `HKLM\SOFTWARE\EnterpriseAgent\Agent`, value `InstallerVersion` = `1.0.0.0`
- SCCM: Application → Script Installer, xuddi shu buyruqlar va detection.

### E. Windows Home kompyuterlari

Home'da domen va GPO yo'q — A yoki C usulidan foydalaning (C uchun kompyuterda mahalliy
administrator akkaunti va "File and Printer Sharing" yoqilgan bo'lishi kerak). O'rnatilgandan
keyin Home va Pro o'rtasida farq yo'q: Desktop (KVM), Terminal (SYSTEM) va Files to'liq ishlaydi,
chunki ular RDP'ga emas, agentning o'ziga tayanadi.

## 5-qadam. Tekshiruv

### 5.1. Serverda

Web-panel → "My Devices" → `Filiallar` guruhida kompyuter **yashil (online)** ko'rinishi kerak
(odatda 10–30 soniya ichida).

### 5.2. Filial kompyuterida

PowerShell (administrator):

```powershell
Get-Content C:\ProgramData\EnterpriseAgent\install.log -Tail 20
```

Oxirgi qatorda `OK: agent ishlayapti (PID …) va rmm.corp.local:443 ga ulangan` bo'lishi kerak.

```powershell
Get-Service EnterpriseAgent
```

```powershell
sc.exe qfailure EnterpriseAgent
```

Kutilgan: `RESTART -- Delay = 5000 milliseconds` (3 marta).

```powershell
Get-ScheduledTask -TaskName EnterpriseAgent-Watchdog
```

```powershell
Get-NetFirewallRule -Group "Korxona RMM Agent" | Select DisplayName, Direction, Enabled
```

(Guruh nomi = `BRAND_NAME` + " Agent".)

```powershell
powercfg /q SCHEME_CURRENT SUB_SLEEP STANDBYIDLE
```

Kutilgan: `Current AC Power Setting Index: 0x00000000`.

```powershell
Get-ChildItem Cert:\LocalMachine\Root, Cert:\LocalMachine\My | Where-Object { $_.Subject -match 'Mesh|Korxona' }
```

Hech narsa chiqmasligi kerak — sertifikat omborlariga yozuv yo'q.

### 5.3. Funksional test

| Test | Qanday | Kutilgan |
|---|---|---|
| Desktop | qurilma → "Desktop" → "Connect" | ekran ko'rinadi; foydalanuvchida bildirishnoma va maxfiylik paneli |
| Terminal | "Terminal" → "Admin Shell" | `whoami` → `nt authority\system` |
| Files | "Files" | `C:\` ko'rinadi, fayl yuklash/olish ishlaydi |
| Recovery | PowerShell: `Stop-Process -Name MeshAgent -Force` | ~5 s da xizmat qayta ishlaydi, qurilma online |
| Watchdog | `Stop-Service EnterpriseAgent` | ≤1 daqiqada qayta ishlaydi |
| Sleep | kompyuterni bir necha soat qoldiring | uxlamaydi, online qoladi |
| Reboot | qurilma → "Actions" → "Restart" | qayta yuklangandan keyin o'zi online bo'ladi |

> `MeshAgent.exe` — o'rnatilgan agent jarayoni nomi (fayl nomi o'zgarmaydi, xizmat nomi
> `EnterpriseAgent`). Aniq yo'l: `(Get-CimInstance Win32_Service -Filter "Name='EnterpriseAgent'").PathName`.

### 5.4. Agentni o'chirish

```bat
EnterpriseAgent_Setup.exe /UNINSTALL
```

Agent, xizmat, firewall qoidalari va watchdog o'chiriladi. Web-panelda qurilmani qo'lda o'chiring
("Actions" → "Delete Device").

### 5.5. Agentning o'zini yangilash

Qayta o'rnatish kerak emas. Server yangilanganda (`sudo ./update.sh`) ulangan agentlar avtomatik
yangilanadi. Installer'ni faqat yangi kompyuterlar uchun tarqatasiz.

### 5.6. Antivirus

Ba'zi AV'lar (shu jumladan Defender) MeshAgent'ni "RemoteAdmin" turidagi dastur sifatida
belgilashi mumkin. Installer o'zi istisno **qo'shmaydi**. Markaziy siyosatda (Intune / GPO /
AV konsoli) ruxsat bering: installer va agent fayllarining SHA256 bo'yicha yoki — installer
imzolangan bo'lsa — imzo bo'yicha.

## 6-qadam. Kundalik ekspluatatsiya

| Vazifa | Buyruq |
|---|---|
| Holat | `cd /opt/mesh-central && sudo docker compose ps` |
| Loglar | `sudo docker compose logs -f meshcentral` |
| Restart | `sudo docker compose restart meshcentral` |
| To'liq yangilash | `sudo ./update.sh` |
| Faqat config/brending | `sudo ./update.sh --config` |
| Air-gapped yangilash | `sudo ./update.sh --bundle FILE` |
| Ortga qaytish | `sudo ./update.sh --rollback` |
| Installer qayta yig'ish | `sudo agent/build-agent.sh` |

**Zaxiralash.** Avtomatik zaxira har 24 soatda `data/meshcentral-backups/` ga yoziladi
(parol: `.env` → `BACKUP_ZIP_PASSWORD`). Bundan tashqari, serverdan **tashqariga** muntazam
nusxalang:

- `.env`
- `data/meshcentral-data/` (ayniqsa `*.key`, `*.crt` — agent-server sertifikati; yo'qolsa
  barcha agentlarni qayta o'rnatishga to'g'ri keladi)
- `data/tls/`
- `data/meshcentral-backups/`

**Server ko'chirilganda** shu fayllarni yangi serverga qo'yib, `sudo ./setup.sh` ni ishga
tushiring — sertifikatlar va `SERVER_HOST` saqlangani uchun agentlar o'zi ulanadi.

## 7-qadam. Muammolarni hal qilish

| Belgi | Sabab | Yechim |
|---|---|---|
| `setup.sh`: `docker compose` xatosi `required` haqida | Compose < 2.20 | Docker compose plugin'ni yangilang |
| `nginx` 502 Bad Gateway | `meshcentral` hali ishga tushmagan yoki xato | `sudo docker compose logs meshcentral` |
| `mongodb` unhealthy, auth xatosi | `MONGO_ROOT_PASSWORD` birinchi ishga tushirishdan keyin o'zgartirilgan | parolni avvalgisiga qaytaring (Mongo uni faqat birinchi ishga tushishda o'rnatadi) |
| `build-agent.sh`: `meshctrl ishlamadi` | `ADMIN_PASSWORD` UI'da o'zgargan yoki 2FA yoqilgan | `.env` ni yangilang; avtomatlashtirish akkauntidan 2FA'ni olib tashlang |
| `build-agent.sh`: `ServerID mos emas` | `data/meshcentral-data` sertifikatlari almashtirilgan | zaxiradan sertifikatlarni tiklang |
| `build-agent.sh`: `MeshServer kutilganidan farq qiladi` | `config.json` `cert` ≠ `SERVER_HOST` | `sudo ./update.sh --config` |
| install.log: `xizmati topilmadi` (exit 1) | AV agentni bloklagan | AV karantinini tekshiring, 5.6 |
| install.log: `WARN … ulanish ko'rinmadi` | tarmoq/VPN yoki allowlist | klientda `Test-NetConnection rmm.corp.local -Port 443`; filial subneti `AGENT_ALLOWED_IP` da borligini tekshiring |
| Qurilma ko'rinmaydi, `Test-NetConnection` OK | DNS boshqa IP'ga yo'naltiradi | klientda `Resolve-DnsName rmm.corp.local` |
| Installer hech narsa qilmadi, exit 0 | shu versiya allaqachon o'rnatilgan | `/FORCE` yoki `AGENT_FILE_VERSION` ni oshiring |
| `SERVER_HOST` o'zgarishi kerak | manzil agent ichiga tikilgan | yangi installer yig'ib, hammaga `/FORCE` bilan qayta o'rnating (shuning uchun DNS nom tavsiya etiladi) |

Klient logi: `C:\ProgramData\EnterpriseAgent\install.log`. Server loglari:
`sudo docker compose logs meshcentral nginx mongodb`.
