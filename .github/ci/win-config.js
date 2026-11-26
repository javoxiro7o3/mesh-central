// CI: server/config.json.template + branding/brand.env dan Windows'da to'g'ridan-to'g'ri
// (Docker/nginx'siz) ishlaydigan sinov config'ini yaratadi. Installer va postinstall.ps1 ni
// haqiqiy Windows'da sinash uchun. Natija stdout'ga.
'use strict';
const fs = require('fs');
const path = require('path');
const root = path.join(__dirname, '..', '..');

const env = {};
for (const line of fs.readFileSync(path.join(root, 'branding', 'brand.env'), 'utf8').split(/\r?\n/)) {
    const m = /^\s*([A-Z0-9_]+)="?(.*?)"?\s*$/.exec(line);
    if (m) env[m[1]] = m[2];
}
Object.assign(env, {
    SERVER_HOST: '127.0.0.1', SERVER_PORT: '443', MESH_NET: '127.0.0', MONGO_ROOT_USER: 'x', MONGO_ROOT_PASSWORD: 'x',
    DB_ENCRYPT_KEY: 'e2eDbEncryptKey0123456789', SESSION_KEY: 'e2eSessionKey0123456789', BACKUP_ZIP_PASSWORD: 'x',
    AGENT_ALLOWED_IP: '', USER_ALLOWED_IP: ''
});
let text = fs.readFileSync(path.join(root, 'server', 'config.json.template'), 'utf8');
text = text.replace(/\$\{([A-Z0-9_]+)\}/g, (_, k) => {
    if (!(k in env)) throw new Error('template variable not set: ' + k);
    return JSON.stringify(String(env[k])).slice(1, -1);
});
const cfg = JSON.parse(text);
const s = cfg.settings, d = cfg.domains[''];
s.cert = '127.0.0.1'; s.port = 443; s.redirPort = 0;
for (const k of ['aliasPort', 'tlsOffload', 'trustedProxy', 'mongoDb', 'mongoDbName', 'autoBackup', 'agentAllowedIP', 'userAllowedIP']) delete s[k];
delete d.certUrl;
d.minify = false; // upstream git'da *-min.handlebars yo'q (ular Docker build'da generatsiya qilinadi)
process.stdout.write(JSON.stringify(cfg, null, 2));
