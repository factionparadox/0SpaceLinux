#!/usr/bin/env python3
"""Render the 0-Space background: inside a Dome ship, at night.

Overhead, the dome: a vast shell of glass, its ribs converging above you in
true perspective, catching glints of light. Through it, deep space: a dust-
laned nebula, layered stars, a banded gas giant and its moon. Below, the
parkland the dome carries: hills fading into mist, a stream holding the sky,
blue-green grass with drifting motes of light, and tall tiered trees at the
edges. The centre is kept calm for the carousel; the corners for the pills.

Rendered offline so it can have real glow, haze and grain.

    python3 tools/render-dome.py [out.png] [width] [height]
"""

import math
import sys

import numpy as np
from PIL import Image
from scipy.ndimage import gaussian_filter, zoom, map_coordinates

OUT = sys.argv[1] if len(sys.argv) > 1 else "art/dome.png"
W = int(sys.argv[2]) if len(sys.argv) > 2 else 2880
H = int(sys.argv[3]) if len(sys.argv) > 3 else 1920
S = H / 1920                      # scale for sizes given at full resolution
rng = np.random.default_rng(1996)

yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
u, v = xx / W, yy / H
HZ = 0.62                         # horizon, as a fraction of height


# --- helpers -------------------------------------------------------------------------
def hexc(h):
    h = h.lstrip("#")
    return np.array([int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)], np.float32)


def fbm(octaves=6, base=4, persistence=0.55, seed=0, warp=None):
    """Fractal value noise in [0, 1], from smoothly upscaled random grids."""
    r = np.random.default_rng(seed)
    out = np.zeros((H, W), np.float32)
    amp, total = 1.0, 0.0
    for o in range(octaves):
        n = base * 2 ** o
        gh, gw = max(2, int(n * H / W) + 3), n + 3
        g = r.random((gh, gw)).astype(np.float32)
        if warp is None:
            up = zoom(g, (H / (gh - 1), W / (gw - 1)), order=3)[:H, :W]
        else:
            wy, wx = warp
            up = map_coordinates(g, [(v + wy) * (gh - 2), (u + wx) * (gw - 2)], order=3, mode="mirror")
        out += amp * up
        total += amp
        amp *= persistence
    out /= total
    return (out - out.min()) / (out.max() - out.min() + 1e-6)


def mix(a, b, t):
    t = np.clip(t, 0, 1)
    if np.ndim(t) == 2:
        t = t[..., None]
    return a * (1 - t) + b * t


def blur(img, s):
    s = max(0.5, s * S)
    if img.ndim == 2:
        return gaussian_filter(img, s)
    return np.stack([gaussian_filter(img[..., c], s) for c in range(3)], -1)


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


def add(img, colour, amount):
    """Additive light."""
    return img + amount[..., None] * colour


def over(img, colour, alpha):
    """Paint colour (H,W,3 or 3) over img with alpha (H,W)."""
    return mix(img, colour, alpha)


def splat(points, radius, height_width=None):
    """Sum of small gaussians at sub-pixel points: [(x, y, brightness, r)]."""
    out = np.zeros((H, W), np.float32)
    for x, y, b, r in points:
        rr = max(0.6, r)
        x0, x1 = int(max(0, x - 4 * rr)), int(min(W, x + 4 * rr + 1))
        y0, y1 = int(max(0, y - 4 * rr)), int(min(H, y + 4 * rr + 1))
        if x0 >= x1 or y0 >= y1:
            continue
        gx = np.arange(x0, x1, dtype=np.float32) - x
        gy = np.arange(y0, y1, dtype=np.float32) - y
        out[y0:y1, x0:x1] += b * np.exp(-(gy[:, None] ** 2 + gx[None, :] ** 2) / (2 * rr * rr))
    return out


# --- sky -----------------------------------------------------------------------------
sky_top, sky_mid, sky_low = hexc("#02040e"), hexc("#081633"), hexc("#1a2d63")
t = np.clip(v / HZ, 0, 1)
img = mix(mix(sky_top, sky_mid, smoothstep(0.0, 0.55, t)), sky_low, smoothstep(0.55, 1.0, t))

# Nebula: a warped band from upper left across to the right, with dark dust lanes.
warp = (0.08 * (fbm(4, 3, 0.5, 11) - 0.5), 0.08 * (fbm(4, 3, 0.5, 12) - 0.5))
band_axis = (v - (0.10 + 0.32 * u)) / 0.17            # distance across the band
band = np.exp(-band_axis ** 2) * smoothstep(HZ, HZ - 0.25, v)
cloud = fbm(7, 3, 0.58, 13, warp)
fine = fbm(6, 8, 0.6, 14, warp)
dust = smoothstep(0.52, 0.78, fbm(6, 5, 0.6, 15, warp))
glow = band * smoothstep(0.30, 0.85, cloud) * (0.55 + 0.45 * fine) * (1 - 0.85 * dust)
hue = fbm(3, 2, 0.5, 16)
neb_col = mix(hexc("#2a6fd6"), hexc("#8a3fae"), smoothstep(0.35, 0.7, hue))
img = add(img, neb_col, 0.55 * glow)
img = add(img, hexc("#9fd4ff"), 0.22 * glow ** 2.2)                    # bright cores
img = img * (1 - 0.35 * (band * dust)[..., None])                       # dust lanes darken

# Stars: many faint, some soft and coloured, a few bright with a short cross.
stars = []
n_star = int(9000 * (W * H) / (2880 * 1920))
sx, sy = rng.random(n_star) * W, rng.random(n_star) * H * HZ * 1.02
dens = np.exp(-(((sy / H) - (0.10 + 0.32 * sx / W)) / 0.2) ** 2)      # more along the band
keep = rng.random(n_star) < 0.35 + 0.65 * dens
for x, y in zip(sx[keep], sy[keep]):
    b = rng.random() ** 3.0
    stars.append((x, y, 0.25 + 1.4 * b, (0.55 + 0.9 * b) * S))
starfield = splat(stars, 1)
tint = mix(hexc("#ffd9b0"), hexc("#bfe0ff"), fbm(3, 6, 0.5, 21))
horizon_fade = smoothstep(HZ, HZ - 0.06, v)
img = img + (starfield * horizon_fade)[..., None] * tint
bright = [(rng.random() * W, rng.random() * H * HZ * 0.9) for _ in range(int(26 * W / 2880))]
for x, y in bright:
    core = splat([(x, y, 2.2, 1.6 * S)], 1)
    halo = splat([(x, y, 0.35, 7 * S)], 1)
    L = 22 * S
    cross = np.exp(-((yy - y) ** 2) / (0.6 * S) ** 2) * np.exp(-np.abs(xx - x) / L) \
        + np.exp(-((xx - x) ** 2) / (0.6 * S) ** 2) * np.exp(-np.abs(yy - y) / L)
    img = img + ((core + halo + 0.35 * cross) * horizon_fade)[..., None] * hexc("#dcefff")

# --- the gas giant and its moon -----------------------------------------------------------
gx, gy, gr = 0.815 * W, 0.155 * H, 0.125 * H
dx, dy = (xx - gx) / gr, (yy - gy) / gr
d = np.sqrt(dx ** 2 + dy ** 2)
disc = smoothstep(1.0, 0.993, d)
z = np.sqrt(np.clip(1 - d ** 2, 0, 1))
lat = (dy + 0.16 * dx) / np.maximum(z, 0.25) ** 0.15                     # bands follow the sphere
turb = fbm(5, 12, 0.55, 31)
bands = 0.5 + 0.5 * np.sin(lat * 13 + 4.0 * turb + 1.5 * fbm(4, 30, 0.5, 32))
planet = mix(hexc("#3e6684"), hexc("#9fb9c4"), 0.65 * bands)
planet = mix(planet, hexc("#c9c9bb"), 0.35 * smoothstep(0.7, 0.95, bands) * smoothstep(0.4, 0.8, turb))
storm = np.exp(-(((dx + 0.32) / 0.16) ** 2 + ((dy - 0.28) / 0.07) ** 2))
planet = mix(planet, hexc("#d8c6a8"), 0.55 * storm)
light = np.clip(-0.62 * dx - 0.55 * dy + 0.55 * z, 0, 1)
light = smoothstep(0.0, 0.85, light)
planet = planet * (0.03 + 0.97 * light)[..., None]
img = over(img, planet, disc)
rim = np.exp(-((d - 1.0) / 0.03) ** 2) * np.clip(-dx - 0.4 * dy + 0.35, 0, 1)
img = add(img, hexc("#8fc8ff"), 0.55 * rim)
img = add(img, hexc("#2f5f9e"), 0.18 * np.exp(-np.clip(d - 1, 0, None) / 0.22) * (1 - disc))

mx, my, mr = 0.70 * W, 0.075 * H, 0.016 * H
md = np.sqrt((xx - mx) ** 2 + (yy - my) ** 2) / mr
mdisc = smoothstep(1.0, 0.96, md)
mz = np.sqrt(np.clip(1 - md ** 2, 0, 1))
mlight = np.clip(-0.7 * (xx - mx) / mr - 0.4 * (yy - my) / mr + 0.6 * mz, 0, 1)
moon = mix(hexc("#8d96a8"), hexc("#e8ecf2"), fbm(4, 40, 0.5, 34)) * (0.05 + 0.95 * mlight)[..., None]
img = over(img, moon, mdisc)
img = add(img, hexc("#bcd6ff"), 0.12 * np.exp(-np.clip(md - 1, 0, None) / 0.5) * (1 - mdisc))

# --- the dome: glass ribs in perspective, converging above ----------------------------------
# A hemisphere of radius 1 round the viewer; the camera looks along +z, tilted up.
pitch = math.radians(45)
fov = math.radians(118)
f = (W / 2) / math.tan(fov / 2)


def project(px, py, pz):
    # rotate by pitch about x (looking up), then perspective
    cy, sy_ = math.cos(pitch), math.sin(pitch)
    y2 = py * cy - pz * sy_
    z2 = py * sy_ + pz * cy
    if z2 <= 0.05:
        return None
    # place the optical centre so that the horizon (elevation 0) lands on HZ
    cy0 = H * HZ - f * math.tan(pitch)
    return W / 2 + f * px / z2, cy0 - f * y2 / z2


def polyline(points):
    out = []
    for p in points:
        q = project(*p)
        if q is not None:
            out.append(q)
    return out


def draw_lines(lines, width):
    """Anti-aliased lines as a coverage mask (H, W), via dense gaussian dots."""
    pts = []
    for line in lines:
        for (x0, y0), (x1, y1) in zip(line, line[1:]):
            seg = math.hypot(x1 - x0, y1 - y0)
            n = max(2, int(seg / (0.8 * width)))
            for i in range(n):
                k = i / n
                x, y = x0 + (x1 - x0) * k, y0 + (y1 - y0) * k
                if -10 < x < W + 10 and -10 < y < H * HZ + 10:
                    pts.append((x, y, 1.0, width))
    m = splat(pts, 1)
    return np.clip(m / (m.max() + 1e-6) * 2.2, 0, 1)


ribs = []
for k in range(16):                                             # meridians
    az = 2 * math.pi * k / 16 + 0.11
    pts = []
    for e in np.linspace(0.0, math.pi / 2, 90):
        pts.append((math.cos(e) * math.sin(az), math.sin(e), math.cos(e) * math.cos(az)))
    ribs.append(polyline(pts))
for el in (math.radians(32), math.radians(56)):                  # rings
    pts = []
    for az in np.linspace(-math.pi, math.pi, 400):
        pts.append((math.cos(el) * math.sin(az), math.sin(el), math.cos(el) * math.cos(az)))
    ribs.append(polyline(pts))

rib = draw_lines(ribs, 1.0 * S)
rib_glow = blur(rib, 7)
above = smoothstep(HZ + 0.005, HZ - 0.04, v) * (0.35 + 0.65 * smoothstep(HZ, 0.0, v))
img = add(img, hexc("#9fd4ff"), (0.13 * rib + 0.10 * rib_glow) * above)
# Glints where the starlight catches the ribs, and broad reflections on the glass.
glint = rib * smoothstep(0.80, 0.95, fbm(3, 5, 0.5, 41)) * above
img = add(img, hexc("#e6f4ff"), 0.5 * blur(glint, 1.5) + 0.35 * blur(glint, 9))
sheen = np.exp(-(((u - 0.18) + 0.55 * (v - 0.12)) / 0.07) ** 2) * smoothstep(0.55, 0.0, v)
sheen += 0.6 * np.exp(-(((u - 0.30) + 0.55 * (v - 0.05)) / 0.03) ** 2) * smoothstep(0.4, 0.0, v)
img = add(img, hexc("#7fb6ff"), 0.07 * sheen)

# The dome's rim: a ring of lights where the glass meets the far ground.
rim_y = H * (HZ - 0.004)
lights = [(x, rim_y, 0.35 + 0.5 * rng.random(), 0.9 * S) for x in np.arange(0, W, 52 * S) + rng.random() * 20 * S]
rimlights = splat(lights, 1)
img = add(img, hexc("#bfe6ff"), rimlights + 0.6 * blur(rimlights, 6))
img = add(img, hexc("#4fb0d8"), 0.22 * np.exp(-((v - HZ) / 0.010) ** 2) + 0.10 * np.exp(-((v - HZ) / 0.05) ** 2))

# --- land ------------------------------------------------------------------------------------
def ridge(base, amp, seed, freq, rough=0.5):
    n1 = fbm(5, freq, rough, seed)[0]
    return H * (base - amp * (n1 - 0.5) * 2)


def layer(top_y, col_top, col_bottom, fade_to, haze, soft=1.5):
    """Fill below a ridge line with a vertical gradient, softly edged."""
    mask = smoothstep(top_y[None, :] - soft * S, top_y[None, :] + soft * S, yy)
    depth = np.clip((yy - top_y[None, :]) / (H * 0.25), 0, 1)
    col = mix(col_top, col_bottom, depth)
    col = mix(col, fade_to, haze)
    return mask, col


horizon_col = hexc("#26356e")
far = ridge(HZ + 0.006, 0.012, 51, 6)
far2 = ridge(HZ + 0.030, 0.022, 58, 5)
mid = ridge(HZ + 0.085, 0.040, 52, 4)
near = ridge(HZ + 0.175, 0.060, 53, 3)

def crest(top, col, strength, reach):
    """Light along a ridge's crest, from the horizon glow behind it."""
    global img
    img = add(img, col, strength * np.exp(-np.clip(yy - top[None, :], 0, None) / (reach * S))
              * smoothstep(top[None, :] - 1.5 * S, top[None, :] + 1.5 * S, yy))

def mist_over(top, strength):
    """A band of mist lying in the valley in front of a ridge."""
    global img
    m = np.exp(-((yy - (top[None, :] + 6 * S)) / (26 * S)) ** 2) * (0.6 + 0.4 * fbm(4, 10, 0.5, int(strength * 1000)))
    img = add(img, hexc("#6f8fd0"), strength * m)

mottle = fbm(6, 14, 0.62, 54)
for top, c_top, c_bot, haze, cr, mist in (
        (far, "#3b4a8a", "#2a376e", 0.60, 0.10, 0.10),
        (far2, "#2f4580", "#223563", 0.45, 0.08, 0.10),
        (mid, "#1d3f68", "#142f50", 0.25, 0.07, 0.08),
        (near, "#123447", "#040b12", 0.04, 0.06, 0.05)):
    m, c = layer(top, hexc(c_top), hexc(c_bot), horizon_col, haze)
    c = c * (0.86 + 0.28 * mottle)[..., None]
    img = over(img, c, m)
    crest(top, hexc("#7fb8f0"), cr * 0.6, 14)
    mist_over(top, mist)
    if top is far2:
        # a far forest: tiny tree tops along the ridge, in the haze
        bumps = smoothstep(0.55, 0.8, fbm(3, 90, 0.5, 70)[0])
        treeline = top - bumps * 9 * S
        m2 = smoothstep(treeline[None, :] - 1 * S, treeline[None, :] + 1 * S, yy) * (yy < top[None, :])
        img = over(img, mix(hexc(c_top), horizon_col, haze * 0.6), m2 * 0.85)

# the lake: a still sheet in the middle distance holding the sky
lake_top = H * (HZ + 0.050)
lake_bot = H * (HZ + 0.115)
shore = fbm(4, 7, 0.55, 60)[0]
lx0 = W * (0.22 + 0.05 * (shore[: W] - 0.5))
lake_shape = smoothstep(0.0, 0.035, 1 - np.abs((u - 0.5) / 0.30) ** 2.2 - ((v * H - (lake_top + lake_bot) / 2) / ((lake_bot - lake_top) / 2)) ** 2 * (0.9 + 0.2 * shore[None, :]))
lake = np.clip(lake_shape, 0, 1)
mirror_y = np.clip(2 * lake_top - yy - 2 * S, 0, H - 1) * 0 + np.clip(lake_top - (yy - lake_top) * 2.4 - 6 * S, 0, H - 1)
ripple = 1.6 * S * np.sin(yy / (2.2 * S) + 4 * fbm(3, 30, 0.5, 59))
reflected = np.stack([map_coordinates(img[..., ch], [mirror_y, xx + ripple], order=1, mode="nearest") for ch in range(3)], -1)
water = mix(hexc("#050f1d"), reflected, 0.80)
water = add(water, hexc("#cfeeff"), 0.10 * smoothstep(0.88, 1.0, fbm(5, 80, 0.6, 55)) * lake)
img = over(img, water, lake)
img = add(img, hexc("#9fd4ff"), 0.06 * np.exp(-((lake_shape - 0.02) / 0.02) ** 2) * (lake_shape < 0.2))
stream = lake

# grass streaks in the foreground, darker towards the bottom
blades = fbm(4, 140, 0.5, 56) * smoothstep(0.5, 0.9, fbm(3, 30, 0.5, 57))
fg = smoothstep(near.mean() / H, 1.0, v)
img = img * (1 - 0.65 * fg ** 1.1)[..., None]
img = add(img, hexc("#2a7f8f"), 0.06 * blades * fg * (1 - stream))

# motes: drifting points of light in the meadow
motes = []
for _ in range(int(70 * W / 2880)):
    x = rng.random() * W
    y = H * (HZ + 0.10 + rng.random() * 0.32)
    if abs(x / W - 0.5) < 0.22 and rng.random() < 0.7:
        continue
    motes.append((x, y, 0.9 + rng.random(), (1.2 + rng.random() * 1.6) * S))
mo = splat(motes, 1)
img = add(img, hexc("#9ff0e0"), mo + 0.8 * blur(mo, 6))


# --- trees: tall and slender, with layered canopies --------------------------------------
LEAF = fbm(5, 90, 0.6, 61)                       # shared leaf texture
LEAF_FINE = fbm(4, 260, 0.6, 62)


def tree(x, base, height, col, seed, haze=0.0):
    global img
    r = np.random.default_rng(seed)
    bend = (r.random() - 0.5) * 0.16 * height
    pad = int(0.45 * height)
    x0, x1 = int(max(0, x - pad)), int(min(W, x + pad))
    y0, y1 = int(max(0, base - height * 1.12)), int(min(H, base + 4 * S))
    if x0 >= x1 or y0 >= y1:
        return
    bx, by = xx[y0:y1, x0:x1], yy[y0:y1, x0:x1]
    patch = img[y0:y1, x0:x1]
    far = mix(np.zeros(3, np.float32), horizon_col, haze)

    # trunk: tapering, gently bent, dark with a faint lit edge on the planet's side
    k = np.clip((base - by) / (height * 0.75), 0, 1)
    cx = x + bend * k ** 2
    half = (0.016 * height) * (1 - 0.75 * k) + 0.9 * S
    trunk = smoothstep(half + 1.0, half - 1.0, np.abs(bx - cx)) * (by <= base) * (k < 1)
    bark = mix(hexc("#04080f"), horizon_col, haze)
    patch = mix(patch, bark, trunk)
    edge = trunk * smoothstep(-0.2, 0.9, (bx - cx) / np.maximum(half, 1e-3))
    patch = patch + (0.10 * (1 - haze) * edge)[..., None] * hexc("#7fb8f0")

    # crown: a few irregular foliage clumps on branches, each made of many small leafy tufts.
    # Shading is mostly per-clump (not per-tuft), so it reads as foliage rather than bubbles.
    cxc = x + bend * 0.55
    cyc = base - height * 0.66
    rx, ry = height * 0.24, height * 0.30
    leafy = LEAF[y0:y1, x0:x1]
    fine = LEAF_FINE[y0:y1, x0:x1]
    mask = np.zeros_like(bx)
    shade = np.zeros_like(bx)
    nclump = 4 + int(r.random() * 3)
    clumps = [(cxc + (r.random() - 0.5) * 0.10 * height, cyc - ry * 0.55, 0.15 * height)]
    for i in range(nclump - 1):
        a_ = (i / (nclump - 1)) * math.pi + (r.random() - 0.5) * 0.5
        clumps.append((cxc + rx * 0.75 * math.cos(a_ + math.pi) * (0.7 + 0.4 * r.random()),
                       cyc + ry * (0.05 + 0.45 * r.random()) - ry * 0.25 * math.sin(a_),
                       height * (0.10 + 0.05 * r.random())))
    for (ccx, ccy, cr) in clumps:
        # branch from the trunk to the clump
        tb = base - height * 0.5
        sx = x + bend * 0.25
        t = np.clip(((bx - sx) * (ccx - sx) + (by - tb) * (ccy - tb)) / max((ccx - sx) ** 2 + (ccy - tb) ** 2, 1), 0, 1)
        d = np.hypot(bx - (sx + t * (ccx - sx)), by - (tb + t * (ccy - tb)))
        bw = (0.010 * height) * (1 - 0.7 * t) + 0.7 * S
        patch = mix(patch, bark, smoothstep(bw + 1.0, bw - 1.0, d))
        for _ in range(30):
            a_ = r.random() * 2 * math.pi
            rr = math.sqrt(r.random())
            ox, oy = cr * 0.8 * rr * math.cos(a_), cr * 0.6 * rr * math.sin(a_)
            br = height * (0.022 + 0.022 * r.random())
            e = ((bx - (ccx + ox)) / br) ** 2 + ((by - (ccy + oy)) / (br * 0.75)) ** 2
            blob = smoothstep(1.0 + 0.8 * (leafy - 0.5) + 0.7 * (fine - 0.5), 0.55, e)
            tuft = np.clip(0.75 - 0.25 * (by - (ccy + oy)) / br, 0, 1)
            clump = np.clip(0.55 - (by - ccy) / (cr * 1.5) + 0.5 * (bx - ccx) / cr, 0, 1)
            crown = np.clip(0.5 - (by - cyc) / (ry * 2.0) + 0.5 * (bx - cxc) / rx, 0, 1)
            lit = tuft * (0.25 + 0.75 * clump) * (0.35 + 0.65 * crown)
            shade = np.where(blob > mask, lit, shade)
            mask = np.maximum(mask, blob)
    canopy = mix(col * 0.05, col * 0.70, (shade * (0.45 + 0.5 * leafy + 0.5 * fine)) ** 1.25)
    canopy = mix(canopy, horizon_col * 0.9, haze)
    patch = mix(patch, canopy, mask)
    inner = gaussian_filter(mask, 3.0 * S)
    edge = np.clip(mask * (1 - inner) * 2.2, 0, 1)
    rim = edge * np.clip(0.2 + (bx - cxc) / rx - 0.7 * (by - cyc) / ry, 0, 1)
    patch = patch + (0.45 * (1 - haze) * rim)[..., None] * hexc("#a8d8ff")
    img[y0:y1, x0:x1] = patch


ground = lambda x: near[int(np.clip(x, 0, W - 1))] + 0.015 * H          # noqa: E731
canopy_cols = [hexc("#3a5fb0"), hexc("#5a46a0"), hexc("#2b7f9a"), hexc("#7a4a96")]
placements = [  # x, extra depth below the near ridge, height, colour, haze
    (0.065, 0.20, 0.52, 0, 0.0), (0.165, 0.10, 0.34, 1, 0.08), (0.240, 0.035, 0.18, 2, 0.32),
    (0.940, 0.22, 0.55, 1, 0.0), (0.845, 0.11, 0.33, 2, 0.08), (0.770, 0.04, 0.17, 3, 0.32),
]
for i, (tx, dep, th, ci, hz) in sorted(enumerate(placements), key=lambda p: p[1][1]):
    xpix = tx * W
    tree(xpix, ground(xpix) + dep * H, th * H, canopy_cols[ci], 100 + i, hz)

# --- finish: bloom, vignette, grain -----------------------------------------------------------
lum = img.mean(-1)
bloom = blur(np.clip(img - 0.55, 0, None), 18) * 0.6 + blur(np.clip(img - 0.35, 0, None), 4) * 0.25
img = img + bloom
vig = 1 - 0.35 * smoothstep(0.55, 1.15, np.sqrt(((u - 0.5) * 1.15) ** 2 + ((v - 0.48) * 1.0) ** 2))
img = img * vig[..., None]
img = img + (rng.standard_normal((H, W, 1)).astype(np.float32) * 0.010)
img = np.clip(img, 0, 1) ** (1 / 1.04)
Image.fromarray((img * 255 + 0.5).astype(np.uint8)).save(OUT, optimize=True)
print(OUT, W, H)
