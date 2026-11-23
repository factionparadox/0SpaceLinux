#!/usr/bin/env python3
"""Render the shell's glass: the frosted Dome and the pills' glow and shadow.

    python3 tools/render-glass.py

art/dome-glass.png   the Dome, blurred. The shell shows the patch of it that
                     lies behind each pill, so the pills look like frosted
                     glass over the real Dome.
art/glow.png         a soft fur-blue halo, as a 9-slice (border 40)
art/shadow.png       a soft drop shadow, as a 9-slice (border 40)

A Dome of your own (~/.local/share/0space/art/dome.png) is frosted the same
way by the session when you log in.
"""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ART = Path(__file__).resolve().parent.parent / "art"
SLICE = 40          # 9-slice border; the shell's BorderImage uses the same
SIZE = 2 * SLICE + 40
RADIUS = 18         # pill corner radius


def frosted_dome():
    dome = Image.open(ART / "dome.png").convert("RGB")
    small = dome.resize((dome.width // 2, dome.height // 2), Image.LANCZOS)
    small.filter(ImageFilter.GaussianBlur(18)).save(ART / "dome-glass.png", optimize=True)


def halo(colour, blur, offset_y, alpha):
    img = Image.new("RGBA", (SIZE, SIZE), colour + (0,))
    mask = Image.new("L", (SIZE, SIZE), 0)
    inset = SLICE - 4
    ImageDraw.Draw(mask).rounded_rectangle(
        (inset, inset + offset_y, SIZE - inset, SIZE - inset + offset_y),
        radius=RADIUS + 4, fill=alpha)
    img.putalpha(mask.filter(ImageFilter.GaussianBlur(blur)))
    return img


def main():
    frosted_dome()
    halo((106, 162, 216), 10, 0, 150).save(ART / "glow.png")      # fur blue
    halo((2, 6, 16), 12, 6, 210).save(ART / "shadow.png")
    print("art/dome-glass.png art/glow.png art/shadow.png")


if __name__ == "__main__":
    main()
