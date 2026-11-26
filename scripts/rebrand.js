#!/usr/bin/env node
/*
 * rebrand.js — MeshCentral manba kodida "MeshCentral" ko'rinadigan matnlarini
 * BRAND_NAME ga almashtiradi (Docker build vaqtida ishlaydi).
 *
 * Ishlatish:  BRAND_NAME="Korxona RMM" node scripts/rebrand.js <meshcentral-src-dir>
 *
 * Qoidalar:
 *  - Faqat foydalanuvchiga ko'rinadigan fayllar: views/*.handlebars, emails/*,
 *    translate/translate.json (kalit + tarjima — tarjimalar buzilmasligi uchun
 *    inglizcha manba va translate.json bir xil almashtiriladi).
 *  - JS identifikatorlar (MeshCentralTheme, MeshCentralServerUpdate ...) TEGILMAYDI:
 *    regex so'z chegarasini talab qiladi.
 *  - URL ichidagi nomlar (".../Ylianst/MeshCentral/...") TEGILMAYDI: oldidan "/" yoki "."
 *    kelsa o'tkazib yuboriladi.
 *  - Apache-2.0 talabi: LICENSE fayli va kod ichidagi copyright sarlavhalari saqlanadi.
 */
'use strict';
const fs = require('fs');
const path = require('path');

const root = process.argv[2];
const brand = process.env.BRAND_NAME;
if (!root || !fs.existsSync(path.join(root, 'meshcentral.js'))) {
    console.error('Usage: BRAND_NAME="..." node rebrand.js <meshcentral-src-dir>'); process.exit(2);
}
if (!brand || /[<>"'`\\]/.test(brand)) {
    console.error('BRAND_NAME is empty or contains forbidden characters (<>"\'`\\)'); process.exit(2);
}

// "MeshCentral" — oldida harf/raqam/_/./- yoki "/" bo'lmasa va keyinida harf/raqam/_ bo'lmasa.
const re = /(?<![\w./-])MeshCentral(?![\w])/g;

function listFiles(dir, filter) {
    if (!fs.existsSync(dir)) return [];
    return fs.readdirSync(dir, { withFileTypes: true })
        .filter(d => d.isFile() && filter(d.name))
        .map(d => path.join(dir, d.name));
}

const targets = [
    ...listFiles(path.join(root, 'views'), n => n.endsWith('.handlebars')),
    ...listFiles(path.join(root, 'emails'), n => /\.(html|txt)$/.test(n)),
    path.join(root, 'translate', 'translate.json'),
    path.join(root, 'public', 'manifest.json'),
].filter(f => fs.existsSync(f));

let total = 0;
for (const file of targets) {
    const src = fs.readFileSync(file, 'utf8');
    let n = 0;
    let out = src.replace(re, () => { n++; return brand; });
    if (file.endsWith('.json')) {
        // JSON ichida brand nomi xavfsiz bo'lishi kerak (qo'shtirnoq tekshirilgan) — validatsiya:
        try { JSON.parse(out); } catch (e) { console.error('JSON broken after rebrand: ' + file); process.exit(1); }
    }
    if (n > 0) { fs.writeFileSync(file, out); total += n; console.log(`  ${String(n).padStart(4)}  ${path.relative(root, file)}`); }
}
console.log(`rebrand: ${total} replacements -> "${brand}"`);
