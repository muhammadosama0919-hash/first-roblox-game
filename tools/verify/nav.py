#!/usr/bin/env python3
"""
Prove the manor is walkable.

Voxelises every collidable part at one-stud resolution, then flood-fills from
the foot of the front steps with a character-sized probe (3 wide, 6 tall) that
may step up or down two studs and may drop any distance. Every room, both
stairs, the attic and every hiding place must be reached.

This is the check the renders cannot do: a wall a half-stud too long across a
doorway looks fine from any angle and is a dead end in play.
"""

import pathlib
import sys
import numpy as np
from collections import deque
from scipy.ndimage import maximum_filter
from render import load

HERE = pathlib.Path(__file__).parent
parts = load(HERE / "parts.tsv")

X0, X1 = -48, 48
Y0, Y1 = -10, 68
Z0, Z1 = -50, 50
NX, NY, NZ = X1 - X0, Y1 - Y0, Z1 - Z0

# --------------------------------------------------------------------------
# Voxelise
# --------------------------------------------------------------------------

solid = np.zeros((NX, NY, NZ), dtype=bool)
collidable = 0
for p in parts:
    if not p.collide:
        continue
    collidable += 1
    half = p.size / 2.0
    corners = np.array([[sx, sy, sz] for sx in (-1, 1) for sy in (-1, 1) for sz in (-1, 1)]) * half
    world = corners @ p.R.T + p.pos
    lo, hi = world.min(axis=0), world.max(axis=0)
    ix = np.arange(max(X0, int(np.floor(lo[0]))), min(X1, int(np.ceil(hi[0]))))
    iy = np.arange(max(Y0, int(np.floor(lo[1]))), min(Y1, int(np.ceil(hi[1]))))
    iz = np.arange(max(Z0, int(np.floor(lo[2]))), min(Z1, int(np.ceil(hi[2]))))
    if len(ix) == 0 or len(iy) == 0 or len(iz) == 0:
        continue
    gx, gy, gz = np.meshgrid(ix + 0.5, iy + 0.5, iz + 0.5, indexing="ij")
    pts = np.stack([gx, gy, gz], axis=-1).reshape(-1, 3)
    local = (pts - p.pos) @ p.R
    tol = 0.05
    inside = np.all(np.abs(local) <= half + tol, axis=1)
    if p.cls == "WedgePart":
        inside &= local[:, 1] <= (half[1] / half[2]) * local[:, 2] + tol
    solid[np.ix_(ix - X0, iy - Y0, iz - Z0)] |= inside.reshape(gx.shape)

print(f"{collidable} collidable parts voxelised, {int(solid.sum())} solid cells")

# --------------------------------------------------------------------------
# Standable cells: 3x6x3 clear above, something solid in the 3x1x3 below
# --------------------------------------------------------------------------

PROBE_H, PROBE_R, STEP_UP = 6, 1, 2

body = maximum_filter(solid, size=(2 * PROBE_R + 1, 1, 2 * PROBE_R + 1))
occupied_above = np.zeros_like(solid)
for dy in range(PROBE_H):
    shifted = np.zeros_like(solid)
    shifted[:, : NY - dy, :] = body[:, dy:, :]
    occupied_above |= shifted
floor_below = np.zeros_like(solid)
floor_below[:, 1:, :] = body[:, :-1, :]

standable = (~occupied_above) & floor_below
standable[:PROBE_R, :, :] = standable[-PROBE_R:, :, :] = False
standable[:, :, :PROBE_R] = standable[:, :, -PROBE_R:] = False
print(f"{int(standable.sum())} standable cells")


def idx(c):
    return (c[0] - X0, c[1] - Y0, c[2] - Z0)


def nearest_standable(px, py, pz, radius=2, box=None):
    """Closest standable cell to a point; `box` limits the search to an XZ extent."""
    best = None
    cx, cy, cz = int(round(px)), int(round(py)), int(round(pz))
    for dx in range(-radius, radius + 1):
        for dz in range(-radius, radius + 1):
            for dy in range(-radius, radius + 1):
                x, y, z = cx + dx, cy + dy, cz + dz
                if not (X0 <= x < X1 and Y0 <= y < Y1 and Z0 <= z < Z1):
                    continue
                if box is not None and not (box[0] <= x + 0.5 <= box[1] and box[2] <= z + 0.5 <= box[3]):
                    continue
                if standable[idx((x, y, z))]:
                    d = dx * dx + 4 * dy * dy + dz * dz
                    if best is None or d < best[0]:
                        best = (d, (x, y, z))
    return None if best is None else best[1]


# --------------------------------------------------------------------------
# Flood fill, remembering how each cell was reached
# --------------------------------------------------------------------------


def flood(seed):
    reached = np.zeros_like(standable)
    parent = {}
    q = deque([seed])
    reached[idx(seed)] = True
    while q:
        x, y, z = q.popleft()
        for dx, dz in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nx, nz = x + dx, z + dz
            if not (X0 + PROBE_R <= nx < X1 - PROBE_R and Z0 + PROBE_R <= nz < Z1 - PROBE_R):
                continue
            landed = False
            for ny in range(y + STEP_UP, y - STEP_UP - 1, -1):
                if Y0 <= ny < Y1 and standable[idx((nx, ny, nz))]:
                    if not reached[idx((nx, ny, nz))]:
                        reached[idx((nx, ny, nz))] = True
                        parent[(nx, ny, nz)] = (x, y, z)
                        q.append((nx, ny, nz))
                    landed = True
                    break
            if not landed:
                # Walk off the edge and fall. The scan starts one cell under
                # the feet, not below the step range: skipping those cells let
                # the probe drop through a floor it could not stand on only
                # because the ceiling above was low.
                ny = y - 1
                while ny >= Y0:
                    if standable[idx((nx, ny, nz))]:
                        if not reached[idx((nx, ny, nz))]:
                            reached[idx((nx, ny, nz))] = True
                            parent[(nx, ny, nz)] = (x, y, z)
                            q.append((nx, ny, nz))
                        break
                    if body[idx((nx, ny, nz))]:
                        break
                    ny -= 1
    return reached, parent


def trace(parent, cell, seed):
    path = [cell]
    while cell != seed and cell in parent:
        cell = parent[cell]
        path.append(cell)
    return path[::-1]


seed = nearest_standable(20, -7, 46, radius=4)
if seed is None:
    print("!! no standable cell near the front steps")
    sys.exit(1)
reached, parent = flood(seed)
print(f"seed {seed}, {int(reached.sum())} cells reached")

# --------------------------------------------------------------------------
# Targets
# --------------------------------------------------------------------------

L1, L2, L3 = 0, 14, 28
targets = [
    ("front steps foot", (20, -7, 46), None),
    ("porch, right end", (36, L1, 27), None),
    ("porch, left end by bay", (-9, L1, 27), None),
    ("porch return", (37, L1, 12), None),
    ("hall, ground", (0, L1, 0), None),
    ("hall, back by rear door", (0, L1, -19), None),
    ("parlour", (-22, L1, 8), None),
    ("bay, ground floor", (-21, L1, 27), None),
    ("kitchen", (-20, L1, -12), None),
    ("dining", (22, L1, 4), None),
    ("study", (22, L1, -8), None),
    ("back stoop", (0, L1, -28), None),
    ("stair 1, mid flight", (-8, 7, -4), None),
    ("landing, first floor", (0, L2, -20), None),
    ("landing, between stairs", (0, L2, -4), None),
    ("bedroom NW", (-16, L2, -18), None),
    ("bedroom SW", (-16, L2, 18), None),
    ("bedroom NE", (16, L2, -18), None),
    ("bedroom SE", (16, L2, 18), None),
    ("bay, first floor", (-21, L2, 27), None),
    ("stair 2, mid flight", (8, 21, -4), None),
    ("attic, centre", (0, L3, -10), None),
    ("attic, left end", (-24, L3, 0), None),
    ("attic, right end", (24, L3, 0), None),
    ("attic, under front dormer", (17, L3, 18), None),
    ("bay, attic", (-21, L3, 27), None),
]

# Places a player should NOT be able to get to on foot.
forbidden = [
    ("porch roof", (15, 15, 27)),
    ("main roof, front slope", (0, 45, 14)),
    ("bay roof", (-21, 38, 30)),
]

# Hiding places: aim at the floor inside the tagged volume, and insist the
# cell found actually lies within the volume's footprint.
for p in parts:
    if "HidingSpot" not in p.tags:
        continue
    half = p.size / 2
    if p.name == "HidingVolume":
        # Extents in the volume's own frame; it is axis-aligned or rotated 90.
        corners = np.array([[sx, 0, sz] for sx in (-1, 1) for sz in (-1, 1)]) * half
        world = corners @ p.R.T + p.pos
        box = (world[:, 0].min(), world[:, 0].max(), world[:, 2].min(), world[:, 2].max())
        floor_y = p.pos[1] - half[1]
        targets.append((f"hiding: cupboard @ {np.round(p.pos[[0, 2]]).astype(int).tolist()}",
                        (p.pos[0], floor_y, p.pos[2]), box))
    else:
        # A crate: you hide beside it, so aim one stud off its side, on the floor.
        floor_y = p.pos[1] - half[1]
        side = p.pos[0] + (half[0] + 2) * (1 if p.pos[0] < 0 else -1)
        targets.append((f"hiding: beside crate @ {np.round(p.pos[[0, 2]]).astype(int).tolist()}",
                        (side, floor_y, p.pos[2]), None))

failures = 0
for name, hint, box in targets:
    cell = nearest_standable(*hint, radius=3, box=box)
    if cell is None:
        print(f"  MISSING  {name:46} nothing standable near {tuple(round(float(v), 1) for v in hint)}")
        failures += 1
        continue
    ok = reached[idx(cell)]
    print(f"  {'ok     ' if ok else 'UNREACH'}  {name:46} at {cell}")
    if not ok:
        failures += 1

print()
for name, hint in forbidden:
    cell = nearest_standable(*hint, radius=3)
    if cell is None:
        print(f"  ok       not standable:   {name}")
        continue
    if reached[idx(cell)]:
        failures += 1
        path = trace(parent, cell, seed)
        print(f"  CLIMBED  {name:46} at {cell}")
        # Show the whole route, compressed to the moves that change height:
        # the leak is wherever it first leaves the floor it should be on.
        last_y = None
        for c in path:
            if c[1] != last_y:
                print(f"             {c}")
                last_y = c[1]
    else:
        print(f"  ok       unreachable:    {name}")

print()
print("standable cells reached per floor band:")
for label, lo, hi in (("ground", -1, 6), ("first", 13, 20), ("attic", 27, 34)):
    print(f"  {label:8} {int(reached[:, lo - Y0:hi - Y0, :].sum())}")

print()
print("RESULT:", "ALL CHECKS PASS" if failures == 0 else f"{failures} FAILURES")
sys.exit(0 if failures == 0 else 1)
