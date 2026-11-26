# Qo'llanma 2. Sinovdan o'tgan serverni yopiq tarmoqqa ko'chirish

Bu qo'llanma quyidagi ssenariy uchun:

1. Server avval **internetli** tarmoqda o'rnatiladi va sinovdan o'tkaziladi. Bu bosqichda
   internetdan kerak bo'lgan hamma narsa yuklab olinadi.
2. Sinov muvaffaqiyatli bo'lgach, server **to'liq nusxa** qilib olinadi.
3. Nusxa **internetga ulanmagan** korxona tarmog'idagi serverga ko'chiriladi.
4. Yopiq tarmoqning IP manzillari butunlay boshqa — server shu tarmoqqa **qayta sozlanadi**.

Server o'rnatish bo'yicha asosiy qo'llanma: [`ORNATISH.md`](ORNATISH.md).

---

## Qisqa javob: mumkinmi?

**Ha, mumkin.** Ko'chirishdan keyin serverning manzilini yangi tarmoqqa bitta buyruq bilan
moslash mumkin. Bu MeshCentral 1.3.2 da sinab ko'rildi: server manzili `mesh.corp.test` dan
`192.168.50.10` ga o'zgartirilganda server shaxsi (ServerID) o'zgarmadi va yangi agentlarga
yangi manzil yozildi.

### Ko'chirishda nima saqlanadi, nima o'zgaradi

| Narsa | Holati | Izoh |
|---|---|---|
| Docker image'lar (MeshCentral, MongoDB, nginx, NSIS) | saqlanadi | paket ichida, internet kerak emas |
| Agent binarlari, npm modullar, tarjimalar | saqlanadi | image ichida |
| Ma'lumotlar bazasi: foydalanuvchilar, guruhlar, sozlamalar | saqlanadi | `data/` to'liq ko'chiriladi |
| Parollar va kalitlar (`.env`) | saqlanadi | adminga o'sha parol bilan kirasiz |
| Brending | saqlanadi | |
| **Server shaxsi — ServerID** (agent-server sertifikati) | **saqlanadi** | eng muhimi: yopiq tarmoqda yangi o'rnatilgan agentlar uni tekshiradi |
| Server manzili (`SERVER_HOST`) | **o'zgaradi** | yangi tarmoq IP'si yoki DNS nomi |
| nginx TLS sertifikati | qayta yaratiladi | yangi manzil bilan |
| MeshCentral web va codesign sertifikatlari | server o'zi qayta yaratadi | logda `does not match name in TLS certificate` xabari chiqadi — bu **normal** |
| IP allowlist'lar | o'zgaradi | yangi tarmoq diapazonlari |
| Windows installer | qayta yig'iladi | yangi manzil ichiga tikiladi |
| Sinov tarmog'ida o'rnatilgan agentlar | **yangi serverga ulanmaydi** | ularga eski manzil tikilgan; sinov kompyuterlari yozuvlari o'chiriladi |

### Eng muhim tavsiya: IP o'rniga DNS nom

Agar yopiq tarmoqda ichki DNS bo'lsa (yoki uni qo'shish mumkin bo'lsa), serverga **boshidanoq
DNS nom** bering, masalan `rmm.corp.local`:

- sinov tarmog'ida: shu nomni sinov server IP'siga yo'naltiring (DNS yoki sinov kompyuterlaridagi
  `hosts` fayli orqali);
- yopiq tarmoqda: xuddi shu nomni yangi server IP'siga yo'naltiring.

Natijada `SERVER_HOST` o'zgarmaydi, TLS sertifikati va installer ham o'zgarmaydi, kelajakda
server IP'si yana o'zgarsa ham agentlarni qayta o'rnatish kerak bo'lmaydi — faqat DNS yozuvi
yangilanadi. IP bilan ishlasangiz ham hammasi ishlaydi, faqat har bir manzil o'zgarishida
installer'ni qayta tarqatishga to'g'ri keladi.

---

## Umumiy jarayon

```
 INTERNETLI TARMOQ (sinov)                         YOPIQ TARMOQ (ishchi)
 ┌───────────────────────────────┐                 ┌───────────────────────────────────┐
 │ 1. sudo ./setup.sh            │                 │ 4. tar -xf mesh-transfer-*.tar     │
 │ 2. sinov (2–3 kompyuter)      │   fleshka /     │ 5. sudo ./import-airgap.sh         │
 │ 3. sudo scripts/              │ ──────────────▶ │      --host <YANGI IP yoki DNS>    │
 │    export-airgap.sh           │  xavfsiz disk   │      --agent-ip <filial tarmoqlari>│
 │    --with-debs                │                 │ 6. tekshiruv                       │
 │ => mesh-transfer-*.tar        │                 │ 7. filiallarga yangi installer     │
 └───────────────────────────────┘                 └───────────────────────────────────┘
```

---

## 0-bosqich. Oldindan rejalashtirish

Quyidagilarni ko'chirishdan **oldin** aniqlab qo'ying:

| # | Savol | Nega muhim |
|---|---|---|
| 1 | Yopiq tarmoqdagi server IP'si (yoki DNS nomi) | `--host` parametri |
| 2 | Filial kompyuterlari joylashgan IP diapazonlar | `--agent-ip` (masalan `192.168.0.0/16,10.20.0.0/16`) |
| 3 | Administratorlar kompyuterlari diapazoni (ixtiyoriy) | `--user-ip` |
| 4 | Yopiq tarmoqda `172.31.250.0/24` ishlatiladimi? | Docker ichki tarmog'i bilan konflikt — bo'lsa `--mesh-net` bilan boshqasini bering |
| 5 | Yopiq serverning OS'i va versiyasi | Docker paketlari (`--with-debs`) **aynan shu OS versiyasi** uchun bo'lishi kerak |
| 6 | Yopiq serverda Docker bormi? | yo'q bo'lsa paketlar eksportga qo'shiladi |
| 7 | Ko'chirish usuli | paket hajmi taxminan 1–2 GB; shifrlangan fleshka tavsiya etiladi |

**Eng oson yo'l:** sinov serveri va yopiq server **bir xil OS versiyasida** bo'lsin (masalan,
ikkalasi ham Ubuntu 24.04). Shunda sinov serveridan olingan Docker paketlari yopiq serverga
to'g'ridan-to'g'ri o'rnatiladi.

---

## 1-bosqich. Internetli tarmoqda o'rnatish

Internetli serverda bitta buyruq:

```bash
curl -fsSL https://raw.githubusercontent.com/javoxiro7o3/mesh-central/HEAD/install.sh | sudo bash
```

Server IP'si avtomatik aniqlanadi. Oxirida `SELFTEST: N/N OK` chiqishi kerak.
Batafsil: [`ORNATISH.md`](ORNATISH.md), 1–3 qadamlar.

DNS nom ishlatmoqchi bo'lsangiz (tavsiya), uni aniq bering — sinov tarmog'ida bu nom sinov
server IP'siga yo'naltirilgan bo'lsin (DNS yoki sinov kompyuterlaridagi `hosts` fayli):

```bash
curl -fsSL https://raw.githubusercontent.com/javoxiro7o3/mesh-central/HEAD/install.sh | sudo bash -s -- --host rmm.corp.local
```

> Bu bosqichda internetdan yuklanadigan hamma narsa (MeshCentral manba kodi, npm modullar,
> agent binarlari, MongoDB va nginx image'lari, NSIS) shu serverga tushadi va keyin eksport
> paketiga kiradi.

---

## 2-bosqich. Sinov

Sinovni internetli tarmoqda to'liq o'tkazing — yopiq tarmoqda xatoni tuzatish qiyinroq.
Kamida bitta Windows **Home** va bitta **Pro** kompyuterda:

- [ ] Installer o'rnatildi, `C:\ProgramData\EnterpriseAgent\install.log` da `OK: agent ishlayapti …`
- [ ] Qurilma web-panelda online
- [ ] Desktop (masofaviy ekran), Terminal (`whoami` → `nt authority\system`), Files ishlaydi
- [ ] Xizmat jarayoni o'ldirilganda ~5 soniyada qaytadi
- [ ] Kompyuter uxlab qolmaydi
- [ ] Brending (logotip, nomlar) to'g'ri
- [ ] Qo'shimcha foydalanuvchilar va guruhlar kerakli tartibda yaratildi (ular ham ko'chadi)

Batafsil tekshiruv buyruqlari: [`ORNATISH.md` → 5-qadam](ORNATISH.md#5-qadam-tekshiruv).

Sinov kompyuterlaridan agentni o'chirib qo'ying (ular yopiq serverga baribir ulanmaydi):

```bat
EnterpriseAgent_Setup.exe /UNINSTALL
```

---

## 3-bosqich. Eksport (internetli sinov serverida)

```bash
cd /opt/mesh-central
```

```bash
sudo scripts/export-airgap.sh --with-debs
```

`--with-debs` Docker Engine, Compose, `jq` va `envsubst` paketlarini qo'shadi. Yopiq serverda
Docker allaqachon o'rnatilgan bo'lsa, bu parametrni tashlab ketishingiz mumkin.

Boshqa parametrlar:

| Parametr | Vazifasi |
|---|---|
| `--out /mnt/usb` | paketni to'g'ridan-to'g'ri fleshkaga yozish |
| `--no-backups` | `data/meshcentral-backups/` ni qo'shmaslik (paket kichikroq bo'ladi) |

Skript nima qiladi:

1. Barcha ishlatilayotgan image'larni tekshiradi (NSIS builder yo'q bo'lsa yig'adi).
2. `--with-debs` bo'lsa — OS paketlarini yuklaydi.
3. Ma'lumotlar bazasi izchil nusxalanishi uchun **stack'ni vaqtincha to'xtatadi**.
4. Repo, `.env` va `data/` ni arxivlaydi (fayl egalari saqlanadi).
5. Image'larni saqlaydi.
6. `MANIFEST.txt` va `SHA256SUMS` yaratadi, stack'ni qayta ishga tushiradi.

Natija:

```
dist/mesh-transfer-YYYYMMDD-HHMM.tar
dist/mesh-transfer-YYYYMMDD-HHMM.tar.sha256
```

Oxirida chiqadigan **ServerID** ning birinchi belgilarini yozib qo'ying — yopiq serverda
tekshirasiz.

> **Xavfsizlik.** Paket ichida `.env` (barcha parollar) va server sertifikatlarining shaxsiy
> kalitlari bor. Paketni egallagan odam sizning serveringiz nomidan agentlarni boshqara oladi.
> Shifrlangan tashuvchidan foydalaning va ko'chirib bo'lgach nusxalarni o'chiring.

---

## 4-bosqich. Yopiq tarmoqqa ko'chirish

1. Ikkala faylni (`.tar` va `.tar.sha256`) tashuvchiga yozing.
2. Yopiq serverga ko'chiring, masalan `/root/` ga.
3. Butunligini tekshiring:

```bash
cd /root && sha256sum -c mesh-transfer-*.tar.sha256
```

Natija `OK` bo'lishi kerak.

4. Paketni oching:

```bash
tar -xf mesh-transfer-*.tar
```

```bash
cd mesh-transfer-*/ && cat MANIFEST.txt
```

---

## 5-bosqich. Yopiq serverda import va yangi tarmoqqa moslash

### 5.1. Server firewall'ini oching

Ubuntu/Debian:

```bash
sudo ufw allow 443/tcp && sudo ufw allow 80/tcp
```

Rocky/RHEL:

```bash
sudo firewall-cmd --permanent --add-service=https --add-service=http && sudo firewall-cmd --reload
```

### 5.2. Import

Eng oddiy holat — server IP'si avtomatik aniqlanadi, filial diapazonlari standart (barcha
xususiy tarmoqlar):

```bash
sudo ./import-airgap.sh --purge-devices
```

Manzil va diapazonlarni aniq berish — IP bilan (misol — yopiq tarmoq `192.168.0.0/16`, server `192.168.50.10`):

```bash
sudo ./import-airgap.sh --host 192.168.50.10 --agent-ip 192.168.0.0/16 --purge-devices
```

DNS nom bilan (yopiq tarmoq DNS'ida `rmm.corp.local` → server IP):

```bash
sudo ./import-airgap.sh --host rmm.corp.local --agent-ip 10.20.0.0/16,10.30.0.0/16 --purge-devices
```

Yopiq tarmoqda `172.31.250.0/24` band bo'lsa, Docker ichki tarmog'ini almashtiring:

```bash
sudo ./import-airgap.sh --host 192.168.50.10 --agent-ip 192.168.0.0/16 --mesh-net 10.250.250 --purge-devices
```

### 5.3. Parametrlar

| Parametr | Majburiy | Vazifasi |
|---|---|---|
| `--host` | yo'q | yopiq tarmoqdagi server IP yoki DNS nomi — agentlar shu manzilga ulanadi. Berilmasa serverning IP'si avtomatik olinadi |
| `--agent-ip` | yo'q | filial kompyuterlari diapazonlari (vergul bilan). Bo'sh qatorni bersangiz (`--agent-ip ""`) cheklov olinadi |
| `--user-ip` | yo'q | administratorlar diapazoni; `127.0.0.1` avtomatik qo'shiladi |
| `--bind` | yo'q | nginx faqat shu IP'da tinglaydi (masalan VPN interfeysi) |
| `--mesh-net` | yo'q | Docker ichki tarmog'i (3 oktet), masalan `10.250.250` |
| `--keep-tls` | yo'q | korxona CA'sidan olingan sertifikatni `data/tls/` da saqlash (yangi manzil uning SAN'ida bo'lishi kerak) |
| `--purge-devices` | tavsiya | sinov tarmog'idagi qurilma yozuvlarini o'chirish |
| `--no-agent` | yo'q | installer'ni hozir yig'maslik |
| `--dir PATH` | yo'q | o'rnatish papkasi (standart `/opt/mesh-central`) |
| `--force` | yo'q | papka bo'sh bo'lmasa ham ustidan yozish |

### 5.4. Import nima qiladi

1. `SHA256SUMS` bo'yicha paket butunligini tekshiradi.
2. Docker yoki utilitalar yo'q bo'lsa — paket ichidagi `packages/` dan o'rnatadi.
3. Repo, `.env` va `data/` ni `/opt/mesh-central` ga ochadi.
4. Docker image'larni yuklaydi.
5. `scripts/reconfigure-network.sh` ni ishga tushiradi, u:
   - `.env` dagi manzil va allowlist'larni yangilaydi;
   - Docker ichki tarmog'i korxona tarmog'i bilan to'qnashmasligini tekshiradi;
   - nginx TLS sertifikatini yangi manzil bilan qayta yaratadi;
   - `config.json` ni qayta generatsiya qiladi;
   - stack'ni qayta yaratib ishga tushiradi;
   - (`--purge-devices` bilan) sinov qurilmalari yozuvlarini o'chiradi;
   - yangi manzil bilan Windows installer'ni yig'adi.
6. Oxirida `scripts/selftest.sh` bilan hammasini tekshiradi (haqiqiy agent ulanishi bilan).

Oxirida shunday blok chiqadi:

```
========== TARMOQ SOZLAMALARI YANGILANDI ==========
 Web-panel : https://192.168.50.10:443/
 Installer : agent/out/EnterpriseAgent_Setup.exe  (MeshServer=wss://192.168.50.10:443/agent.ashx)
 Eslatma   : eski manzil (rmm.corp.local) bilan o'rnatilgan agentlarga yangi installer'ni /FORCE bilan o'rnating.
===================================================
```

---

## 6-bosqich. Yopiq serverda tekshiruv

Import oxirida selftest avtomatik ishlaydi; istalgan vaqtda qayta:

```bash
cd /opt/mesh-central && sudo scripts/selftest.sh
```

`SELFTEST: N/N OK` — hammasi joyida. Qo'lda tekshirish:

```bash
cd /opt/mesh-central && sudo docker compose ps
```

Barcha servislar `Up … (healthy)` bo'lishi kerak.

```bash
curl -sk https://127.0.0.1/health.ashx
```

Javob: `ok`. (`--bind` bergan bo'lsangiz, `127.0.0.1` o'rniga shu IP'ni yozing.)

ServerID sinov serveridagi bilan bir xil ekanini tekshiring:

```bash
jq -r .serverId agent/out/EnterpriseAgent_Setup.build-info.json
```

Birinchi belgilari 3-bosqichda yozib olgan qiymat bilan mos kelishi kerak.

Installer yangi manzilni olganini tekshiring:

```bash
jq -r .meshServer agent/out/EnterpriseAgent_Setup.build-info.json
```

Kutilgan: `wss://<yangi manzil>:443/agent.ashx`.

Internetga chiqishga urinishlar yo'qligini tekshiring (bir necha daqiqa ishlagandan keyin):

```bash
sudo docker compose logs meshcentral | grep -iE "ENOTFOUND|EAI_AGAIN|getaddrinfo|npm ERR" || echo "tashqi ulanish urinishlari yo'q"
```

Web-panelga kiring: yopiq tarmoqdagi administrator kompyuterida `https://<yangi manzil>/`.
Login va parol — sinov serveridagi bilan **bir xil** (`.env` → `ADMIN_USER` / `ADMIN_PASSWORD`).
TLS sertifikati yangilangani uchun brauzer ogohlantirishi qayta chiqadi (admin kompyuterlariga
import qilgan bo'lsangiz, yangi `data/tls/server.crt` ni qayta import qiling).

---

## 7-bosqich. Filial kompyuterlariga o'rnatish

Yangi installer:

- serverda: `/opt/mesh-central/agent/out/EnterpriseAgent_Setup.exe`
- LAN orqali: `https://<yangi manzil>/dl/EnterpriseAgent_Setup.exe`

O'rnatish usullari (qo'lda, GPO, PsExec, Intune/SCCM) va tekshiruv:
[`ORNATISH.md` → 4-qadam](ORNATISH.md#4-qadam-filial-kompyuterlariga-ornatish).

Sinov tarmog'ida o'rnatilgan va yopiq tarmoqqa olib kelingan kompyuter bo'lsa, unga `/FORCE`
bilan qayta o'rnating:

```bat
EnterpriseAgent_Setup.exe /FORCE
```

---

## Keyinchalik

### Server IP'si yana o'zgarsa

Shu skriptni yopiq serverning o'zida ishga tushiring:

```bash
cd /opt/mesh-central && sudo scripts/reconfigure-network.sh --host 192.168.60.10
```

Diqqat: IP bilan ishlasangiz, o'rnatilgan barcha agentlarga yangi installer'ni `/FORCE` bilan
qayta tarqatish kerak bo'ladi. DNS nom bilan ishlasangiz — `--host` o'zgarmaydi, faqat DNS
yozuvini yangilaysiz va hech narsa qayta o'rnatilmaydi.

### Yopiq serverni yangilash

Internetli tarmoqdagi sinov serverini yangi versiyaga yangilang va sinab ko'ring
(`sudo ./update.sh`). Keyin yangi image'larni ko'chiring:

```bash
sudo scripts/make-offline-bundle.sh
```

Natijani (`dist/corp-mesh-offline-*.tar.gz`) yopiq serverga ko'chirib:

```bash
cd /opt/mesh-central && sudo ./update.sh --bundle /root/corp-mesh-offline-*.tar.gz
```

Bu buyruq yopiq serverning ma'lumotlari, `.env` va tarmoq sozlamalarini **saqlaydi**: faqat
image'lar va repo fayllari almashtiriladi. Agentlar server orqali o'zi yangilanadi.

> `export-airgap.sh` ni yangilash uchun **ishlatmang** — u sinov serverining ma'lumotlar
> bazasini ham olib keladi va yopiq serverdagi ish ma'lumotlarini almashtirib yuboradi.

### Zaxira

Yopiq serverdagi `data/` va `.env` ni muntazam ravishda server tashqarisiga nusxalang
([`ORNATISH.md` → 6-qadam](ORNATISH.md#6-qadam-kundalik-ekspluatatsiya)). Sinov serveri esa
ko'chirilgan holatning tayyor nusxasi sifatida saqlanib qoladi — yopiq serverda biror narsa
buzilsa, eksportni qaytadan qilish mumkin.

---

## Muammolarni hal qilish

| Belgi | Sabab | Yechim |
|---|---|---|
| `checksum mos emas` | paket ko'chirishda buzilgan | qayta ko'chiring; `sha256sum -c` bilan tekshiring |
| `Docker/utilitalar yo'q va paketda packages/ ham yo'q` | eksport `--with-debs` siz qilingan | `--with-debs` bilan qayta eksport qiling yoki Docker'ni qo'lda o'rnating |
| `dpkg xatosi` (bog'liqlik yetishmaydi) | yopiq server OS versiyasi sinov serverinikidan farq qiladi | aynan shu OS versiyasi uchun yetishmagan `.deb` larni olib keling yoki OS versiyalarini tenglang |
| `… bo'sh emas` | `/opt/mesh-central` da eski fayllar bor | `--dir` bilan boshqa papka yoki `--force` |
| `Host interfeysi … konflikt` / `marshrutlarida … konflikt` | Docker ichki tarmog'i korxona tarmog'i bilan to'qnashadi | `--mesh-net 10.250.250` (yoki boshqa bo'sh /24) |
| Logda `does not match name in TLS certificate` | server manzili o'zgargan | **normal** — server web va codesign sertifikatlarini o'zi qayta yaratadi |
| `mongodb` unhealthy | `data/mongodb` egalik huquqi buzilgan (masalan arxiv root bo'lmagan holda ochilgan) | `sudo chown -R 999:999 /opt/mesh-central/data/mongodb` va `sudo docker compose up -d` |
| Web-panelga kirib bo'lmaydi, `curl` ishlaydi | `--user-ip` administrator kompyuteri diapazonini o'z ichiga olmaydi | `sudo scripts/reconfigure-network.sh --host <manzil> --user-ip <to'g'ri diapazon>` |
| Agent o'rnatildi, lekin online emas | filial diapazoni `--agent-ip` da yo'q yoki 443 port yopiq | `--agent-ip` ni tuzating; klientda `Test-NetConnection <manzil> -Port 443` |
| Sinov kompyuteri yangi serverga ulanmaydi | unga eski manzil tikilgan | `EnterpriseAgent_Setup.exe /FORCE` |
| `ServerID` sinov serveridagidan farq qiladi | `data/meshcentral-data/agentserver-cert-*` ko'chmagan | eksportni qayta bajaring; `data/` to'liq ko'chganini tekshiring |
