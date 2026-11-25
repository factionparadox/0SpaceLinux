#!/usr/bin/env python3
"""Draw the 0-Space logo: a hollow zero with six Andalite tail blades.

Each blade grows out of the zero's rim, sweeps forward and outward like a
tail strike, and tapers to an edge. Six of them turn round the zero, in fur
blue and dome glass by turns.

    python3 tools/render-logo.py

Writes art/logo.svg and art/logo-{64,128,256,512}.png.
"""
import math
from pathlib import Path

from PIL import Image, ImageDraw

ART = Path(__file__).resolve().parent.parent / "art"
FUR, GLASS, NIGHT = "#6aa2d8", "#9fd4ff", "#071226"

R_IN, R_OUT = 0.20, 0.31      # the zero (fractions of the half-size)
BLADES = 6
SWEEP = math.radians(78)      # how far round each blade sweeps
REACH = 0.97                  # blade tip radius
BASE_W = 0.17                 # blade width where it leaves the rim


def blade(k):
    """Polygon (unit coordinates, centre 0,0) for blade k."""
    a0 = 2 * math.pi * k / BLADES
    pts_out, pts_in = [], []
    n = 48
    for i in range(n + 1):
        t = i / n
        # centreline: from the rim outwards, turning as it goes (ease-out)
        r = R_OUT * 0.92 + (REACH - R_OUT * 0.92) * t
        a = a0 + SWEEP * (1 - (1 - t) ** 2)
        cx, cy = r * math.cos(a), r * math.sin(a)
        # direction of travel, for the normal
        t2 = min(1, t + 1e-3)
        r2 = R_OUT * 0.92 + (REACH - R_OUT * 0.92) * t2
        a2 = a0 + SWEEP * (1 - (1 - t2) ** 2)
        dx, dy = r2 * math.cos(a2) - cx, r2 * math.sin(a2) - cy
        ln = math.hypot(dx, dy) or 1
        nx, ny = -dy / ln, dx / ln
        # width: full at the rim, a slight swell, then a keen point
        w = BASE_W * (1 - t) ** 0.85 * (1 + 0.35 * math.sin(math.pi * t))
        # the leading edge stays fuller (the blade's back), the trailing edge cuts in
        pts_out.append((cx + nx * w * 0.62, cy + ny * w * 0.62))
        pts_in.append((cx - nx * w * 0.38, cy - ny * w * 0.38))
    return pts_out + pts_in[::-1]


def ring(n=180):
    outer = [(R_OUT * math.cos(2 * math.pi * i / n), R_OUT * math.sin(2 * math.pi * i / n)) for i in range(n)]
    inner = [(R_IN * math.cos(2 * math.pi * i / n), R_IN * math.sin(2 * math.pi * i / n)) for i in range(n)]
    return outer, inner


def svg():
    size = 512
    h = size / 2

    def path(pts):
        return "M" + " L".join(f"{h + x * h * 0.96:.1f},{h + y * h * 0.96:.1f}" for x, y in pts) + " Z"

    parts = []
    for k in range(BLADES):
        parts.append(f'<path d="{path(blade(k))}" fill="{FUR if k % 2 == 0 else GLASS}"/>')
    outer, inner = ring()
    parts.append(f'<path d="{path(outer)} {path(inner[::-1])}" fill="{GLASS}" fill-rule="evenodd"/>')
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {size} {size}" '
            f'width="{size}" height="{size}">\n  <title>0-Space Linux</title>\n  '
            + "\n  ".join(parts) + "\n</svg>\n")


def png(size):
    ss = 4
    big = size * ss
    h = big / 2
    img = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    def px(pts):
        return [(h + x * h * 0.96, h + y * h * 0.96) for x, y in pts]

    for k in range(BLADES):
        d.polygon(px(blade(k)), fill=FUR if k % 2 == 0 else GLASS)
    outer, inner = ring()
    d.polygon(px(outer), fill=GLASS)
    hole = Image.new("L", (big, big), 0)
    ImageDraw.Draw(hole).polygon(px(inner), fill=255)
    img.paste((0, 0, 0, 0), mask=hole)
    return img.resize((size, size), Image.LANCZOS)


def main():
    (ART / "logo.svg").write_text(svg())
    for s in (64, 128, 256, 512):
        png(s).save(ART / f"logo-{s}.png", optimize=True)
    print("art/logo.svg art/logo-{64,128,256,512}.png")


if __name__ == "__main__":
    main()
