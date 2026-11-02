import re
from pathlib import Path
import sys

root = Path(__file__).resolve().parent.parent
native = (root / "Sources/Quill/Theme.swift").read_text()
editors = [(root / path).read_text() for path in ["Sources/Quill/Brand/Editor/page.css", "web/src/page.css"]]
tokens = {
    name: [tuple(bytes.fromhex(light)), tuple(bytes.fromhex(dark))]
    for name, light, dark in re.findall(r"static let (\w+) = color\(0x([0-9A-F]{6}), 0x([0-9A-F]{6})\)", native)
}

PAIRS = [
    ("ink", "paper", 90, "body text"),
    ("ink", "mark", 75, "body text on a pending change"),
    ("soft", "paper", 60, "secondary text"),
    ("soft", "sheet", 60, "secondary text on cards"),
    ("accent", "paper", 60, "accent text and links"),
    ("onAccent", "accent", 60, "primary button text"),
    ("red", "paper", 60, "error text"),
    ("ink", "sheet", 75, "card text"),
]


def luminance(rgb):
    r, g, b = (v / 255 for v in rgb)
    y = 0.2126729 * r ** 2.4 + 0.7151522 * g ** 2.4 + 0.0721750 * b ** 2.4
    return y + (0.022 - y) ** 1.414 if y < 0.022 else y


def apca(text, bg):
    yt, yb = luminance(text), luminance(bg)
    if yb > yt:
        s = (yb ** 0.56 - yt ** 0.57) * 1.14
        return 0 if s < 0.1 else (s - 0.027) * 100
    s = (yb ** 0.65 - yt ** 0.62) * 1.14
    return 0 if s > -0.1 else (s + 0.027) * 100


def hexa(rgb):
    return "0x%02X%02X%02X" % rgb


colors = tokens
failed = False
for name, values in colors.items():
    if name in ["onAccent", "red", "green"]:
        continue
    for editor in editors:
        if re.findall(rf"--{name}: #([0-9A-F]{{6}});", editor) != [hexa(value)[2:] for value in values]:
            print(f"FAIL: {name} differs between Theme.swift and page.css")
            failed = True
print("| token | light | dark |")
print("|---|---|---|")
for k, (lt, dk) in colors.items():
    print(f"| {k} | {hexa(lt)} | {hexa(dk)} |")
print()
print("| text on background | use | light Lc | dark Lc | floor |")
print("|---|---|---|---|---|")
for t, b, floor, use in PAIRS:
    lv = abs(apca(colors[t][0], colors[b][0]))
    dv = abs(apca(colors[t][1], colors[b][1]))
    ok = lv >= floor and dv >= floor
    failed |= not ok
    print(f"| {t} on {b} | {use} | {lv:.1f} | {dv:.1f} | {floor}{'' if ok else ' FAIL'} |")
sys.exit(1 if failed else 0)
