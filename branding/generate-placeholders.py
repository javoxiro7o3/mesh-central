#!/usr/bin/env python3
"""
generate-placeholders.py — brend rasmlarining vaqtinchalik (placeholder) versiyalarini yaratadi.
Haqiqiy logolaringizni SHU NOMLAR va O'LCHAMLAR bilan almashtiring, keyin ./update.sh --config.

  branding/assets/title.png          450x66   web-panel yuqori chap logotip   (domains.titlePicture)
  branding/assets/login.png          600x150  login sahifasi logotipi          (domains.loginPicture)
  branding/assets/welcome.jpg        900x400  login sahifasi rasmi             (domains.welcomePicture)
  branding/assets/agent.ico          16..256  agent EXE va installer ikonkasi  (agentFileInfo.icon, NSIS)
  branding/web/public/favicon.ico, favicon-16x16.png, favicon-32x32.png,
                      android-chrome-192x192.png, android-chrome-512x512.png   (meshcentral-web overlay)
  branding/web/public/images/logoback.png   (mobil/PWA fon logotipi)

Talab: pip install pillow
"""
import os
import re
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.abspath(__file__))


def brand_env():
    env = {}
    with open(os.path.join(ROOT, 'brand.env'), encoding='utf-8') as f:
        for line in f:
            m = re.match(r'^\s*([A-Z0-9_]+)="?(.*?)"?\s*$', line)
            if m:
                env[m.group(1)] = m.group(2)
    return env


env = brand_env()
NAME = env.get('BRAND_NAME', 'Enterprise')
BG = env.get('BRAND_BG', '#0B3D91')
FG = env.get('BRAND_FG', '#FFFFFF')
INITIALS = ''.join(w[0] for w in NAME.split()[:2]).upper() or 'E'


def font(size):
    for p in ('/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf',
              '/usr/share/fonts/dejavu/DejaVuSans-Bold.ttf',
              'C:/Windows/Fonts/arialbd.ttf'):
        if os.path.exists(p):
            return ImageFont.truetype(p, size)
    return ImageFont.load_default()


def banner(w, h, text, path, transparent=False):
    img = Image.new('RGBA', (w, h), (0, 0, 0, 0) if transparent else BG)
    d = ImageDraw.Draw(img)
    f = font(int(h * 0.45))
    box = d.textbbox((0, 0), text, font=f)
    d.text(((w - (box[2] - box[0])) / 2, (h - (box[3] - box[1])) / 2 - box[1]), text,
           font=f, fill=FG if not transparent else BG)
    if path.endswith('.jpg'):
        img = img.convert('RGB')
    img.save(path)


def square(size):
    img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    r = max(2, size // 6)
    d.rounded_rectangle((0, 0, size - 1, size - 1), radius=r, fill=BG)
    f = font(int(size * 0.5))
    box = d.textbbox((0, 0), INITIALS, font=f)
    d.text(((size - (box[2] - box[0])) / 2, (size - (box[3] - box[1])) / 2 - box[1]), INITIALS, font=f, fill=FG)
    return img


assets = os.path.join(ROOT, 'assets')
pub = os.path.join(ROOT, 'web', 'public')
os.makedirs(assets, exist_ok=True)
os.makedirs(os.path.join(pub, 'images'), exist_ok=True)

banner(450, 66, NAME, os.path.join(assets, 'title.png'))
banner(600, 150, NAME, os.path.join(assets, 'login.png'), transparent=True)
banner(900, 400, NAME, os.path.join(assets, 'welcome.jpg'))

ico_sizes = [(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)]
square(256).save(os.path.join(assets, 'agent.ico'), sizes=ico_sizes, bitmap_format='bmp')  # BMP: eski Windows/NSIS/MeshCentral PE-resurs muharriri bilan mos
square(256).save(os.path.join(pub, 'favicon.ico'), sizes=[(16, 16), (32, 32), (48, 48)], bitmap_format='bmp')
for s in (16, 32):
    square(s).save(os.path.join(pub, f'favicon-{s}x{s}.png'))
for s in (192, 512):
    square(s).save(os.path.join(pub, f'android-chrome-{s}x{s}.png'))
square(512).save(os.path.join(pub, 'images', 'logoback.png'))
print('placeholders generated for', NAME)
