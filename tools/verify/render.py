#!/usr/bin/env python3
"""
Rasterise the captured Manor geometry.

A z-buffer rather than a painter's sort, because the whole point is to see
whether the roof actually closes and whether the interior is really enclosed —
and a depth sort papers over exactly those mistakes by drawing things in an
order that happens to look right.
"""

import math
import sys
import pathlib
import numpy as np
from PIL import Image

HERE = pathlib.Path(__file__).parent

# --------------------------------------------------------------------------
# Load
# --------------------------------------------------------------------------


class Part:
    __slots__ = ("cls", "name", "path", "size", "pos", "R", "colour", "material",
                 "transparency", "collide", "tags")


def load(path):
    parts = []
    for line in pathlib.Path(path).read_text().splitlines():
        if not line.startswith("PART\t"):
            continue
        f = line.split("\t")
        p = Part()
        p.cls, p.name, p.path = f[1], f[2], f[3]
        p.size = np.array([float(v) for v in f[4].split(",")])
        p.pos = np.array([float(v) for v in f[5].split(",")])
        r = np.array([float(v) for v in f[6].split(",")])
        u = np.array([float(v) for v in f[7].split(",")])
        b = np.array([float(v) for v in f[8].split(",")])
        p.R = np.column_stack([r, u, b])          # local -> world
        p.colour = np.array([float(v) for v in f[9].split(",")])
        p.material = f[10]
        p.transparency = float(f[11])
        p.collide = f[12] == "true"
        p.tags = f[13] if len(f) > 13 else ""
        parts.append(p)
    return parts


# --------------------------------------------------------------------------
# Geometry
# --------------------------------------------------------------------------

# Box corners, in the order used by the face tables below.
BOX = np.array([[-1, -1, -1], [1, -1, -1], [1, -1, 1], [-1, -1, 1],
                [-1, 1, -1], [1, 1, -1], [1, 1, 1], [-1, 1, 1]], dtype=float)

BOX_FACES = [(0, 1, 2, 3), (4, 7, 6, 5), (0, 4, 5, 1),
             (3, 2, 6, 7), (0, 3, 7, 4), (1, 5, 6, 2)]

# A Roblox WedgePart keeps its full rectangular face on +Z and slopes down to
# -Z; the two +Y,-Z corners are the ones that are missing. Confirmed against the
# module's own gable triangles, which only close if the cut is on that corner.
WEDGE = np.array([[-1, -1, -1], [1, -1, -1], [1, -1, 1], [-1, -1, 1],
                  [-1, 1, 1], [1, 1, 1]], dtype=float)

WEDGE_FACES = [(0, 1, 2, 3), (3, 2, 5, 4), (0, 4, 5, 1), (0, 3, 4), (1, 5, 2)]


def is_emissive(p):
    """Neon, and the tinted panes the module puts a PointLight behind."""
    if p.material == "Neon":
        return True
    return p.material == "Glass" and p.colour[1] > 0.7 and p.colour[1] > p.colour[0] + 0.25


def triangles(parts, keep=None, extra=None):
    """Flatten parts into a world-space triangle soup with per-triangle colour."""
    verts, cols, emis = [], [], []
    for p in parts:
        if p.transparency >= 0.9:
            continue                       # invisible collision ramps, hide markers
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

    for quad, colour in extra or []:
        for a, b in zip(quad[1:-1], quad[2:]):
            verts.append([quad[0], a, b])
            cols.append(colour)
            emis.append(False)

    return np.array(verts), np.array(cols), np.array(emis, dtype=bool)


# --------------------------------------------------------------------------
# Camera
# --------------------------------------------------------------------------


def look_at(eye, target, up=(0, 1, 0)):
    eye, target = np.array(eye, float), np.array(target, float)
    f = target - eye
    f /= np.linalg.norm(f)
    r = np.cross(f, np.array(up, float))
    r /= np.linalg.norm(r)
    u = np.cross(r, f)
    return eye, np.stack([r, u, -f])       # world -> camera rotation


def render(tris, cols, eye, target, emis=None, size=(1400, 900), fov=42.0,
           sky=(0.72, 0.74, 0.73), fog_near=120.0, fog_far=460.0,
           light=(-0.45, 0.78, 0.44), ambient=0.42, ortho=None, up=(0, 1, 0)):
    W, H = size
    eye, M = look_at(eye, target, up)

    cam = (tris.reshape(-1, 3) - eye) @ M.T
    cam = cam.reshape(-1, 3, 3)

    # Flat shading: one normal per triangle, which is what a hard-edged,
    # untextured build actually looks like.
    e1 = tris[:, 1] - tris[:, 0]
    e2 = tris[:, 2] - tris[:, 0]
    n = np.cross(e1, e2)
    ln = np.linalg.norm(n, axis=1, keepdims=True)
    ln[ln == 0] = 1
    n = n / ln

    L = np.array(light, float)
    L /= np.linalg.norm(L)
    lam = np.abs(n @ L)
    shade = np.clip(ambient + (1 - ambient) * lam, 0, 1)[:, None]
    face_col = np.clip(cols * shade, 0, 1)

    # Emissive faces ignore the key light entirely: a lit window is a source,
    # not a surface, and shading it makes the one bright thing in frame dull.
    if emis is not None and emis.any():
        face_col[emis] = np.clip(cols[emis] * 1.15, 0, 1)

    depth = -cam[:, :, 2]

    if ortho is not None:
        scale = min(W, H) / ortho
        sx = W / 2 + cam[:, :, 0] * scale
        sy = H / 2 - cam[:, :, 1] * scale
        visible = depth.min(axis=1) > -1e9
    else:
        focal = (H / 2) / math.tan(math.radians(fov) / 2)
        safe = np.where(depth > 1e-3, depth, 1e-3)
        sx = W / 2 + cam[:, :, 0] * focal / safe
        sy = H / 2 - cam[:, :, 1] * focal / safe
        visible = depth.min(axis=1) > 0.5

    img = np.zeros((H, W, 3), dtype=np.float32)
    img[:] = sky
    zbuf = np.full((H, W), np.inf, dtype=np.float32)

    order = np.argsort(-depth.mean(axis=1))
    for i in order:
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

        # Linear depth across the triangle is not perspective-correct, but the
        # error only matters within one small triangle and never reorders two.
        za, zb, zc = depth[i]
        z = za + w1 * (zb - za) + w0 * (zc - za)

        sub = zbuf[iy0:iy1, ix0:ix1]
        win = inside & (z < sub)
        if not win.any():
            continue

        col = face_col[i]
        if fog_far > fog_near and not (emis is not None and emis[i]):
            t = np.clip((z[win] - fog_near) / (fog_far - fog_near), 0, 1)[:, None]
            blended = col[None, :] * (1 - t) + np.array(sky, float)[None, :] * t
        else:
            blended = np.repeat(col[None, :], win.sum(), axis=0)

        region = img[iy0:iy1, ix0:ix1]
        region[win] = blended
        sub[win] = z[win]

    return Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8))


def frame(parts, keep=None):
    pts = []
    for p in parts:
        if p.transparency >= 0.9:
            continue
        if keep is not None and not keep(p):
            continue
        half = p.size / 2.0
        pts.append((BOX * half) @ p.R.T + p.pos)
    allp = np.concatenate(pts)
    return allp.min(axis=0), allp.max(axis=0)


if __name__ == "__main__":
    parts = load(HERE / "parts.tsv")
    print(f"{len(parts)} parts loaded")
    print(f"{sum(1 for p in parts if is_emissive(p))} emissive")
    lo, hi = frame(parts)
    print("extent x", lo[0], hi[0], " y", lo[1], hi[1], " z", lo[2], hi[2])
