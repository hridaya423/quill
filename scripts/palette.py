import math
import sys

TOKENS = {
    "paper":   [(0.978, 0.007, 85), (0.205, 0.006, 75)],
    "sheet":   [(0.955, 0.009, 85), (0.245, 0.007, 75)],
    "ink":     [(0.235, 0.012, 65), (0.925, 0.010, 85)],
    "soft":    [(0.500, 0.014, 70), (0.775, 0.011, 80)],
    "faint":   [(0.800, 0.012, 75), (0.390, 0.009, 75)],
    "rule":    [(0.900, 0.010, 80), (0.300, 0.007, 75)],
    "accent":  [(0.500, 0.150, 32), (0.785, 0.110, 40)],
    "mark":    [(0.935, 0.030, 45), (0.290, 0.040, 35)],
    "kept":    [(0.560, 0.070, 150), (0.740, 0.080, 150)],
}

PAIRS = [
    ("ink", "paper", 90, "body text"),
    ("ink", "mark", 75, "body text on a pending change"),
    ("soft", "paper", 60, "secondary text"),
    ("soft", "sheet", 60, "secondary text on cards"),
    ("accent", "paper", 60, "accent text and links"),
    ("ink", "sheet", 75, "card text"),
]


def oklch_to_srgb(l, c, h):
    a, b = c * math.cos(math.radians(h)), c * math.sin(math.radians(h))
    l_ = l + 0.3963377774 * a + 0.2158037573 * b
    m_ = l - 0.1055613458 * a - 0.0638541728 * b
    s_ = l - 0.0894841775 * a - 1.2914855480 * b
    lc, mc, sc = l_ ** 3, m_ ** 3, s_ ** 3
    lin = (
        4.0767416621 * lc - 3.3077115913 * mc + 0.2309699292 * sc,
        -1.2684380046 * lc + 2.6097574011 * mc - 0.3413193965 * sc,
        -0.0041960863 * lc - 0.7034186147 * mc + 1.7076147010 * sc,
    )

    def gamma(x):
        x = min(1, max(0, x))
        return 12.92 * x if x <= 0.0031308 else 1.055 * x ** (1 / 2.4) - 0.055

    return tuple(round(gamma(x) * 255) for x in lin)


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


colors = {k: [oklch_to_srgb(*v[0]), oklch_to_srgb(*v[1])] for k, v in TOKENS.items()}
print("| token | light | dark |")
print("|---|---|---|")
for k, (lt, dk) in colors.items():
    print(f"| {k} | {hexa(lt)} | {hexa(dk)} |")
print()
print("| text on background | use | light Lc | dark Lc | floor |")
print("|---|---|---|---|---|")
failed = False
for t, b, floor, use in PAIRS:
    lv = abs(apca(colors[t][0], colors[b][0]))
    dv = abs(apca(colors[t][1], colors[b][1]))
    ok = lv >= floor and dv >= floor
    failed |= not ok
    print(f"| {t} on {b} | {use} | {lv:.1f} | {dv:.1f} | {floor}{'' if ok else ' FAIL'} |")
sys.exit(1 if failed else 0)
