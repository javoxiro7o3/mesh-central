# QO'LLANMA — boshidan oxirigacha

Sizning holatingiz uchun: korxona tarmog'i **internetga ulanmagan**. Shuning uchun server avval
internetli mashinada o'rnatiladi va sinaladi, keyin to'liq nusxasi yopiq tarmoqqa ko'chiriladi va
o'sha tarmoq manzillariga avtomatik moslanadi.

Hamma narsa sozlangan: fork qilish, fayl tahrirlash, parol o'ylab topish **kerak emas**.
Siz faqat quyidagi buyruqlarni ketma-ket bajarasiz.

Batafsil ma'lumot kerak bo'lsa: [`docs/ORNATISH.md`](docs/ORNATISH.md) (talablar, client
o'rnatish usullari, muammolar) va [`docs/KOCHIRISH.md`](docs/KOCHIRISH.md) (ko'chirish tafsilotlari).

---

## 0. Nima kerak

| # | Nima | Talab |
|---|---|---|
| 1 | **Sinov serveri** (internetli) | Ubuntu 24.04 (yoki 22.04 / Debian 12), 2+ CPU, 4+ GB RAM, 40+ GB disk, root huquqi. Virtual mashina ham bo'ladi |
| 2 | **Ishchi server** (yopiq tarmoqda) | **sinov serveri bilan aynan bir xil OS versiyasi**, resurslar qurilmalar soniga qarab (100 tagacha — 2 CPU/4 GB; 1000 tagacha — 4 CPU/8 GB/100 GB SSD) |
| 3 | Fleshka yoki tashqi disk | 4 GB+, tavsiya — shifrlangan |
| 4 | Sinov uchun Windows kompyuter | kamida bitta Windows 10/11 **Home** va bitta **Pro** (VM ham bo'ladi), sinov serveriga tarmoq orqali ulanadigan |
| 5 | Yopiq tarmoqda | filial kompyuterlaridan ishchi serverga **443/tcp** ochiq bo'lishi |

Filial kompyuterlari uchun hech narsa oldindan kerak emas (sertifikat, dastur va h.k.).

---

## 1. Sinov serverini o'rnatish (internetli tarmoq)

Sinov serverida bitta buyruq:

```bash
curl -fsSL https://raw.githubusercontent.com/javoxiro7o3/mesh-central/HEAD/install.sh | sudo bash
```

10–20 daqiqa davom etadi. O'zi bajaradi: Docker o'rnatish, barcha parol va kalitlarni
generatsiya qilish, MeshCentral'ni yig'ish (brending, internetsiz ishlash uchun barcha modullar
va agent fayllari ichiga), MongoDB, nginx, admin akkaunti, `Filiallar` qurilma guruhi,
Windows installer va yakuniy tekshiruv.

Oxirida shunday chiqishi kerak:

```
==================== TAYYOR ====================
 Web-panel : https://<server IP>:443/
 Login     : admin
 Parol     : ....................   <- yozib oling
 Installer : agent/out/EnterpriseAgent_Setup.exe
==================================================
SELFTEST: N/N OK
```

Parolni keyin ham ko'rish:

```bash
sudo grep ADMIN_PASSWORD /opt/mesh-central/.env
```

Server firewall'i yoqilgan bo'lsa (Ubuntu ufw):

```bash
sudo ufw allow 443/tcp && sudo ufw allow 80/tcp
```

---

## 2. Sinov (internetli tarmoqda)

### 2.1. Web-panel

Sinov tarmog'idagi kompyuterda brauzerda `https://<server IP>/` ni oching. Sertifikat
ogohlantirishi chiqadi ("Advanced → Proceed") — bu faqat administrator brauzeriga taalluqli,
filial kompyuterlariga ta'sir qilmaydi. `admin` va 1-bosqichdagi parol bilan kiring.

### 2.2. Windows sinov kompyuteriga agent o'rnatish

Windows kompyuterda brauzerda oching va faylni yuklab oling:

```
https://<server IP>/dl/EnterpriseAgent_Setup.exe
```

Administrator sifatida buyruq satrini oching, fayl turgan papkaga o'ting va:

```bat
EnterpriseAgent_Setup.exe
```

Hech qanday oyna chiqmaydi (faqat Windows UAC tasdig'i). 30–60 soniyadan keyin web-panelda
`Filiallar` guruhida kompyuter **online** ko'rinadi.

### 2.3. Tekshiring

| Nima | Qanday | Kutilgan |
|---|---|---|
| Ekran | qurilma → **Desktop** → Connect | ekran ko'rinadi, boshqarsa bo'ladi |
| Terminal | **Terminal** → Admin Shell → `whoami` | `nt authority\system` |
| Fayllar | **Files** | `C:\` ochiladi, fayl yuklash/olish ishlaydi |
| Avtomatik tiklanish | Windows'da admin PowerShell: `Stop-Service EnterpriseAgent` | ≤1 daqiqada qaytadi |
| Uyqu | kompyuterni bir necha soat qoldiring | uxlamaydi, online qoladi |
| Qayta yuklash | web-panel → Actions → Restart | o'zi online bo'ladi |

Windows kompyuterdagi log: `C:\ProgramData\EnterpriseAgent\install.log`
(oxirgi qatorda `OK: agent ishlayapti …`).

### 2.4. Sinov kompyuterlaridan agentni olib tashlang

Ularga sinov serverining manzili yozilgan, yopiq serverga baribir ulanmaydi:

```bat
EnterpriseAgent_Setup.exe /UNINSTALL
```

---

## 3. Ko'chirish paketini yaratish (sinov serverida)

```bash
cd /opt/mesh-central && sudo scripts/export-airgap.sh --with-debs
```

Natija `dist/` papkasida:

```
mesh-transfer-YYYYMMDD-HHMM.tar          <- hamma narsa: Docker image'lar, sozlamalar, baza,
mesh-transfer-YYYYMMDD-HHMM.tar.sha256      sertifikatlar, Docker o'rnatish paketlari
```

Oxirida chiqadigan **ServerID** ning birinchi belgilarini yozib qo'ying.

Ikkala faylni fleshkaga ko'chiring:

```bash
sudo cp /opt/mesh-central/dist/mesh-transfer-*.tar* /media/$USER/<fleshka>/
```

> Paket ichida barcha parollar va server kalitlari bor — fleshkani nazoratda saqlang.

Sinov serverini o'chirmang — u kelajakdagi yangilanishlar uchun kerak bo'ladi (8-bo'lim).

---

## 4. Yopiq tarmoqdagi serverga o'rnatish

Ishchi serverga (sinov serveri bilan bir xil OS) fleshkadagi fayllarni ko'chiring, masalan `/root/` ga:

```bash
sudo cp /media/*/*/mesh-transfer-*.tar* /root/
```

Butunligini tekshiring (`OK` chiqishi kerak):

```bash
cd /root && sha256sum -c mesh-transfer-*.tar.sha256
```

Oching:

```bash
cd /root && tar -xf mesh-transfer-*.tar && cd mesh-transfer-*/
```

O'rnating (server IP'si avtomatik aniqlanadi):

```bash
sudo ./import-airgap.sh --purge-devices
```

Bu buyruq: Docker'ni paketdan o'rnatadi (yo'q bo'lsa) → hammasini `/opt/mesh-central` ga
ochadi → image'larni yuklaydi → serverni **yopiq tarmoq IP'siga** moslaydi (yangi TLS
sertifikati, config, ichki Docker tarmog'i to'qnashuvini tekshirish) → sinov qurilmalari
yozuvlarini o'chiradi → **yangi manzil bilan yangi installer** yig'adi → selftest.

Oxirida `SELFTEST: N/N OK` chiqishi kerak.

**Variantlar** (kerak bo'lsa):

| Holat | Buyruq |
|---|---|
| Server IP'sini aniq berish | `sudo ./import-airgap.sh --host 192.168.50.10 --purge-devices` |
| Ichki DNS nomi bilan (tavsiya, agar DNS bo'lsa) | `sudo ./import-airgap.sh --host rmm.corp.local --purge-devices` |
| Faqat ma'lum filial tarmoqlariga ruxsat | `… --agent-ip 192.168.0.0/16,10.20.0.0/16` |
| Faqat IT bo'limi tarmog'idan web-panelga kirish | `… --user-ip 192.168.10.0/24` |
| Tarmog'ingizda `172.31.250.x` ishlatilsa (skript o'zi aytadi) | `… --mesh-net 10.250.250` |

Firewall:

```bash
sudo ufw allow 443/tcp && sudo ufw allow 80/tcp
```

ServerID sinov serveridagi bilan bir xil ekanini tekshiring (3-bosqichda yozib olgan qiymat):

```bash
sudo jq -r .serverId /opt/mesh-central/agent/out/EnterpriseAgent_Setup.build-info.json
```

---

## 5. Yopiq tarmoqda tekshiruv

Yopiq tarmoqdagi administrator kompyuterida brauzerda `https://<ishchi server IP>/` —
login va parol sinov serveridagi bilan **bir xil**. Istalgan vaqtda to'liq tekshiruv:

```bash
cd /opt/mesh-central && sudo scripts/selftest.sh
```

---

## 6. Filial kompyuterlariga o'rnatish

Installer:
- serverda: `/opt/mesh-central/agent/out/EnterpriseAgent_Setup.exe`
- tarmoq orqali: `https://<ishchi server IP>/dl/EnterpriseAgent_Setup.exe`

Usullar:

| Usul | Qachon | Qanday |
|---|---|---|
| Qo'lda | bir nechta kompyuter | admin buyruq satrida `EnterpriseAgent_Setup.exe` |
| Group Policy | domendagi kompyuterlar | GPO → Computer Configuration → Policies → Windows Settings → Scripts → **Startup** → `\\server\share\EnterpriseAgent_Setup.exe`; kompyuterlar qayta yuklanganda o'rnatiladi |
| PsExec | domen yo'q, admin paroli ma'lum | `psexec \\PC-NOMI -s -c -f EnterpriseAgent_Setup.exe` |
| Intune / SCCM | MDM bo'lsa | install: `EnterpriseAgent_Setup.exe`, uninstall: `EnterpriseAgent_Setup.exe /UNINSTALL`, System nomidan |

Batafsil (GPO, PsExec ro'yxat bilan, Intune detection rule): [`docs/ORNATISH.md` → 4-qadam](docs/ORNATISH.md#4-qadam-filial-kompyuterlariga-ornatish).

Installer har bir kompyuterda: agentni SYSTEM xizmati sifatida o'rnatadi, uyqu va
hibernate'ni o'chiradi, firewall qoidalarini qo'shadi, xizmat to'xtasa 5 soniyada qayta
ko'taradi, qo'lda to'xtatilsa 1 daqiqada qaytaradi. Windows sertifikat omborlariga hech narsa
yozmaydi. Qayta ishga tushirilsa (masalan GPO har yuklanishda) — hech narsa qilmaydi.

---

## 7. Kundalik ish

| Vazifa | Buyruq (ishchi serverda) |
|---|---|
| Holat | `cd /opt/mesh-central && sudo docker compose ps` |
| To'liq tekshiruv | `sudo scripts/selftest.sh` |
| Loglar | `sudo docker compose logs -f meshcentral` |
| Qayta ishga tushirish | `sudo docker compose restart` |
| Server IP'si o'zgardi | `sudo scripts/reconfigure-network.sh --host <yangi IP>` keyin agentlarga `EnterpriseAgent_Setup.exe /FORCE` |
| Installer'ni qayta yig'ish | `sudo agent/build-agent.sh` |
| Qo'shimcha guruh + alohida installer | web-panelda guruh yarating, keyin `sudo agent/build-agent.sh --group "Guruh nomi"` |

**Zaxira.** Server har kuni avtomatik zaxira oladi (`/opt/mesh-central/data/meshcentral-backups/`).
Bundan tashqari, haftada bir marta serverdan tashqariga nusxalang:

```bash
sudo tar -czf /root/mesh-backup-$(date +%F).tar.gz -C /opt/mesh-central .env data/meshcentral-data data/tls data/meshcentral-backups
```

`data/meshcentral-data` ichidagi `*.key` / `*.crt` fayllari yo'qolsa — barcha agentlarni qayta
o'rnatishga to'g'ri keladi.

**Muhim:** web-panelda `admin` akkauntiga 2FA yoqmang va parolini o'zgartirsangiz
`/opt/mesh-central/.env` dagi `ADMIN_PASSWORD` ni ham yangilang — bu akkaunt installer yig'ish
uchun ishlatiladi. Xodimlar uchun alohida akkauntlar yarating ("My Users" → "Add User").

---

## 8. Kelajakda yangilash

1. **Sinov serverida** (internetli):

```bash
cd /opt/mesh-central && sudo ./update.sh
```

2. Sinab ko'ring, keyin yangilanish paketini yarating:

```bash
cd /opt/mesh-central && sudo scripts/make-offline-bundle.sh
```

3. `dist/corp-mesh-offline-*.tar.gz` ni fleshka orqali **ishchi serverga** ko'chiring va:

```bash
cd /opt/mesh-central && sudo ./update.sh --bundle /root/corp-mesh-offline-*.tar.gz
```

Ishchi serverning bazasi, foydalanuvchilari va tarmoq sozlamalari saqlanadi; agentlar
server orqali o'zi yangilanadi. Yangilashda `export-airgap.sh` ni **ishlatmang** — u sinov
serverining bazasini olib kelib, ishchi ma'lumotlarni almashtirib yuboradi.

---

## 9. Ixtiyoriy: o'z brendingiz

Standart nomlar: web-panel "Korxona RMM", Windows xizmati "EnterpriseAgent". O'zgartirish
**1-bosqichdan oldin** eng qulay (sinov serverida):

1. `/opt/mesh-central/branding/brand.env` — nomlar, ranglar, matnlar.
2. `/opt/mesh-central/branding/assets/` va `branding/web/public/` — logotiplar (nomlar va
   o'lchamlar: [`docs/ORNATISH.md`](docs/ORNATISH.md), I qism 3-bo'lim).
3. Qo'llash:

```bash
cd /opt/mesh-central && sudo ./update.sh --config
```

Nomlar web-sahifalar ichiga build vaqtida yoziladi, shuning uchun `BRAND_NAME` o'zgarsa
`sudo ./update.sh` (to'liq qayta yig'ish) kerak. Keyin 3-bosqichdan davom eting.
