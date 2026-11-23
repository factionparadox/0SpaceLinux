#!/usr/bin/env python3
"""Render the 0-Space Dome background.

A night under the dome on the Andalite homeworld: deep sky and nebula, stars,
two moons, the dome's glass catching the light, hills fading into mist, and
the red, blue and pink trees of home. Rendered offline so it can have real
glow, haze and grain, which the live shell cannot draw.

    python3 tools/render-dome.py [out.png] [width] [height]
"""

import sys
import numpy as np
from PIL import Image
from scipy.ndimage import gaussian_filter, zoom

OUT = sys.argv[1] if len(sys.argv) > 1 else "system_files/usr/share/0space/art/dome.png"
W = int(sys.argv[2]) if len(sys.argv) > 2 else 2880
H = int(sys.argv[3]) if len(sys.argv) > 3 else 1920
rng = np.random.default_rng(1996)

yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
u, v = xx / W, yy / H


def hexc(h):
    h = h.lstrip("#")
    return np.array([int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)], np.float32)


def fbm(octaves=6, base=4, persistence=0.55, seed=0):
    """Fractal noise in [0, 1], built from smoothly upscaled random grids."""
    r = np.random.default_rng(seed)
    out = np.zeros((H, W), np.float32)
    amp, total = 1.0, 0.0
    for o in range(octaves):
        n = base * 2 ** o
        gh, gw = max(2, int(n * H / W) + 2), n + 2
        g = r.random((gh, gw)).astype(np.float32)
        up = zoom(g, (H / gh, W / gw), order=3)[:H, :W]
        out += amp * up
        total += amp
        amp *= persistence
    out /= total
    return (out - out.min()) / (out.max() - out.min() + 1e-6)


def mix(a, b, t):
    t = np.clip(t, 0, 1)[..., None]
    return a * (1 - t) + b * t


def blur(img, s):
    if img.ndim == 2:
        return gaussian_filter(img, s)
    return np.stack([gaussian_filter(img[..., c], s) for c in range(3)], -1)


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


HZ = 0.74  # horizon, as a fraction of height

# --- sky ----------------------------------------------------------------------
img = np.zeros((H, W, 3), np.float32)
stops = [(0.00, "#02050d"), (0.30, "#060d22"), (0.55, "#101a3a"),
         (0.68, "#2a1b44"), (HZ, "#7a3e62"), (1.00, "#7a3e62")]
for (p0, c0), (p1, c1) in zip(stops, stops[1:]):
    band = (v >= p0) & (v <= p1)
    t = (v - p0) / max(1e-6, p1 - p0)
    img[band] = mix(np.broadcast_to(hexc(c0), img.shape), np.broadcast_to(hexc(c1), img.shape), t)[band]

# Nebula: two noise fields, coloured, masked to the upper sky, softly lit.
n1 = fbm(7, 3, 0.58, seed=3)
n2 = fbm(6, 5, 0.55, seed=8)
neb_mask = smoothstep(0.0, 0.25, v) * (1 - smoothstep(0.35, 0.66, v))
band_shape = np.exp(-((v - (0.16 + 0.22 * u)) ** 2) / 0.045)  # a wide diagonal drift of cloud
cloud = np.clip((n1 - 0.38) * 1.8, 0, 1) ** 1.8 * band_shape * neb_mask
wisps = np.clip((n2 - 0.55) * 3.0, 0, 1) ** 2 * neb_mask
img += cloud[..., None] * hexc("#3d5bb5") * 0.32
img += (cloud * n2)[..., None] * hexc("#8a4fb0") * 0.30
img += wisps[..., None] * hexc("#2f8fa8") * 0.18
img += blur(cloud, 60)[..., None] * hexc("#4a6ad0") * 0.22       # glow round the cloud

# Stars: many faint, a few bright with bloom, slight colour variation.
stars = np.zeros((H, W, 3), np.float32)
count = int(W * H / 900)
sx = rng.integers(0, W, count)
sy = (rng.random(count) ** 1.25 * H * (HZ - 0.02)).astype(int)
mag = rng.random(count) ** 6
tint = np.where(rng.random(count)[:, None] < 0.3, hexc("#ffd9b8"), hexc("#cfe0ff"))
for x, y, m, t in zip(sx, sy, mag, tint):
    stars[y, x] += t * (0.25 + 2.5 * m)
dim = (1 - smoothstep(0.45, HZ, v))[..., None]
img += stars * dim
img += blur(stars, 2.0) * 2.5 * dim
img += blur(stars, 7.0) * 3.0 * dim

# --- moons --------------------------------------------------------------------
def moon(cx, cy, r, lit, shade, seed):
    global img
    d = np.sqrt((xx - cx) ** 2 + (yy - cy) ** 2)
    disk = smoothstep(r + 1.5, r - 1.5, d)
    # Lit from the upper left.
    nx, ny = (xx - cx) / r, (yy - cy) / r
    nz = np.sqrt(np.clip(1 - nx ** 2 - ny ** 2, 0, 1))
    light = np.clip(-0.55 * nx - 0.5 * ny + 0.67 * nz, 0, 1)
    craters = fbm(5, 24, 0.5, seed=seed)
    surface = mix(np.broadcast_to(hexc(shade), img.shape), np.broadcast_to(hexc(lit), img.shape),
                  light * (0.8 + 0.25 * craters))
    img = mix(img, surface, disk)
    halo = np.exp(-np.clip(d - r, 0, None) / (r * 1.6)) * (1 - disk)
    img += halo[..., None] * hexc(lit) * 0.18

moon(W * 0.835, H * 0.15, H * 0.034, "#f2e6cf", "#3a3442", 21)
moon(W * 0.885, H * 0.205, H * 0.014, "#c9dbf7", "#232a44", 22)

# --- the dome's glass ------------------------------------------------------------
# A huge curve of glass overhead: a soft bright rim and a faint broad sheen.
ecx, ecy, erx, ery = W * 0.5, H * (HZ + 0.02), W * 0.78, H * 0.95
rad = np.sqrt(((xx - ecx) / erx) ** 2 + ((yy - ecy) / ery) ** 2)
rim = np.exp(-((rad - 1.0) ** 2) / 0.00004) * (v < HZ)
sheen = np.exp(-((rad - 0.93) ** 2) / 0.002) * (v < HZ) * smoothstep(0.0, 0.5, u) * (1 - smoothstep(0.5, 1.0, u))
img += blur(rim, 1.2)[..., None] * hexc("#b9e2ff") * 0.30
img += blur(rim, 10)[..., None] * hexc("#7fb8ff") * 0.18
img += blur(sheen, 25)[..., None] * hexc("#9fc8ff") * 0.05

# --- horizon glow and hills --------------------------------------------------------
glow = np.exp(-(((u - 0.5) / 0.55) ** 2) - ((v - HZ) / 0.06) ** 2)
img += glow[..., None] * hexc("#e48aa6") * 0.30


def ridge(base, amp, seed, freq):
    r = np.random.default_rng(seed)
    xs = np.linspace(0, 1, W)
    y = np.zeros(W)
    a, f = 1.0, freq
    for _ in range(6):
        ph = r.random() * 6.283
        y += a * np.sin(xs * f * 6.283 + ph) * (0.6 + 0.4 * r.random())
        a *= 0.5
        f *= 2.1
    return (base - amp * y) * H


haze_col = hexc("#6b3a62")
layers = [(HZ - 0.005, 0.020, 1, 1.3, "#3b2a5a", 0.65),
          (HZ + 0.020, 0.024, 2, 1.7, "#24234a", 0.38),
          (HZ + 0.050, 0.018, 3, 2.2, "#14223a", 0.15),
          (HZ + 0.090, 0.022, 4, 1.5, "#0b1626", 0.0)]
for base, amp, seed, freq, col, haze in layers:
    top = ridge(base, amp, seed, freq)
    mask = smoothstep(-1.5, 1.5, yy - top[None, :])
    shade = mix(np.broadcast_to(hexc(col), img.shape), np.broadcast_to(haze_col, img.shape),
                np.full((H, W), haze))
    # Each layer darkens towards its foot.
    shade = shade * (1 - 0.35 * smoothstep(0, 0.25, v - base))[..., None]
    img = mix(img, shade, mask)
    # Mist lying in the valley in front of this layer.
    mist = np.exp(-((yy - top[None, :] - H * 0.012) / (H * 0.018)) ** 2) * mask
    img += blur(mist, 12)[..., None] * hexc("#c58fb0") * (0.10 * (1 - haze) + 0.05)

# --- trees -----------------------------------------------------------------------------
def tree(tx, base, th, col, seed):
    global img
    r = np.random.default_rng(seed)
    sil = np.zeros((H, W), np.float32)
    lit = np.zeros((H, W), np.float32)
    # Trunk: a gently curving tapered line.
    ts = np.linspace(0, 1, 400)
    bend = r.uniform(-0.12, 0.12)
    px = tx + th * (bend * np.sin(ts * 3.1) + 0.03 * ts)
    py = base - th * ts
    for x, y, t in zip(px, py, ts):
        w = th * (0.035 * (1 - t) + 0.012)
        x0, x1 = int(x - w), int(x + w) + 1
        y0, y1 = int(y - 2), int(y + 2)
        sil[max(0, y0):max(0, y1), max(0, x0):max(0, x1)] = 1
    # Canopy: a cloud of soft blobs, lit from the upper left.
    top_x, top_y = px[-1], py[-1]
    for _ in range(90):
        a = r.uniform(0, 6.283)
        d = r.random() ** 0.6
        bx = top_x + np.cos(a) * d * th * 0.42
        by = top_y + np.sin(a) * d * th * 0.24 - th * 0.02
        br = th * r.uniform(0.05, 0.11)
        x0, x1 = int(max(0, bx - br * 2)), int(min(W, bx + br * 2))
        y0, y1 = int(max(0, by - br * 2)), int(min(H, by + br * 2))
        if x1 <= x0 or y1 <= y0:
            continue
        dd = np.sqrt((xx[y0:y1, x0:x1] - bx) ** 2 + (yy[y0:y1, x0:x1] - by) ** 2)
        blob = smoothstep(br, br * 0.85, dd)
        sil[y0:y1, x0:x1] = np.maximum(sil[y0:y1, x0:x1], blob)
        side = np.clip(((bx - top_x) * -0.6 + (by - top_y) * -1.0) / (th * 0.4) + 0.5, 0, 1)
        lit[y0:y1, x0:x1] = np.maximum(lit[y0:y1, x0:x1], blob * side * (1 - d * 0.5))
    sil = blur(sil, 1.0)
    body = mix(np.broadcast_to(hexc("#0a0b18"), img.shape), np.broadcast_to(hexc(col), img.shape), lit * 0.55)
    img = mix(img, body, sil)
    img += blur(lit * sil, 6)[..., None] * hexc(col) * 0.10   # faint bioluminescence

tree(W * 0.030, H * 0.90, H * 0.20, "#c75f92", 31)
tree(W * 0.085, H * 0.875, H * 0.12, "#4f78c8", 32)
tree(W * 0.150, H * 0.845, H * 0.065, "#c24d5c", 33)
tree(W * 0.968, H * 0.905, H * 0.22, "#c24d5c", 34)
tree(W * 0.915, H * 0.872, H * 0.11, "#c75f92", 35)
tree(W * 0.860, H * 0.848, H * 0.06, "#4f78c8", 36)

# --- finish: bloom, vignette, grain ----------------------------------------------------
bright = np.clip(img - 0.55, 0, None)
img += blur(bright, 18) * 0.35
vig = 1 - 0.38 * smoothstep(0.35, 1.0, np.sqrt(((u - 0.5) / 0.7) ** 2 + ((v - 0.48) / 0.75) ** 2))
img *= vig[..., None]
img += (rng.standard_normal((H, W, 1)).astype(np.float32)) * 0.012
img = np.clip(img, 0, 1) ** (1 / 1.05)

Image.fromarray((img * 255 + 0.5).astype(np.uint8), "RGB").save(OUT, optimize=True)
print(f"< Dome rendered: {OUT} ({W}x{H}) >")
