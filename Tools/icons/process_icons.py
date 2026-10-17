"""Transforme les icônes générées (Nano Banana) en assets Xcode.

Usage : python Tools/icons/process_icons.py <dossier_raw> App/Resources/Assets.xcassets
- nav.*  : glyphe noir sur blanc → gabarit (alpha = noirceur), recadré, carré, 144 px
- dock.* : tuile arrondie sur fond blanc → coins rendus transparents, 180 px
"""
import json
import pathlib
import sys

from PIL import Image, ImageChops, ImageDraw

raw, assets = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
out_dir = assets / "Icons"


def save(name, img, template):
    d = out_dir / f"{name}.imageset"
    d.mkdir(parents=True, exist_ok=True)
    for old in d.glob("*.png"):
        old.unlink()
    img.save(d / f"{name}.png")
    meta = {"images": [{"filename": f"{name}.png", "idiom": "universal", "scale": "3x"}],
            "info": {"author": "xcode", "version": 1}}
    if template:
        meta["properties"] = {"template-rendering-intent": "template", "preserves-vector-representation": False}
    (d / "Contents.json").write_text(json.dumps(meta, indent=2))


def glyph(path):
    gray = Image.open(path).convert("L")
    alpha = ImageChops.invert(gray).point(lambda v: 0 if v < 40 else min(255, int((v - 40) * 1.25)))
    box = alpha.getbbox() or (0, 0, gray.width, gray.height)
    alpha = alpha.crop(box)
    side = int(max(alpha.size) * 1.12)
    canvas = Image.new("L", (side, side), 0)
    canvas.paste(alpha, ((side - alpha.width) // 2, (side - alpha.height) // 2))
    canvas = canvas.resize((144, 144), Image.LANCZOS)
    out = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    out.putalpha(canvas)
    return out


def tile(path):
    img = Image.open(path).convert("RGBA")
    # fond blanc relié aux coins → transparent
    mask = Image.new("L", img.size, 0)
    rgb = img.convert("RGB")
    for corner in [(0, 0), (img.width - 1, 0), (0, img.height - 1), (img.width - 1, img.height - 1)]:
        ImageDraw.floodfill(rgb, corner, (255, 0, 255), thresh=40)
    px, mp = rgb.load(), mask.load()
    for y in range(img.height):
        for x in range(img.width):
            mp[x, y] = 0 if px[x, y] == (255, 0, 255) else 255
    img.putalpha(mask)
    box = mask.getbbox() or (0, 0, img.width, img.height)
    img = img.crop(box)
    side = max(img.size)
    sq = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    sq.paste(img, ((side - img.width) // 2, (side - img.height) // 2))
    return sq.resize((180, 180), Image.LANCZOS)


for f in sorted(raw.glob("*.png")):
    name = f.stem
    if name.startswith("nav."):
        save(name, glyph(f), True)
    elif name.startswith("dock."):
        save(name, tile(f), False)
    print("✓", name)
