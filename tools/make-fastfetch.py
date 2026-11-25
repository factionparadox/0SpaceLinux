#!/usr/bin/env python3
"""Make 0-Space's fastfetch: the logo as text, and two configs.

  theme/fastfetch/logo.txt          the logo in characters, for text consoles
  theme/fastfetch/mirrorwave.jsonc  in Mirrorwave: the logo as a picture, and
                                    every label as <script>/English
  theme/fastfetch/console.jsonc     on a text console: the text logo, English

Colours are the console palette's names, which 0-Space sets to the Andalite
palette: blue is fur blue, cyan the dome's glass, yellow fur tan.

  python3 tools/make-fastfetch.py
"""
import json
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "theme" / "fastfetch"
OFFSET = 0x100000            # the script font's copy of its letters (see mirrorwave/tab_bar.py)


def andalite(text):
    return "".join(chr(OFFSET + ord(c)) if c.isascii() and c.isalpha() else c for c in text.lower())


# ---------------------------------------------------------------- the text logo
def text_logo(cols=38, rows=19):
    im = Image.open(ROOT / "art" / "logo-512.png").convert("RGBA").resize((cols, rows), Image.LANCZOS)
    ramp = " .:-=+*#"
    lines = []
    for y in range(rows):
        line, colour = "", None
        for x in range(cols):
            r, g, b, a = im.getpixel((x, y))
            if a < 40:
                line += " "
                continue
            c = "$1" if (r + g + b) / 3 > 190 else "$2"   # light glass, or fur blue
            if c != colour:
                line += c
                colour = c
            line += ramp[min(len(ramp) - 1, 1 + a * (len(ramp) - 1) // 256)]
        lines.append(line.rstrip())
    while lines and not lines[0].replace("$1", "").replace("$2", "").strip():
        lines.pop(0)
    while lines and not lines[-1].replace("$1", "").replace("$2", "").strip():
        lines.pop()
    return "\n".join(lines) + "\n"


# ---------------------------------------------------------------- the configs
# fastfetch module, its English label, and what the Andalite would call it.
FIELDS = [
    ("os", "Dome ship", {"format": "{name} {version-id}"}),
    ("host", "Hull", {"format": "{name}"}),
    ("kernel", "Core", {"format": "{release}"}),
    ("uptime", "Morph time", {"format": "{hours}h {minutes}m / 2h limit"}),
    ("packages", "Forms", {}),
    ("wm", "Carousel", {"format": "{pretty-name}"}),
    ("display", "Viewscreen", {"format": "{width}x{height} @ {scale-factor}x"}),
    ("cpu", "Mind", {"format": "{name}"}),
    ("gpu", "Stalk eyes", {"format": "{name}"}),
    ("memory", "Memory", {}),
    ("swap", "Z-space", {}),
    ("disk", "Hold", {"folders": "/", "format": "{size-used} of {size-total}"}),
    ("battery", "Power cells", {}),
]

# Thought-speak from the ship: one line, picked at random each time. In
# Mirrorwave the script gives the first three words, as the shell's does.
SAYINGS = [
    "The Dome holds.",
    "Two hours in morph. No more.",
    "Z-space is quiet tonight.",
    "An aristh learns by watching.",
    "Keep your tail blade ready.",
    "The Dome grass is good to run on.",
    "Thought-speak carries far.",
    "The home world is far. The Dome is near.",
    "Every acquired form is a trust.",
    "Stalk eyes up. Watch the stars.",
]


def config(script):
    def key(label):
        return f"{andalite(label)}/{label}" if script else label

    modules = [
        {"type": "title",
         "format": (f"\u001b[33m{andalite('aristh')}/Aristh\u001b[0m " if script else "\u001b[33mAristh\u001b[0m ")
                   + "{user-name-colored}\u001b[34m of the Dome ship \u001b[0m{host-name-colored}",
         "color": {"user": "yellow", "at": "blue", "host": "cyan"}},
        {"type": "custom", "format": "\u001b[34m" + "─" * 34 + "\u001b[0m"},
    ]
    for kind, label, extra in FIELDS:
        m = {"type": kind, "key": key(label)}
        m.update(extra)
        modules.append(m)
    modules += [
        "break",
        {"type": "command", "key": " ", "keyWidth": 1,
         "text": "shuf -n1 @SAYINGS@ 2>/dev/null || echo '< The Dome holds. >'",
         "outputColor": "yellow"},
        "break",
        {"type": "colors", "symbol": "diamond" if script else "block", "paddingLeft": 0},
    ]
    logo = ({"type": "kitty-direct", "source": "@LOGO_PNG@", "width": 16, "height": 8,
             "padding": {"top": 2, "left": 1, "right": 2}}
            if script else
            {"type": "file", "source": "@LOGO_TXT@", "color": {"1": "cyan", "2": "blue"},
             "padding": {"top": 1, "left": 2, "right": 3}})
    return {
        "$schema": "https://github.com/fastfetch-cli/fastfetch/raw/dev/doc/json_schema.json",
        "logo": logo,
        "display": {
            "separator": " ",
            "color": {"keys": "blue", "title": "yellow", "output": "white", "separator": "cyan"},
            # Script letters take one cell each in Mirrorwave, so lengths line up.
            "key": {"width": max(len(key(l)) for _, l, _ in FIELDS) + 1},
        },
        "modules": modules,
    }


OUT.mkdir(parents=True, exist_ok=True)
(OUT / "logo.txt").write_text(text_logo())
(OUT / "sayings-mirrorwave.txt").write_text("".join(f"< {andalite(' '.join(x.split()[:3]))}/{x} >\n" for x in SAYINGS))
(OUT / "sayings-console.txt").write_text("".join(f"< {x} >\n" for x in SAYINGS))
(OUT / "mirrorwave.jsonc").write_text(json.dumps(config(True), ensure_ascii=False, indent=2) + "\n")
(OUT / "console.jsonc").write_text(json.dumps(config(False), ensure_ascii=False, indent=2) + "\n")
print("theme/fastfetch: logo.txt mirrorwave.jsonc console.jsonc")
