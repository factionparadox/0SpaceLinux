#!/usr/bin/env python3
"""Build art/0space-script.ttf: the invented Andalite script as a real font.

Written in one hand: every letter grows from one of eight forms (crescents,
the tail's S-curve, a cloven hoof, a teardrop, an arch, a bowl, a bladed
spine) and is told apart by its marks: stalk eyes, a core dot, a tick, a
trailing tail. Everything leans forward. Capitals are the same letter drawn
taller with a crown stroke. Only letters are covered: digits and
symbols fall back to the terminal's normal font, so numbers stay readable.

The letters are at their usual code points (for the shell, which writes
English in this font) and again at U+100000 + the letter, so a terminal can
map just that range to the script and show it beside ordinary English.

The cell matches Maple Mono (600 wide, 1000 units per em) so it sits on the
terminal grid exactly.

    python3 tools/make-script-font.py
"""
import math
from pathlib import Path

from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen
from shapely.geometry import LineString, Point
from shapely.geometry.polygon import orient
from shapely.ops import unary_union

ADVANCE = 600
LEFT, WIDTH = 75, 450      # drawing box inside the cell
STROKE = 68                # stroke width in font units
LOWER_H, UPPER_H = 540, 720


def arc(cx, cy, r, a0, a1, n=24):
    return [(cx + r * math.cos(a0 + (a1 - a0) * i / n),
             cy + r * math.sin(a0 + (a1 - a0) * i / n)) for i in range(n + 1)]


def quad(p0, p1, p2, n=20):
    return [((1 - t) ** 2 * p0[0] + 2 * (1 - t) * t * p1[0] + t ** 2 * p2[0],
             (1 - t) ** 2 * p0[1] + 2 * (1 - t) * t * p1[1] + t ** 2 * p2[1])
            for t in (i / n for i in range(n + 1))]


def cubic(p0, p1, p2, p3, n=28):
    return [tuple((1 - t) ** 3 * a + 3 * (1 - t) ** 2 * t * b + 3 * (1 - t) * t ** 2 * c + t ** 3 * d
                  for a, b, c, d in zip(p0, p1, p2, p3))
            for t in (i / n for i in range(n + 1))]


# One hand: eight forms, each told apart by the marks added to it. Unit box:
# x 0..1, y 0 (baseline) .. 1 (top of the body); eyes reach above, tails below.
FORMS = {
    "crescL": lambda: [cubic((0.9, 1), (-0.25, 1.05), (-0.25, -0.05), (0.9, 0))],  # bulges left
    "crescR": lambda: [cubic((0.1, 1), (1.25, 1.05), (1.25, -0.05), (0.1, 0))],    # bulges right
    "tail":   lambda: [cubic((0.1, 0.05), (1.15, 0.2), (-0.1, 0.8), (0.75, 1.0)),
                       quad((0.75, 1.0), (0.95, 1.05), (1.0, 0.82))],        # the tail, blade flicked
    "hoof":   lambda: [quad((0.08, 1), (0.15, 0.25), (0.5, 0)),
                       quad((0.92, 1), (0.85, 0.25), (0.5, 0))],             # cloven
    "drop":   lambda: [cubic((0.5, 1.05), (-0.35, 0.05), (1.35, 0.05), (0.5, 1.05))],  # teardrop
    "arch":   lambda: [cubic((0.05, 0), (0.0, 1.3), (1.0, 1.3), (0.95, 0.15))],
    "bowl":   lambda: [cubic((0.05, 1.0), (0.0, -0.3), (1.0, -0.3), (0.95, 0.85)),
                       quad((0.95, 0.85), (0.95, 1.05), (1.1, 1.1))],
    "spine":  lambda: [[(0.45, 0), (0.45, 1)], quad((0.45, 1), (0.5, 1.18), (0.82, 1.12))],
}
MARKS = {
    "tick":  lambda: [[(0.62, 0.32), (1.08, 0.6)]],     # a slash across the right side
    "under": lambda: [quad((0.5, 0.0), (0.45, -0.32), (0.05, -0.3))],
}
DOTS = {                       # (x, y, radius) as fractions of the box
    "eye":  [(0.5, 1.34, 0.085)],
    "eyes": [(0.26, 1.34, 0.08), (0.74, 1.34, 0.08)],   # stalk eyes, the pair
    "core": [(0.5, 0.48, 0.085)],
}
SLANT = 0.16
PUA = 0x100000                 # where the second copy of the letters lives                   # forward lean, like a fast hand

LETTERS = {
    "a": ("crescL", "core"),  "c": ("crescL", "eye"),   "q": ("crescL", "under"),
    "d": ("crescR", "core"),  "b": ("crescR", "eyes"),  "p": ("crescR", "under"),
    "s": ("tail",),           "z": ("tail", "tick"),    "x": ("tail", "eyes"),
    "v": ("hoof", "tick"),    "w": ("hoof", "core"),    "y": ("hoof", "eyes"),
    "k": ("hoof", "eye"),
    "o": ("drop",),           "e": ("drop", "tick"),    "g": ("drop", "under"),
    "n": ("arch", "tick"),    "m": ("arch", "core"),    "h": ("arch", "eyes"),
    "r": ("arch", "eye"),
    "u": ("bowl", "core"),    "j": ("bowl", "under"),
    "l": ("spine",),          "i": ("spine", "eye"),    "t": ("spine", "tick"),
    "f": ("spine", "eyes"),
}
assert len({frozenset(v) for v in LETTERS.values()}) == 26, "two letters share a glyph"


def outline(parts, height, capital):
    def place(p):
        x, y = p[0] * WIDTH, p[1] * height
        return (LEFT + x + SLANT * (y - height / 2), y)

    lines, dots = [], []
    for part in parts:
        lines += (FORMS.get(part) or MARKS.get(part) or (lambda: []))()
        dots += DOTS.get(part, [])
    if capital:  # capitals: taller, with a crown stroke over the left shoulder
        lines.append([(-0.05, 1.2), (0.25, 1.28)])

    shapes = [LineString([place(p) for p in line]).buffer(
        STROKE / 2, cap_style="round", join_style="round", quad_segs=6) for line in lines]
    shapes += [Point(place((x, y))).buffer(r * WIDTH, quad_segs=8) for x, y, r in dots]
    return unary_union(shapes)


def draw(geom):
    pen = TTGlyphPen(None)
    polys = getattr(geom, "geoms", [geom])
    for poly in polys:
        poly = orient(poly, sign=-1.0)  # TrueType: outer rings clockwise
        for ring in [poly.exterior, *poly.interiors]:
            pts, last = [], None
            for x, y in ring.coords[:-1]:
                pt = (round(x), round(y))
                if pt != last:
                    pts.append(pt)
                last = pt
            if len(pts) < 3:
                continue
            pen.moveTo(pts[0])
            for pt in pts[1:]:
                pen.lineTo(pt)
            pen.closePath()
    return pen.glyph()


def main():
    order = [".notdef", "space"]
    glyphs = {".notdef": TTGlyphPen(None).glyph(), "space": TTGlyphPen(None).glyph()}
    cmap = {32: "space"}
    for ch, parts in LETTERS.items():
        glyphs[ch] = draw(outline(parts, LOWER_H, False))
        glyphs[ch.upper()] = draw(outline(parts, UPPER_H, True))
        cmap[ord(ch)] = ch
        cmap[ord(ch.upper())] = ch.upper()
        # A second copy in Private Use Area-B, so a terminal can show the
        # script beside English: Mirrorwave maps only this range to the font.
        cmap[PUA + ord(ch)] = ch
        cmap[PUA + ord(ch.upper())] = ch.upper()
        order += [ch, ch.upper()]

    fb = FontBuilder(1000, isTTF=True)
    fb.setupGlyphOrder(order)
    fb.setupCharacterMap(cmap)
    fb.setupGlyf(glyphs)
    fb.setupHorizontalMetrics({g: (ADVANCE, 0) for g in order})
    fb.setupHorizontalHeader(ascent=1020, descent=-300)
    fb.setupNameTable({"familyName": "0-Space Script", "styleName": "Regular",
                       "psName": "0SpaceScript-Regular",
                       "copyright": "0-Space Linux. Invented script, free to use.",
                       "version": "Version 1.0"})
    fb.setupOS2(sTypoAscender=1020, sTypoDescender=-300, sTypoLineGap=0,
                usWinAscent=1020, usWinDescent=300, sxHeight=LOWER_H,
                sCapHeight=UPPER_H, achVendID="0SPC",
                panose=dict({k: 0 for k in (
                    "bFamilyType", "bSerifStyle", "bWeight", "bProportion", "bContrast",
                    "bStrokeVariation", "bArmStyle", "bLetterForm", "bMidline", "bXHeight")},
                    bFamilyType=2, bProportion=9))  # 9 = monospaced
    fb.setupPost(isFixedPitch=1)
    out = Path(__file__).resolve().parent.parent / "art" / "0space-script.ttf"
    fb.save(str(out))
    print(out)


if __name__ == "__main__":
    main()
