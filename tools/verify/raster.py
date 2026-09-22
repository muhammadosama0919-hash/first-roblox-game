#!/usr/bin/env python3
"""
Z-buffer preview renderer for a captured house.

A z-buffer rather than a painter's sort, because the point is to see whether
a roof really closes and a room is really enclosed — a depth sort papers over
exactly those mistakes by drawing things in an order that happens to look
right.

Every Roblox part shape the kit uses is tessellated: blocks, wedges,
cylinders (axis along the part's X, diameter the smaller of Y and Z, as the
engine draws them) and balls. Materials are approximated by procedural
patterns in each part's own coordinates, and every edge where one part meets
another is darkened, the way the engine's lighting picks them out. Not
photoreal; honest about what geometry exists.

Big triangles are rasterised one at a time with their material pattern.
Small ones — the facets of every chair leg and door knob, which are most of
the triangles in a furnished house — are rasterised in vectorised batches
with flat colour, which is what keeps a furnished interior renderable at all.
"""

import math

import numpy as np
from PIL import Image

# --------------------------------------------------------------------------
# Unit meshes
# --------------------------------------------------------------------------

BOX = np.array([[-1, -1, -1], [1, -1, -1], [1, -1, 1], [-1, -1, 1],
                [-1, 1, -1], [1, 1, -1], [1, 1, 1], [-1, 1, 1]], dtype=float)
BOX_FACES = [(0, 1, 2, 3), (4, 7, 6, 5), (0, 4, 5, 1),
             (3, 2, 6, 7), (0, 3, 7, 4), (1, 5, 6, 2)]

# A Roblox WedgePart keeps its full rectangular face on +Z and slopes down to
# -Z; the two +Y,-Z corners are the ones that are missing.
WEDGE = np.array([[-1, -1, -1], [1, -1, -1], [1, -1, 1], [-1, -1, 1],
                  [-1, 1, 1], [1, 1, 1]], dtype=float)
WEDGE_FACES = [(0, 1, 2, 3), (3, 2, 5, 4), (0, 4, 5, 1), (0, 3, 4), (1, 5, 2)]


def _fan(faces):
    tris = []
    for face in faces:
        for a, b in zip(face[1:-1], face[2:]):
            tris.append((face[0], a, b))
    return np.array(tris, dtype=int)


BOX_TRIS = _fan(BOX_FACES)
WEDGE_TRIS = _fan(WEDGE_FACES)

_cyl_cache = {}
_ball_cache = {}


def cylinder_mesh(n):
    """Unit cylinder along X: x in [-1, 1], radius 1. Returns (verts, tris)."""
    if n in _cyl_cache:
        return _cyl_cache[n]
    ang = np.linspace(0, 2 * math.pi, n, endpoint=False)
    ring = np.stack([np.cos(ang), np.sin(ang)], axis=1)
    verts = np.concatenate([
        np.column_stack([-np.ones(n), ring]),
        np.column_stack([np.ones(n), ring]),
    ])
    tris = []
    for i in range(n):
        j = (i + 1) % n
        tris.append((i, j, n + j))
        tris.append((i, n + j, n + i))
    for i in range(1, n - 1):
        tris.append((0, i + 1, i))
        tris.append((n, n + i, n + i + 1))
    _cyl_cache[n] = (verts, np.array(tris, dtype=int))
    return _cyl_cache[n]


def ball_mesh(n):
    """Unit sphere, n segments around, n//2 rings. Returns (verts, tris)."""
    if n in _ball_cache:
        return _ball_cache[n]
    rings = max(3, n // 2)
    verts = [(0.0, 1.0, 0.0)]
    for k in range(1, rings):
        phi = math.pi * k / rings
        for i in range(n):
            th = 2 * math.pi * i / n
            verts.append((math.sin(phi) * math.cos(th), math.cos(phi), math.sin(phi) * math.sin(th)))
    verts.append((0.0, -1.0, 0.0))
    verts = np.array(verts)
    tris = []
    for i in range(n):
        tris.append((0, 1 + (i + 1) % n, 1 + i))
    for k in range(rings - 2):
        a0 = 1 + k * n
        b0 = 1 + (k + 1) * n
        for i in range(n):
            j = (i + 1) % n
            tris.append((a0 + i, a0 + j, b0 + j))
            tris.append((a0 + i, b0 + j, b0 + i))
    last = len(verts) - 1
    base = 1 + (rings - 2) * n
    for i in range(n):
        tris.append((base + i, base + (i + 1) % n, last))
    _ball_cache[n] = (verts, np.array(tris, dtype=int))
    return _ball_cache[n]


def segments(radius):
    return int(max(8, min(24, round(2 * math.pi * radius / 0.3))))


# --------------------------------------------------------------------------
# Triangle soup
# --------------------------------------------------------------------------


def soup(parts, keep=None, extra=None):
    """World-space triangles, the owning part index of each (negative for the
    extra ground quads), and the colours of those extra quads by owner id."""
    chunks, owners = [], []
    extra_colours = {}
    for i, p in enumerate(parts):
        if p.transparency >= 0.9:
            continue
        if keep is not None and not keep(p):
            continue
        half = p.size / 2.0
        if p.cls == "WedgePart":
            local, tris = WEDGE * half, WEDGE_TRIS
        elif p.cls == "Part" and p.shape == "Cylinder":
            r = min(half[1], half[2])
            verts, tris = cylinder_mesh(segments(r))
            local = verts * np.array([half[0], r, r])
        elif p.cls == "Part" and p.shape == "Ball":
            r = float(half.min())
            verts, tris = ball_mesh(segments(r))
            local = verts * r
        else:
            local, tris = BOX * half, BOX_TRIS
        world = local @ p.R.T + p.pos
        chunks.append(world[tris])
        owners.append(np.full(len(tris), i, dtype=np.int32))
    for k, (quad, colour) in enumerate(extra or []):
        quad = np.asarray(quad, float)
        tri = np.array([[quad[0], quad[1], quad[2]], [quad[0], quad[2], quad[3]]])
        chunks.append(tri)
        owners.append(np.full(2, -1 - k, dtype=np.int32))
        extra_colours[-1 - k] = np.asarray(colour, float)
    if not chunks:
        return np.zeros((0, 3, 3)), np.zeros(0, dtype=np.int32), extra_colours
    return np.concatenate(chunks), np.concatenate(owners), extra_colours


# --------------------------------------------------------------------------
# Material patterns, evaluated at points in a part's own coordinates
# --------------------------------------------------------------------------


def hash2(a, b):
    """Cheap deterministic noise in [0, 1) from two integer grids."""
    h = (a * 374761393 + b * 668265263) & 0x7FFFFFFF
    h = (h ^ (h >> 13)) * 1274126177 & 0x7FFFFFFF
    return ((h ^ (h >> 16)) & 0xFFFF) / 65536.0


def _i(x):
    return np.floor(x).astype(np.int64)


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
        grain = 0.94 + 0.06 * hash2(_i(u * 0.7), _i(v / 1.6))
        out = grain * np.where(seam, 0.78, 1.0) * np.where(ends, 0.86, 1.0)
    elif material == "Wood":
        out = 0.95 + 0.05 * hash2(_i(u * 0.5), _i(v * 3))
    elif material in ("RoofShingles", "ClayRoofTiles"):
        row = np.floor(v / 1.4)
        seam = ((v / 1.4) % 1.0) < 0.16
        stagger = (row % 2) * 1.1
        col = np.abs((((u + stagger) / 2.2) % 1.0) - 0.5) > 0.46
        tone = 0.9 + 0.1 * hash2(_i((u + stagger) / 2.2), row.astype(np.int64))
        out = tone * np.where(seam, 0.7, 1.0) * np.where(col, 0.84, 1.0)
    elif material == "Cobblestone":
        row = np.floor(v / 1.1)
        stagger = (row % 2) * 0.8
        tone = 0.82 + 0.26 * hash2(_i((u + stagger) / 1.6), row.astype(np.int64))
        mortar = (((u + stagger) / 1.6) % 1.0 < 0.13) | ((v / 1.1) % 1.0 < 0.16)
        out = tone * np.where(mortar, 0.62, 1.0)
    elif material == "Brick":
        row = np.floor(v / 0.9)
        stagger = (row % 2) * 1.5
        tone = 0.88 + 0.16 * hash2(_i((u + stagger) / 3.0), row.astype(np.int64))
        mortar = (((u + stagger) / 3.0) % 1.0 < 0.08) | ((v / 0.9) % 1.0 < 0.18)
        out = tone * np.where(mortar, 0.68, 1.0)
    elif material == "CeramicTiles":
        tone = 0.9 + 0.1 * hash2(_i(u / 1.5), _i(v / 1.5))
        grout = ((u / 1.5) % 1.0 < 0.06) | ((v / 1.5) % 1.0 < 0.06)
        out = tone * np.where(grout, 0.7, 1.0)
    elif material in ("Fabric", "Carpet"):
        s = 5.0 if material == "Fabric" else 3.0
        out = 0.92 + 0.08 * hash2(_i(u * s), _i(v * s))
    elif material == "Leather":
        out = 0.88 + 0.12 * hash2(_i(u * 1.2), _i(v * 1.2)) * hash2(_i(u * 3.1), _i(v * 3.1))
    elif material in ("Metal", "DiamondPlate", "Foil"):
        out = 0.94 + 0.06 * hash2(_i(u * 2), _i(v * 2))
    elif material == "CorrodedMetal":
        blotch = hash2(_i(u * 0.9), _i(v * 0.9))
        out = np.where(blotch > 0.6, 0.78, 1.0) * (0.92 + 0.08 * hash2(_i(u * 4), _i(v * 4)))
    elif material == "Marble":
        vein = np.abs(np.sin(u * 1.7 + v * 0.9 + 2.0 * hash2(_i(u * 0.5), _i(v * 0.5))))
        out = np.where(vein < 0.08, 0.75, 1.0)
    elif material in ("Plaster", "Concrete", "Limestone", "Sandstone", "Cardboard"):
        out = 0.94 + 0.06 * hash2(_i(u * 0.8), _i(v * 0.8))
    elif material in ("Slate", "Granite", "Basalt"):
        out = 0.92 + 0.08 * hash2(_i(u), _i(v))
    elif material in ("Rock", "Pebble"):
        out = 0.88 + 0.12 * hash2(_i(u * 0.7), _i(v * 0.7))
    return out


EMISSIVE = {"Neon"}

# --------------------------------------------------------------------------
# Rasteriser
# --------------------------------------------------------------------------


def camera(eye, target):
    eye, target = np.asarray(eye, float), np.asarray(target, float)
    f = target - eye
    f /= np.linalg.norm(f)
    r = np.cross(f, np.array([0, 1, 0], float))
    if np.linalg.norm(r) < 1e-6:
        r = np.array([1.0, 0, 0])
    r /= np.linalg.norm(r)
    u = np.cross(r, f)
    return eye, np.stack([r, u, -f])


def clip_near(tris, owner, eye, M, near):
    """Clip triangles against the plane `near` in front of the eye."""
    depth = -((tris - eye) @ M.T)[..., 2]
    inside = depth > near
    count = inside.sum(axis=1)
    keep = count == 3
    out_t, out_o = [tris[keep]], [owner[keep]]

    def lerp(a, b, da, db):
        t = (da - near) / (da - db)
        return a + (b - a) * t[:, None]

    for k in range(3):
        m = (count == 1) & inside[:, k]
        if m.any():
            a, b, c = tris[m, k], tris[m, (k + 1) % 3], tris[m, (k + 2) % 3]
            da, db, dc = depth[m, k], depth[m, (k + 1) % 3], depth[m, (k + 2) % 3]
            out_t.append(np.stack([a, lerp(a, b, da, db), lerp(a, c, da, dc)], axis=1))
            out_o.append(owner[m])
        m = (count == 2) & ~inside[:, k]
        if m.any():
            c = tris[m, k]
            a, b = tris[m, (k + 1) % 3], tris[m, (k + 2) % 3]
            dc, da, db = depth[m, k], depth[m, (k + 1) % 3], depth[m, (k + 2) % 3]
            bc, ac = lerp(b, c, db, dc), lerp(a, c, da, dc)
            out_t.append(np.stack([a, b, bc], axis=1))
            out_t.append(np.stack([a, bc, ac], axis=1))
            out_o.append(owner[m])
            out_o.append(owner[m])
    return np.concatenate(out_t), np.concatenate(out_o)


def render(parts, tris, owner, eye, target, size=(1500, 950), fov=40.0,
           sky=(0.64, 0.65, 0.63), fog_near=170.0, fog_far=560.0,
           key=(-0.5, 0.75, 0.45), fill=(0.7, 0.3, -0.4), ambient=0.30,
           edge_strength=0.22, extra_colours=None, near=0.4, small_px=10):
    W, H = size
    eye, M = camera(eye, target)

    if len(tris) == 0:
        return Image.new("RGB", size, tuple(int(c * 255) for c in sky))

    pos = np.array([p.pos for p in parts]) if parts else np.zeros((0, 3))
    colour = np.array([p.colour for p in parts]) if parts else np.zeros((0, 3))
    emissive = np.array([p.material in EMISSIVE for p in parts], dtype=bool)

    # Outward normals, from each part's centre, and back faces dropped: every
    # part is a closed convex solid, so a face turned away is always hidden.
    e1, e2 = tris[:, 1] - tris[:, 0], tris[:, 2] - tris[:, 0]
    n = np.cross(e1, e2)
    ln = np.linalg.norm(n, axis=1, keepdims=True)
    ln[ln == 0] = 1
    n /= ln
    centre = tris.mean(axis=1)
    is_part = owner >= 0
    ref = np.where(is_part[:, None], pos[np.clip(owner, 0, None)] if len(pos) else centre, centre - n)
    flip = ((centre - ref) * n).sum(axis=1) < 0
    n[flip] *= -1
    front = ((eye - centre) * n).sum(axis=1) > 0
    front |= ~is_part                       # ground quads are one-sided anyway
    tris, owner, n = tris[front], owner[front], n[front]

    # Shade per triangle before clipping, and carry it through.
    K = np.array(key, float); K /= np.linalg.norm(K)
    F = np.array(fill, float); F /= np.linalg.norm(F)
    lam = ambient + 0.62 * np.abs(n @ K) + 0.18 * np.abs(n @ F)
    lam += 0.10 * np.clip(n[:, 1], 0, 1) - 0.08 * np.clip(-n[:, 1], 0, 1)
    shade = np.clip(lam, 0, 1)

    idx = np.arange(len(tris))
    tris, tri_id = clip_near(tris, idx, eye, M, near)
    owner, shade = owner[tri_id], shade[tri_id]

    cam = ((tris.reshape(-1, 3) - eye) @ M.T).reshape(-1, 3, 3)
    depth = -cam[:, :, 2]
    focal = (H / 2) / math.tan(math.radians(fov) / 2)
    sx = W / 2 + cam[:, :, 0] * focal / depth
    sy = H / 2 - cam[:, :, 1] * focal / depth

    xmin, xmax = sx.min(axis=1), sx.max(axis=1)
    ymin, ymax = sy.min(axis=1), sy.max(axis=1)
    onscreen = (xmax >= 0) & (xmin < W) & (ymax >= 0) & (ymin < H)
    area = (sx[:, 1] - sx[:, 0]) * (sy[:, 2] - sy[:, 0]) - (sx[:, 2] - sx[:, 0]) * (sy[:, 1] - sy[:, 0])
    onscreen &= np.abs(area) > 1e-9

    extra_colours = extra_colours or {}
    oc = np.clip(owner, 0, None)
    neg = owner < 0
    if len(colour):
        base = colour[oc].astype(float)
        glow_tri = emissive[oc] & ~neg
    else:
        base = np.zeros((len(tris), 3))
        glow_tri = np.zeros(len(tris), dtype=bool)
    for k in np.unique(owner[neg]):
        base[owner == k] = extra_colours.get(int(k), np.array([0.19, 0.15, 0.12]))
    base = np.where(glow_tri[:, None], base, base * shade[:, None])

    img = np.zeros((H, W, 3), dtype=np.float32)
    img[:] = sky
    zbuf = np.full((H, W), np.inf, dtype=np.float64)
    ids = np.full((H, W), -(10 ** 6), dtype=np.int64)
    skyc = np.array(sky, float)

    bw, bh = xmax - xmin, ymax - ymin
    small = onscreen & (bw <= small_px - 1) & (bh <= small_px - 1)
    big = onscreen & ~small

    # ---- big triangles, one at a time, with material patterns
    for i in np.nonzero(big)[0]:
        ix0, ix1 = max(0, int(xmin[i])), min(W, int(xmax[i]) + 2)
        iy0, iy1 = max(0, int(ymin[i])), min(H, int(ymax[i]) + 2)
        if ix1 <= ix0 or iy1 <= iy0:
            continue
        ax, ay = sx[i, 0], sy[i, 0]
        bx, by = sx[i, 1], sy[i, 1]
        cx, cy = sx[i, 2], sy[i, 2]
        a2 = (bx - ax) * (cy - ay) - (cx - ax) * (by - ay)
        yy, xx = np.mgrid[iy0:iy1, ix0:ix1]
        px, py = xx + 0.5, yy + 0.5
        w0 = ((bx - ax) * (py - ay) - (px - ax) * (by - ay)) / a2
        w1 = ((px - ax) * (cy - ay) - (cx - ax) * (py - ay)) / a2
        wa = 1 - w0 - w1
        inside = (w0 >= 0) & (w1 >= 0) & (wa >= 0)
        if not inside.any():
            continue
        za, zb, zc = depth[i]
        z = 1.0 / (wa / za + w1 / zb + w0 / zc)
        sub = zbuf[iy0:iy1, ix0:ix1]
        win = inside & (z < sub)
        if not win.any():
            continue
        o = owner[i]
        col = base[i]
        if o >= 0 and not glow_tri[i]:
            p = parts[o]
            A, B, C = tris[i]
            zw = z[win][:, None]
            wp = (wa[win][:, None] * (A / za) + w1[win][:, None] * (B / zb) + w0[win][:, None] * (C / zc)) * zw
            local = (wp - p.pos) @ p.R
            mult = pattern(p.material, local, p.size)
            c = np.clip(col[None, :] * mult[:, None], 0, 1)
        else:
            c = np.repeat(np.clip(col, 0, 1)[None, :], int(win.sum()), axis=0)
        if not glow_tri[i]:
            t = np.clip((z[win] - fog_near) / (fog_far - fog_near), 0, 1)[:, None]
            c = c * (1 - t) + skyc[None, :] * t
        img[iy0:iy1, ix0:ix1][win] = c
        sub[win] = z[win]
        ids[iy0:iy1, ix0:ix1][win] = o

    # ---- small triangles, batched, flat colour
    small_idx = np.nonzero(small)[0]
    S = small_px
    oy, ox = np.mgrid[0:S, 0:S]
    ox, oy = ox.ravel(), oy.ravel()
    flat_z = zbuf.ravel()
    flat_img = img.reshape(-1, 3)
    flat_ids = ids.ravel()
    for start in range(0, len(small_idx), 12000):
        ti = small_idx[start:start + 12000]
        x0 = np.floor(xmin[ti]).astype(np.int64)
        y0 = np.floor(ymin[ti]).astype(np.int64)
        PX = x0[:, None] + ox[None, :]
        PY = y0[:, None] + oy[None, :]
        px, py = PX + 0.5, PY + 0.5
        ax, ay = sx[ti, 0][:, None], sy[ti, 0][:, None]
        bx, by = sx[ti, 1][:, None], sy[ti, 1][:, None]
        cx, cy = sx[ti, 2][:, None], sy[ti, 2][:, None]
        a2 = (bx - ax) * (cy - ay) - (cx - ax) * (by - ay)
        w0 = ((bx - ax) * (py - ay) - (px - ax) * (by - ay)) / a2
        w1 = ((px - ax) * (cy - ay) - (cx - ax) * (py - ay)) / a2
        wa = 1 - w0 - w1
        ok = (w0 >= 0) & (w1 >= 0) & (wa >= 0) & (PX >= 0) & (PX < W) & (PY >= 0) & (PY < H)
        za, zb, zc = depth[ti, 0][:, None], depth[ti, 1][:, None], depth[ti, 2][:, None]
        with np.errstate(divide="ignore", invalid="ignore"):
            z = 1.0 / (wa / za + w1 / zb + w0 / zc)
        rows, cols = np.nonzero(ok)
        if len(rows) == 0:
            continue
        pix = PY[rows, cols] * W + PX[rows, cols]
        zz = z[rows, cols]
        better = zz < flat_z[pix]
        pix, zz, tri = pix[better], zz[better], ti[rows[better]]
        if len(pix) == 0:
            continue
        order = np.lexsort((zz, pix))
        pix, zz, tri = pix[order], zz[order], tri[order]
        first = np.ones(len(pix), dtype=bool)
        first[1:] = pix[1:] != pix[:-1]
        pix, zz, tri = pix[first], zz[first], tri[first]
        c = np.clip(base[tri], 0, 1)
        t = np.clip((zz - fog_near) / (fog_far - fog_near), 0, 1)[:, None]
        glow = glow_tri[tri]
        c = np.where(glow[:, None], c, c * (1 - t) + skyc[None, :] * t)
        flat_img[pix] = c
        flat_z[pix] = zz
        flat_ids[pix] = owner[tri]

    # Edge lines: wherever the part under a pixel differs from its neighbour,
    # or the depth jumps, darken — what a lit edge does in the engine.
    edge = np.zeros((H, W), dtype=bool)
    with np.errstate(invalid="ignore"):
        for dy, dx in ((0, 1), (1, 0)):
            a = ids[dy:, dx:]
            b = ids[: H - dy, : W - dx]
            za_ = zbuf[dy:, dx:]
            zb_ = zbuf[: H - dy, : W - dx]
            diff = (a != b) | (np.abs(za_ - zb_) > np.maximum(1.2, 0.02 * np.minimum(za_, zb_)))
            diff &= (a != -(10 ** 6)) | (b != -(10 ** 6))
            edge[dy:, dx:] |= diff
            edge[: H - dy, : W - dx] |= diff
        far = np.clip((zbuf - fog_near) / (fog_far - fog_near), 0, 1)
    far = np.where(np.isfinite(zbuf), far, 1.0)
    strength = edge_strength * (1 - far)
    img[edge] *= (1 - strength[edge])[:, None]

    return Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8))


def extent(parts, keep=None):
    pts = []
    for p in parts:
        if p.transparency >= 0.9 or (keep and not keep(p)):
            continue
        lo, hi = p.aabb()
        pts.append(lo)
        pts.append(hi)
    allp = np.array(pts)
    return allp.min(axis=0), allp.max(axis=0)
