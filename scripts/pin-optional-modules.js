#!/usr/bin/env node
/*
 * pin-optional-modules.js — MeshCentral ishga tushganda config'ga qarab qo'shimcha
 * npm modullarni (mongodb, ssh2, image-size ...) INTERNETDAN o'rnatishga harakat
 * qiladi (meshcentral.js -> mainStart() -> InstallModules). Air-gapped serverda bu
 * ishlamaydi, shuning uchun ular build vaqtida package.json ga qo'shiladi.
 *
 * Versiyalar AYNAN meshcentral.js dagi bilan bir xil bo'lishi shart (InstallModules
 * versiyani qat'iy tekshiradi) — shuning uchun ular qo'lda yozilmaydi, manba koddan
 * o'qiladi. Upstream versiyani o'zgartirsa, build avtomatik moslashadi.
 *
 * Ishlatish: node pin-optional-modules.js <meshcentral-dir> mod1 mod2 ...
 */
'use strict';
const fs = require('fs');
const path = require('path');

const dir = process.argv[2];
const wanted = process.argv.slice(3);
const src = fs.readFileSync(path.join(dir, 'meshcentral.js'), 'utf8');
const pkgFile = path.join(dir, 'package.json');
const pkg = JSON.parse(fs.readFileSync(pkgFile, 'utf8'));

const found = {};
for (const m of src.matchAll(/modules\.push\('((?:@[^@']+)|[^@']+)@([^']+)'\)/g)) {
    if (wanted.includes(m[1]) && !found[m[1]]) found[m[1]] = m[2];
}
const missing = wanted.filter(w => !found[w]);
if (missing.length) { console.error('Not found in meshcentral.js: ' + missing.join(', ')); process.exit(1); }

pkg.dependencies = Object.assign({}, pkg.dependencies, found);
fs.writeFileSync(pkgFile, JSON.stringify(pkg, null, 2) + '\n');
for (const [k, v] of Object.entries(found)) console.log(`pinned ${k}@${v}`);
