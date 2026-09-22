#!/usr/bin/env python3
"""
Prove a house is walkable.

    nav.py Manor                 doors open: every target reachable?
    nav.py Manor --exits         also: with every door shut, is the only way
                                 out through the doors the house means?
                                 Always run for a house marked `sealed` in
                                 houses.py, which the villa is.

Voxelises every collidable part at one-stud resolution, adds a ground plane at
the pivot (the terrain the house will stand on), then flood-fills from outside
the front door with a character-sized probe (3 wide, 6 tall) that may step up
or down two studs and drop any distance. Every room, stair, landing and
tagged hiding place must be reached; roofs must not be.

Doors are left out of the solid geometry, because every one of them opens.
With --exits they are put back in, closed, and the fill is run again from
inside: whatever it can still reach outside is a way out the house did not
mean to have.

This is the check the renders cannot do: a wall a half-stud too long across a
doorway looks fine from any angle and is a dead end in play.
"""

import pathlib
import sys
from collections import deque

import numpy as np
from scipy.ndimage import maximum_filter

import capture
from houses import HOUSES

HERE = pathlib.Path(__file__).parent

PROBE_H, PROBE_R, STEP_UP = 6, 1, 2


class Grid:
    def __init__(self, parts, bounds, G, doors_closed):
        (self.X0, self.X1) = bounds["x"]
        (Y0, Y1) = bounds["y"]
        (self.Z0, self.Z1) = bounds["z"]
        self.Y0, self.Y1 = Y0 + G, Y1 + G
        self.G = G
        nx, ny, nz = self.X1 - self.X0, self.Y1 - self.Y0, self.Z1 - self.Z0
        solid = np.zeros((nx, ny, nz), dtype=bool)
        count = 0
        for p in parts:
            if not p.collide:
                continue
            if p.door is not None and not doors_closed:
                continue
            count += 1
            half = p.size / 2.0
            lo, hi = p.aabb()
            ix = np.arange(max(self.X0, int(np.floor(lo[0]))), min(self.X1, int(np.ceil(hi[0]))))
            iy = np.arange(max(self.Y0, int(np.floor(lo[1]))), min(self.Y1, int(np.ceil(hi[1]))))
            iz = np.arange(max(self.Z0, int(np.floor(lo[2]))), min(self.Z1, int(np.ceil(hi[2]))))
            if len(ix) == 0 or len(iy) == 0 or len(iz) == 0:
                continue
            gx, gy, gz = np.meshgrid(ix + 0.5, iy + 0.5, iz + 0.5, indexing="ij")
            pts = np.stack([gx, gy, gz], axis=-1).reshape(-1, 3)
            local = (pts - p.pos) @ p.R
            tol = 0.05
            if p.cls == "Part" and p.shape == "Cylinder":
                r = min(half[1], half[2])
                inside = (np.abs(local[:, 0]) <= half[0] + tol) & (np.hypot(local[:, 1], local[:, 2]) <= r + tol)
            elif p.cls == "Part" and p.shape == "Ball":
                inside = np.linalg.norm(local, axis=1) <= half.min() + tol
            else:
                inside = np.all(np.abs(local) <= half + tol, axis=1)
                if p.cls == "WedgePart":
                    inside &= local[:, 1] <= (half[1] / half[2]) * local[:, 2] + tol
            solid[np.ix_(ix - self.X0, iy - self.Y0, iz - self.Z0)] |= inside.reshape(gx.shape)
        # The terrain: a floor at the pivot's height everywhere.
        ground = -self.Y0 - 1
        if 0 <= ground < ny:
            solid[:, ground, :] = True
        self.solid = solid
        self.count = count

        body = maximum_filter(solid, size=(2 * PROBE_R + 1, 1, 2 * PROBE_R + 1))
        above = np.zeros_like(solid)
        for dy in range(PROBE_H):
            shifted = np.zeros_like(solid)
            shifted[:, : ny - dy, :] = body[:, dy:, :]
            above |= shifted
        below = np.zeros_like(solid)
        below[:, 1:, :] = body[:, :-1, :]
        standable = (~above) & below
        standable[:PROBE_R, :, :] = standable[-PROBE_R:, :, :] = False
        standable[:, :, :PROBE_R] = standable[:, :, -PROBE_R:] = False
        self.body = body
        self.standable = standable

    def idx(self, c):
        return (c[0] - self.X0, c[1] - self.Y0, c[2] - self.Z0)

    def inside(self, x, y, z):
        return self.X0 <= x < self.X1 and self.Y0 <= y < self.Y1 and self.Z0 <= z < self.Z1

    def nearest(self, px, py, pz, radius=3, box=None):
        """Closest standable cell to a world point; `box` limits the search to an XZ extent."""
        best = None
        cx, cy, cz = int(np.floor(px)), int(round(py)), int(np.floor(pz))
        for dx in range(-radius, radius + 1):
            for dz in range(-radius, radius + 1):
                for dy in range(-radius, radius + 1):
                    x, y, z = cx + dx, cy + dy, cz + dz
                    if not self.inside(x, y, z):
                        continue
                    if box is not None and not (box[0] <= x + 0.5 <= box[1] and box[2] <= z + 0.5 <= box[3]):
                        continue
                    if self.standable[self.idx((x, y, z))]:
                        d = dx * dx + 4 * dy * dy + dz * dz
                        if best is None or d < best[0]:
                            best = (d, (x, y, z))
        return None if best is None else best[1]

    def flood(self, seed):
        st = self.standable
        reached = np.zeros_like(st)
        parent = {}
        q = deque([seed])
        reached[self.idx(seed)] = True
        while q:
            x, y, z = q.popleft()
            for dx, dz in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, nz = x + dx, z + dz
                if not (self.X0 + PROBE_R <= nx < self.X1 - PROBE_R and self.Z0 + PROBE_R <= nz < self.Z1 - PROBE_R):
                    continue
                landed = False
                for ny in range(y + STEP_UP, y - STEP_UP - 1, -1):
                    if self.Y0 <= ny < self.Y1 and st[self.idx((nx, ny, nz))]:
                        if not reached[self.idx((nx, ny, nz))]:
                            reached[self.idx((nx, ny, nz))] = True
                            parent[(nx, ny, nz)] = (x, y, z)
                            q.append((nx, ny, nz))
                        landed = True
                        break
                if not landed:
                    ny = y - 1
                    while ny >= self.Y0:
                        if st[self.idx((nx, ny, nz))]:
                            if not reached[self.idx((nx, ny, nz))]:
                                reached[self.idx((nx, ny, nz))] = True
                                parent[(nx, ny, nz)] = (x, y, z)
                                q.append((nx, ny, nz))
                            break
                        if self.body[self.idx((nx, ny, nz))]:
                            break
                        ny -= 1
        return reached, parent


def trace(parent, cell, seed):
    path = [cell]
    while cell != seed and cell in parent:
        cell = parent[cell]
        path.append(cell)
    return path[::-1]


def main():
    name = sys.argv[1] if len(sys.argv) > 1 else "Manor"
    cfg = HOUSES[name]
    check_exits = cfg.get("sealed", False) or "--exits" in sys.argv
    G = cfg["G"]
    cap = capture.load(HERE / "work" / f"{name}.tsv")

    grid = Grid(cap.parts, cfg["bounds"], G, doors_closed=False)
    print(f"{grid.count} collidable parts voxelised (doors open), {int(grid.standable.sum())} standable cells")

    def world(p):
        return (p[0], p[1] + G, p[2])

    seed = grid.nearest(*world(cfg["seed"]), radius=4)
    if seed is None:
        print("!! nothing standable at the seed")
        sys.exit(1)
    reached, parent = grid.flood(seed)
    print(f"seed {seed}, {int(reached.sum())} cells reached")

    failures = 0
    targets = [(n, world(p), None) for n, p in cfg["targets"]]
    for p in cap.parts:
        if "HidingSpot" not in p.tags:
            continue
        half = p.size / 2
        corners = np.array([[sx, 0, sz] for sx in (-1, 1) for sz in (-1, 1)]) * half
        w = corners @ p.R.T + p.pos
        box = (w[:, 0].min() - 0.5, w[:, 0].max() + 0.5, w[:, 2].min() - 0.5, w[:, 2].max() + 0.5)
        floor_y = p.pos[1] - half[1]
        kind = p.attrs.get("Kind", "?")
        targets.append((f"hiding: {kind} {p.name} @ {np.round(p.pos[[0, 2]]).astype(int).tolist()}",
                        (p.pos[0], floor_y, p.pos[2]), (box, kind)))

    for tname, hint, extra in targets:
        box, kind = extra if extra else (None, None)
        # A player lies down under a bed or crouches under a table: the probe,
        # which is a standing player, is only asked to reach the edge of it.
        if kind in ("UnderBed", "UnderTable"):
            cell = grid.nearest(*hint, radius=max(4, int(max(box[1] - box[0], box[3] - box[2]) / 2) + 2))
        else:
            cell = grid.nearest(*hint, radius=3, box=box)
        if cell is None:
            print(f"  MISSING  {tname:56} nothing standable near {tuple(round(float(v), 1) for v in hint)}")
            failures += 1
            continue
        ok = reached[grid.idx(cell)]
        print(f"  {'ok     ' if ok else 'UNREACH'}  {tname:56} at {cell}")
        if not ok:
            failures += 1

    print()
    for fname, p in cfg.get("forbidden", []):
        cell = grid.nearest(*world(p), radius=3)
        if cell is None:
            print(f"  ok       not standable:  {fname}")
            continue
        if reached[grid.idx(cell)]:
            failures += 1
            print(f"  CLIMBED  {fname:56} at {cell}")
            last_y = None
            for c in trace(parent, cell, seed):
                if c[1] != last_y:
                    print(f"             {c}")
                    last_y = c[1]
        else:
            print(f"  ok       unreachable:    {fname}")

    print()
    print("standable cells reached per floor:")
    for label, level in cfg["floors"]:
        lo, hi = level + G - 1 - grid.Y0, level + G + 6 - grid.Y0
        print(f"  {label:8} {int(reached[:, max(0, lo):hi, :].sum())}")

    if check_exits:
        failures += exits(cap, cfg, grid, reached)

    print()
    print("RESULT:", "ALL CHECKS PASS" if failures == 0 else f"{failures} FAILURES")
    sys.exit(0 if failures == 0 else 1)


def exits(cap, cfg, open_grid, open_reached):
    """With every door shut, flood from inside: nothing outside may be reached."""
    G = cfg["G"]
    if "inside" not in cfg:
        print()
        print("!! --exits needs an `inside` point for this house in houses.py")
        return 1
    closed = Grid(cap.parts, cfg["bounds"], G, doors_closed=True)
    inside = cfg["inside"]
    seed = closed.nearest(inside[0], inside[1] + G, inside[2], radius=4)
    reached, parent = closed.flood(seed)
    ground = -closed.Y0
    outside_ground = reached[:, ground, :].sum() if 0 <= ground < reached.shape[1] else 0
    print()
    print(f"doors shut: flood from inside at {seed} reaches {int(reached.sum())} cells, {int(outside_ground)} of them on the ground outside")
    if outside_ground:
        cells = np.argwhere(reached[:, ground, :])
        x, z = cells[0]
        cell = (x + closed.X0, ground + closed.Y0, z + closed.Z0)
        print("  LEAK: a way out that is not a door. Route:")
        last = None
        for c in trace(parent, cell, seed):
            if last is None or c[1] != last[1] or abs(c[0] - last[0]) + abs(c[2] - last[2]) > 6:
                print(f"             {c}")
                last = c
        return 1
    print("  ok       the only ways out are the doors")
    return 0


if __name__ == "__main__":
    main()
