"""Découpe les planches d'icônes exportées du Figma en assets Xcode.

Usage : python Tools/figma/slice_icons.py <navicons.png> <appicons.png> <Assets.xcassets>
Positions = métadonnées Figma (nœuds 347:19037 « Navtree icons » et 347:19334 « App icons »).
"""
import json
import pathlib
import sys

from PIL import Image

nav_png, app_png, assets = sys.argv[1], sys.argv[2], pathlib.Path(sys.argv[3])

NAV = {  # ligne « Color=black » (y=315) + cadenas ouvert
    "software": 48, "service": 120, "security": 192, "eye": 264, "trip": 336,
    "controls": 408, "display": 480, "lights": 552, "lock": 624, "steering": 696,
    "power": 768, "model3": 840, "navigation": 912, "search": 984, "point": 1056,
    "shop": 1128, "chevronUp": 1200, "chevronDown": 1272,
}
APP_TEMPLATE = {  # glyphes blancs sur fond #404040
    "volume": (48, 48), "car": (152, 48), "frontDefrost": (256, 48), "rearDefrost": (360, 48),
    "seatWarmer": (464, 48), "wheelWarmer": (568, 48), "wiper": (672, 48), "seat": (984, 48),
    "music": (152, 152),
}
APP_COLOR = {
    "phone": (776, 48), "calendar": (880, 48), "dashcam": (1088, 48), "camera": (48, 152),
    "bluetooth": (256, 152), "spotify": (360, 152), "messages": (464, 152), "zoom": (568, 152),
    "video": (672, 152), "toybox": (880, 152), "games": (984, 152), "karaoke": (1088, 152),
}
BG = (0x40, 0x40, 0x40)


def write_imageset(name, img, template):
    d = assets / "Icons" / f"{name}.imageset"
    d.mkdir(parents=True, exist_ok=True)
    img.save(d / f"{name}.png")
    meta = {
        "images": [{"filename": f"{name}.png", "idiom": "universal", "scale": "2x"}],
        "info": {"author": "xcode", "version": 1},
    }
    if template:
        meta["properties"] = {"template-rendering-intent": "template"}
    (d / "Contents.json").write_text(json.dumps(meta, indent=2))


def mask_from_dark(tile):
    out = Image.new("RGBA", tile.size)
    for i, (r, g, b, a) in enumerate(tile.getdata()):
        dark = 255 - (r + g + b) // 3
        out.putpixel((i % tile.width, i // tile.width), (0, 0, 0, a * dark // 255))
    return out


def mask_from_light(tile):
    out = Image.new("RGBA", tile.size)
    for i, (r, g, b, a) in enumerate(tile.getdata()):
        lum = (r + g + b) // 3
        alpha = max(0, min(255, (lum - BG[0]) * 255 // (255 - BG[0])))
        out.putpixel((i % tile.width, i // tile.width), (0, 0, 0, alpha))
    return out


def remove_bg(tile):
    out = tile.copy()
    px = out.load()
    for y in range(out.height):
        for x in range(out.width):
            r, g, b, a = px[x, y]
            if abs(r - BG[0]) + abs(g - BG[1]) + abs(b - BG[2]) < 18:
                px[x, y] = (r, g, b, 0)
    return out


nav = Image.open(nav_png).convert("RGBA")
for name, x in NAV.items():
    write_imageset(f"nav.{name}", mask_from_dark(nav.crop((x, 315, x + 48, 363))), True)
write_imageset("nav.unlocked", mask_from_dark(nav.crop((1344, 319, 1392, 367))), True)

app = Image.open(app_png).convert("RGBA")
for name, (x, y) in APP_TEMPLATE.items():
    write_imageset(f"app.{name}", mask_from_light(app.crop((x, y, x + 48, y + 48))), True)
for name, (x, y) in APP_COLOR.items():
    write_imageset(f"app.{name}", remove_bg(app.crop((x, y, x + 48, y + 48))), False)

(assets / "Icons" / "Contents.json").write_text(
    json.dumps({"info": {"author": "xcode", "version": 1}, "properties": {"provides-namespace": False}}, indent=2)
)
print("icônes écrites dans", assets / "Icons")
