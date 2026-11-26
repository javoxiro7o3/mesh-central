# patches/meshcentral

Config orqali qilib bo'lmaydigan **manba kod o'zgarishlari** shu yerda `.patch` ko'rinishida saqlanadi.
`server/Dockerfile` ularni nom tartibida (`0001-…`, `0002-…`) upstream kodiga `git apply` qiladi.
Upstream yangilanganda patch qo'llanmasa — build to'xtaydi (jim buzilish bo'lmaydi).

Patch yaratish:

```bash
. ./upstream.lock
git clone https://github.com/Ylianst/MeshCentral.git /tmp/mc && cd /tmp/mc && git checkout "$MESHCENTRAL_REF"
# ... o'zgartiring ...
git diff > ~/mesh-central/patches/meshcentral/0001-mening-ozgarishim.patch
```

Hozirgi holatda patch **kerak emas**: brending (`scripts/rebrand.js` + `config.json` + `meshcentral-web`)
va air-gap (`selfUpdate:false`, `agentDownloads.enabled:false`, `agentTimeStampServer:false`,
`NPM_CONFIG_OFFLINE=true`, oldindan o'rnatilgan modullar va agent binarlari) config/build darajasida hal qilingan.
Patch'larni minimal tutish upstream yangilanishlarini arzon qiladi.
