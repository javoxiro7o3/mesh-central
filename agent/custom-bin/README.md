# agent/custom-bin — o'zingiz kompilyatsiya qilgan MeshAgent (ixtiyoriy)

Bo'sh bo'lsa: server rasmiy (Ylianst/MeshAgent) imzolangan agentlarini ishlatadi —
ular server tomonida brendlanadi (`agentCustomization`, `agentFileInfo`) va `.msh` ichiga tikiladi.

To'ldirish: Windows build mashinasida `agent/meshagent/build-meshagent.ps1` yoki
`.github/workflows/meshagent-windows.yml`. Natija:

```
MeshService64.exe  MeshService.exe  MeshServiceARM64.exe  custom-manifest.json
```

`custom-manifest.json` bor bo'lsa, `server/Dockerfile` (7-qadam) fayllarni image ichiga
qo'shadi va `server/entrypoint.sh` uni `settings.agentDownloads.manifest` ga ulaydi —
MeshCentral shu binarlarni SHA384 bo'yicha tekshirib, agentlarga tarqatadi va
ulangan agentlarni avtomatik yangilaydi.

Katta binarlarni Git'da saqlash uchun Git LFS tavsiya etiladi (`git lfs track "agent/custom-bin/*.exe"`).
