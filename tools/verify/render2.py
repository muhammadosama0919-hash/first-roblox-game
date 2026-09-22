#!/usr/bin/env python3
"""
Preview renderer, second pass: material patterns and edge lines.

Roblox draws WoodPlanks, RoofShingles, Cobblestone and Brick with real
textures, and lights every part edge. A flat-colour preview hides both, so the
house looks worse here than it will in Studio. This pass approximates each
material with a procedural pattern in the part's own coordinates and darkens
every pixel where one part meets another, so the preview shows the geometry
the way the engine will — not photoreal, but honest about what is there.
"""

import math
import pathlib
import numpy as np
from PIL import Image
from render import load, BOX, BOX_FACES, WEDGE, WEDGE_FACES, is_emissive

HERE = pathlib.Path(__file__).parent


# --------------------------------------------------------------------------
# Triangle soup with a part index per triangle
# --------------------------------------------------------------------------


def soup(parts, keep=None, extra=None):
    verts, cols, emis, pid = [], [], [], []
    for i, p in enumerate(parts):
        if p.transparency >= 0.9:
            continue
        if keep is not None and not keep(p):
            continue
        half = p.size / 2.0
        local = (WEDGE if p.cls == "WedgePart" else BOX) * half
        world = local @ p.R.T + p.pos
        faces = WEDGE_FACES if p.cls == "WedgePart" else BOX_FACES
        glow = is_emissive(p)
        for face in faces:
            for a, b in zip(face[1:-1], face[2:]):
                verts.append([world[face[0]], world[a], world[b]])
                cols.append(p.colour)
                emis.append(glow)
                pid.append(i)
    for quad, colour in extra or []:
        for a, b in zip(quad[1:-1], quad[2:]):
            verts.append([quad[0], a, b])
            cols.append(colour)
            emis.append(False)
            pid.append(-1)
    return (np.array(verts), np.array(cols), np.array(emis, dtype=bool),
            np.array(pid, dtype=np.int32))


# --------------------------------------------------------------------------
# Material patterns, evaluated at world points inside a known part
# --------------------------------------------------------------------------


def hash2(a, b):
    """Cheap deterministic noise in [0, 1) from two integer grids."""
    h = (a * 374761393 + b * 668265263) & 0x7FFFFFFF
    h = (h ^ (h >> 13)) * 1274126177 & 0x7FFFFFFF
    return ((h ^ (h >> 16)) & 0xFFFF) / 65536.0


def pattern(material, local, size):
    """Multiplier on the base colour, shape (N,)."""
    n = local.shape[0]
    out = np.ones(n)
    if n == 0:
        return out

    order = np.argsort(-size)            # longest local axis first
    u = local[:, order[0]]
    v = local[:, order[1]]

    if material == "WoodPlanks":
        seam = np.abs(((v / 1.6) % 1.0) - 0.5) > 0.44
        stagger = np.floor(v / 1.6) % 2
        ends = np.abs((((u + stagger * 4.0) / 8.0) % 1.0) - 0.5) > 0.47
        grain = 0.94 + 0.06 * hash2(np.floor(u * 0.7).astype(np.int64),
                                    np.floor(v / 1.6).astype(np.int64))
        out = grain * np.where(seam, 0.78, 1.0) * np.where(ends, 0.86, 1.0)

    elif material == "Wood":
        grain = 0.95 + 0.05 * hash2(np.floor(u * 0.5).astype(np.int64),
                                    np.floor(v * 3).astype(np.int64))
        out = grain

    elif material == "RoofShingles":
        row = np.floor(v / 1.4)
        seam = ((v / 1.4) % 1.0) < 0.16
        stagger = (row % 2) * 1.1
        col = np.abs((((u + stagger) / 2.2) % 1.0) - 0.5) > 0.46
        tone = 0.9 + 0.1 * hash2(np.floor((u + stagger) / 2.2).astype(np.int64),
                                 row.astype(np.int64))
        out = tone * np.where(seam, 0.7, 1.0) * np.where(col, 0.84, 1.0)

    elif material == "Cobblestone":
        row = np.floor(v / 1.1)
        stagger = (row % 2) * 0.8
        cx = np.floor((u + stagger) / 1.6)
        tone = 0.82 + 0.26 * hash2(cx.astype(np.int64), row.astype(np.int64))
        mortar = (((u + stagger) / 1.6) % 1.0 < 0.13) | ((v / 1.1) % 1.0 < 0.16)
        out = tone * np.where(mortar, 0.62, 1.0)

    elif material == "Brick":
        row = np.floor(v / 0.9)
        stagger = (row % 2) * 1.5
        cx = np.floor((u + stagger) / 3.0)
        tone = 0.88 + 0.16 * hash2(cx.astype(np.int64), row.astype(np.int64))
        mortar = (((u + stagger) / 3.0) % 1.0 < 0.08) | ((v / 0.9) % 1.0 < 0.18)
        out = tone * np.where(mortar, 0.68, 1.0)

    elif material == "Rock":
        out = np.full(n, 0.85 + 0.3 * hash2(np.floor(u).astype(np.int64) * 0 + 7,
                                            np.floor(v).astype(np.int64) * 0 + 3)[0])

    elif material == "Plaster":
        out = 0.95 + 0.05 * hash2(np.floor(u * 0.8).astype(np.int64),
                                  np.floor(v * 0.8).astype(np.int64))

    elif material == "Slate":
        out = 0.92 + 0.08 * hash2(np.floor(u).astype(np.int64), np.floor(v).astype(np.int64))

    return out


# --------------------------------------------------------------------------
# Rasteriser
# --------------------------------------------------------------------------


def look_at(eye, target):
    eye, target = np.array(eye, float), np.array(target, float)
    f = target - eye
    f /= np.linalg.norm(f)
    r = np.cross(f, np.array([0, 1, 0], float))
    r /= np.linalg.norm(r)
    u = np.cross(r, f)
    return eye, np.stack([r, u, -f])


def render(parts, tris, cols, emis, pid, eye, target, size=(1500, 950), fov=40.0,
           sky=(0.64, 0.65, 0.63), fog_near=170.0, fog_far=560.0,
           key=(-0.5, 0.75, 0.45), fill=(0.7, 0.3, -0.4), ambient=0.30,
           edge_strength=0.22):
    W, H = size
    eye, M = look_at(eye, target)
    cam = ((tris.reshape(-1, 3) - eye) @ M.T).reshape(-1, 3, 3)

    e1, e2 = tris[:, 1] - tris[:, 0], tris[:, 2] - tris[:, 0]
    n = np.cross(e1, e2)
    ln = np.linalg.norm(n, axis=1, keepdims=True)
    ln[ln == 0] = 1
    n /= ln

    # Two lights so the shadow side is modelled rather than black.
    K = np.array(key, float); K /= np.linalg.norm(K)
    F = np.array(fill, float); F /= np.linalg.norm(F)
    lam = ambient + 0.62 * np.abs(n @ K) + 0.18 * np.abs(n @ F)
    # Upward faces catch the sky; downward ones (soffits, undersides) do not.
    lam += 0.10 * np.clip(n[:, 1], 0, 1) - 0.08 * np.clip(-n[:, 1], 0, 1)
    shade = np.clip(lam, 0, 1)

    depth = -cam[:, :, 2]
    focal = (H / 2) / math.tan(math.radians(fov) / 2)
    safe = np.where(depth > 1e-3, depth, 1e-3)
    sx = W / 2 + cam[:, :, 0] * focal / safe
    sy = H / 2 - cam[:, :, 1] * focal / safe
    visible = depth.min(axis=1) > 0.5

    img = np.zeros((H, W, 3), dtype=np.float32)
    img[:] = sky
    zbuf = np.full((H, W), np.inf, dtype=np.float32)
    ids = np.full((H, W), -2, dtype=np.int32)
    skyc = np.array(sky, float)

    for i in np.argsort(-depth.mean(axis=1)):
        if not visible[i]:
            continue
        x0, x1 = sx[i].min(), sx[i].max()
        y0, y1 = sy[i].min(), sy[i].max()
        if x1 < 0 or x0 >= W or y1 < 0 or y0 >= H:
            continue
        ix0, ix1 = max(0, int(x0)), min(W, int(x1) + 2)
        iy0, iy1 = max(0, int(y0)), min(H, int(y1) + 2)
        if ix1 <= ix0 or iy1 <= iy0:
            continue

        ax, ay = sx[i, 0], sy[i, 0]
        bx, by = sx[i, 1], sy[i, 1]
        cx, cy = sx[i, 2], sy[i, 2]
        area = (bx - ax) * (cy - ay) - (cx - ax) * (by - ay)
        if abs(area) < 1e-9:
            continue

        yy, xx = np.mgrid[iy0:iy1, ix0:ix1]
        px, py = xx + 0.5, yy + 0.5
        w0 = ((bx - ax) * (py - ay) - (px - ax) * (by - ay)) / area
        w1 = ((px - ax) * (cy - ay) - (cx - ax) * (py - ay)) / area
        inside = (w0 >= 0) & (w1 >= 0) & (w0 + w1 <= 1)
        if not inside.any():
            continue

        za, zb, zc = depth[i]
        z = za + w1 * (zb - za) + w0 * (zc - za)
        sub = zbuf[iy0:iy1, ix0:ix1]
        win = inside & (z < sub)
        if not win.any():
            continue

        base = cols[i] * (1.0 if emis[i] else shade[i])
        count = int(win.sum())

        if pid[i] >= 0 and not emis[i]:
            p = parts[pid[i]]
            A, B, C = tris[i]
            wp = A + w1[win][:, None] * (B - A) + w0[win][:, None] * (C - A)
            local = (wp - p.pos) @ p.R
            mult = pattern(p.material, local, p.size)
            colour = np.clip(base[None, :] * mult[:, None], 0, 1)
        else:
            colour = np.repeat(np.clip(base, 0, 1)[None, :], count, axis=0)

        if not emis[i]:
            t = np.clip((z[win] - fog_near) / (fog_far - fog_near), 0, 1)[:, None]
            colour = colour * (1 - t) + skyc[None, :] * t

        img[iy0:iy1, ix0:ix1][win] = colour
        sub[win] = z[win]
        ids[iy0:iy1, ix0:ix1][win] = pid[i]

    # Edge lines: wherever the part under a pixel differs from its neighbour,
    # or the depth jumps, darken. That is what a lit edge does in the engine.
    edge = np.zeros((H, W), dtype=bool)
    for dy, dx in ((0, 1), (1, 0)):
        a = ids[dy:, dx:]
        b = ids[: H - dy, : W - dx]
        za = zbuf[dy:, dx:]
        zb = zbuf[: H - dy, : W - dx]
        diff = (a != b) | (np.abs(za - zb) > 1.2)
        diff &= (a != -2) | (b != -2)
        edge[dy:, dx:] |= diff
        edge[: H - dy, : W - dx] |= diff

    # Softer with distance, so far edges do not turn into a dark mesh.
    with np.errstate(invalid="ignore"):
        far = np.clip((zbuf - fog_near) / (fog_far - fog_near), 0, 1)
    far = np.where(np.isfinite(zbuf), far, 1.0)
    strength = edge_strength * (1 - far)
    img[edge] *= (1 - strength[edge])[:, None]

    return Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8))


# --------------------------------------------------------------------------
# Shots
# --------------------------------------------------------------------------


def extent(parts, keep=None):
    pts = []
    for p in parts:
        if p.transparency >= 0.9 or (keep and not keep(p)):
            continue
        pts.append((BOX * (p.size / 2)) @ p.R.T + p.pos)
    allp = np.concatenate(pts)
    return allp.min(axis=0), allp.max(axis=0)


if __name__ == "__main__":
    import sys
    out = HERE / "out"
    out.mkdir(exist_ok=True)
    parts = load(HERE / "parts.tsv")
    lo, hi = extent(parts)
    centre = (lo + hi) / 2
    radius = float(np.linalg.norm(hi - lo) / 2)

    EARTH = np.array([0.19, 0.15, 0.12])
    REACH, TILES = 420.0, 14
    gy = lo[1] + 0.4
    ground = []
    for i in range(TILES):
        for j in range(TILES):
            x0 = -REACH + 2 * REACH * i / TILES
            x1 = -REACH + 2 * REACH * (i + 1) / TILES
            z0 = -REACH + 2 * REACH * j / TILES
            z1 = -REACH + 2 * REACH * (j + 1) / TILES
            ground.append((np.array([[x0, gy, z0], [x1, gy, z0], [x1, gy, z1], [x0, gy, z1]]),
                           EARTH * (0.9 + 0.1 * ((i + j) % 2))))

    def eye_for(direction, target, fov, margin, size):
        d = np.array(direction, float); d /= np.linalg.norm(d)
        W, H = size
        half = math.radians(fov) / 2
        hhalf = math.atan(math.tan(half) * W / H)
        return np.array(target, float) + d * radius * margin / math.sin(min(half, hhalf))

    def shoot(name, direction, target, keep=None, fov=38.0, margin=1.03,
              size=(1500, 950), with_ground=True, eye=None):
        tris, cols, emis, pid = soup(parts, keep, ground if with_ground else None)
        e = eye if eye is not None else eye_for(direction, target, fov, margin, size)
        img = render(parts, tris, cols, emis, pid, e, target, size=size, fov=fov)
        img.save(out / name)
        print(f"{name}: {len(tris)} tris")

    only = sys.argv[1:] or ["hero", "front", "detail", "side", "back", "cutaway"]
    base = np.array([centre[0], (lo[1] + hi[1]) / 2, centre[2]])

    if "hero" in only:
        shoot("11-hero.png", (0.78, 0.24, 0.85), base + np.array([0, -4.0, 0]), fov=36, margin=1.0)
    if "front" in only:
        shoot("12-front.png", (0.05, 0.12, 1.0), base + np.array([0, -2.0, 0]), fov=34, margin=1.0)
    if "detail" in only:
        # Close on the porch and bay from ground level, as a player would see it.
        shoot("13-detail.png", None, np.array([0.0, 12.0, 30.0]), fov=48,
              eye=np.array([52.0, 4.0, 88.0]))
    if "side" in only:
        shoot("14-side.png", (1.0, 0.14, 0.15), base, fov=34, margin=1.02)
    if "back" in only:
        shoot("15-back.png", (-0.6, 0.22, -0.9), base, fov=36, margin=1.03)
    if "cutaway" in only:
        shoot("16-cutaway.png", (0.42, 0.30, 1.0), base, keep=lambda p: p.pos[2] < 2.0,
              fov=38, margin=1.0, with_ground=False)
    print("done")
