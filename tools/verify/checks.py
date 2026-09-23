#!/usr/bin/env python3
"""
Checks a captured house must pass beyond walkability.

    checks.py Manor

  - The build ran clean: no errors, no warnings, no part left out of the model.
  - Nothing gives light: no light instances and no Neon. Every lamp is dead.
  - Nothing inside is pale. Every part that can be seen from inside is at or
    under a luminance ceiling, so there is no white, cream or bright surface
    anywhere in the rooms.
  - Every door swings clear: each is turned from shut to fully open in small
    steps, and its leaf may not pass through anything solid on the way.
  - No furniture is pushed into the building: every piece's parts are tested
    against every wall, floor and stair, and outside against the walls,
    gates and buildings of the grounds.
  - No wall inside meets an outside wall across a window.

Each finding names the parts involved, so the fix can be found by name.
"""

import math
import pathlib
import sys

import numpy as np

import capture

HERE = pathlib.Path(__file__).parent

LUMINANCE_LIMIT = 0.125
INSIDE_FOLDERS = {"Interior", "Furniture", "Doors", "Dressing"}
LININGS = {"Wallpaper", "Dado", "ChairRail", "Skirting", "Cornice"}
FRAMES = {"Jamb", "Lintel", "Sill", "Mullion", "Bar", "BarStrap"}
THROUGH_ROOF = {"Ceiling", "RoofSlope", "RoofBoards", "ChimneyLintel"}
FLAT_ON_FLOOR = {"Rug", "RugBorder", "RugMedallion", "Worn", "Flags", "Tiles", "Tile", "Stain", "Smear", "Hole",
                 "Runner", "Ashes", "Hearth", "Path"}
# What furniture is tested against: the building, and outside it the walls,
# gates, paths and small buildings of its grounds.
STRUCTURE_FOLDERS = ("Shell", "Interior", "Grounds")


# --------------------------------------------------------------------------
# Oriented boxes
# --------------------------------------------------------------------------


class Box:
    """
    A part as a convex solid: its corner points and the directions that can
    separate it from another. A block, cylinder or ball is a box (the round
    ones shrunk to sit inside their square); a wedge is the six corners of
    its actual solid, so the empty half of its box is never mistaken for
    something in the way.
    """
    __slots__ = ("verts", "normals", "edges", "name", "id", "lo", "hi")

    def __init__(self, c, R, h, name="", pid=-1, wedge=False):
        self.name, self.id = name, pid
        hx, hy, hz = h
        if wedge:
            # Solid where y <= (hy / hz) * z: the full face on +Z.
            local = np.array([[sx * hx, -hy, sz * hz] for sx in (-1, 1) for sz in (-1, 1)]
                             + [[sx * hx, hy, hz] for sx in (-1, 1)])
            slope_n = np.array([0.0, hz, -hy])
            slope_n /= np.linalg.norm(slope_n)
            slope_d = np.array([0.0, hy, hz])
            slope_d /= np.linalg.norm(slope_d)
            self.normals = [R[:, 0], R[:, 1], R[:, 2], R @ slope_n]
            self.edges = [R[:, 0], R[:, 1], R[:, 2], R @ slope_d]
        else:
            local = np.array([[sx * hx, sy * hy, sz * hz] for sx in (-1, 1) for sy in (-1, 1) for sz in (-1, 1)])
            self.normals = [R[:, 0], R[:, 1], R[:, 2]]
            self.edges = self.normals
        self.verts = local @ R.T + c
        self.lo, self.hi = self.verts.min(axis=0), self.verts.max(axis=0)


def part_box(p, shrink=0.0):
    h = np.maximum(p.size / 2 - shrink, 0.005)
    if p.cls == "Part" and p.shape == "Cylinder":
        r = min(h[1], h[2]) * 0.92  # the round section is inside its square
        h = np.array([h[0], r, r])
    elif p.cls == "Part" and p.shape == "Ball":
        r = float(h.min()) * 0.8
        h = np.array([r, r, r])
    return Box(p.pos, p.R, h, p.name, p.id, wedge=p.cls == "WedgePart")


def overlap(a, b):
    """Separating axis test for two convex solids, by projecting corners."""
    if np.any(a.hi < b.lo) or np.any(b.hi < a.lo):
        return False
    axes = list(a.normals) + list(b.normals)
    for ea in a.edges:
        for eb in b.edges:
            c = np.cross(ea, eb)
            n = np.linalg.norm(c)
            if n > 1e-6:
                axes.append(c / n)
    for ax in axes:
        pa = a.verts @ ax
        pb = b.verts @ ax
        if pa.max() < pb.min() - 1e-6 or pb.max() < pa.min() - 1e-6:
            return False
    return True


def rot_y(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])


# --------------------------------------------------------------------------


def folder_of(p):
    bits = p.path.split("/")
    return bits[2] if len(bits) > 2 else ""


def main():
    name = sys.argv[1] if len(sys.argv) > 1 else "Manor"
    cap = capture.load(HERE / "work" / f"{name}.tsv")
    parts = cap.parts
    failures = 0

    def report(title, rows, limit=25):
        nonlocal failures
        if rows:
            failures += 1
            print(f"FAIL  {title}: {len(rows)}")
            for r in rows[:limit]:
                print(f"        {r}")
            if len(rows) > limit:
                print(f"        ... and {len(rows) - limit} more")
        else:
            print(f"ok    {title}")

    # ---- build ran clean
    report("build errors and warnings", cap.errors + [f"WARN {w}" for w in cap.warnings])

    # ---- no light
    lit = [f"{l['cls']} {l['name']} (parent {l['parent']})" for l in cap.lights]
    lit += [f"Neon part {p.name} at {np.round(p.pos, 1).tolist()}" for p in parts if p.material == "Neon"]
    report("light sources (every lamp should be dead)", lit)

    # ---- nothing pale inside
    pale = []
    for p in parts:
        inside = folder_of(p) in INSIDE_FOLDERS or p.name in LININGS or p.name in FRAMES
        if not inside or p.transparency >= 0.9:
            continue
        lum = capture.luminance(p.colour)
        if lum > LUMINANCE_LIMIT:
            pale.append((lum, p.name, folder_of(p), np.round(p.colour * 255).astype(int).tolist()))
    pale.sort(reverse=True)
    report(f"surfaces inside paler than luminance {LUMINANCE_LIMIT}",
           [f"{n} ({f}) rgb{c} luminance {l:.3f}" for l, n, f, c in pale])

    # ---- door swings
    static = [p for p in parts if p.door is None and p.transparency < 0.9 and p.size.max() > 0.3]
    static_boxes = [(p, part_box(p, 0.02)) for p in static]
    rows = []
    for node in cap.tagged_nodes("Door"):
        mine = [p for p in parts if p.door == node.id]
        hinge = next((p for p in mine if p.name == "Hinge"), None)
        leaf = next((p for p in mine if p.name == "Leaf"), None)
        if hinge is None or leaf is None:
            rows.append(f"{node.name}: no Hinge or Leaf")
            continue
        open_a = math.radians(float(node.attrs.get("OpenAngle", 90)))
        now_a = math.radians(float(node.attrs.get("Angle", 0)))
        closed_R, hpos = hinge.R, hinge.pos
        now_R = closed_R @ rot_y(now_a)
        # Leaf in the hinge frame at its current angle.
        rel_R = now_R.T @ leaf.R
        rel_p = now_R.T @ (leaf.pos - hpos)
        h = leaf.size / 2 - np.array([0.12, 0.12, 0.05])
        hits = {}
        steps = max(2, int(abs(math.degrees(open_a)) / 5))
        for k in range(steps + 1):
            a = open_a * k / steps
            Rw = closed_R @ rot_y(a)
            box = Box(hpos + Rw @ rel_p, Rw @ rel_R, h, "Leaf")
            for p, pb in static_boxes:
                if p.name in FLAT_ON_FLOOR:
                    continue
                # The frame and finishes right at the hinge are what the leaf
                # turns against; they only count further than a stud away.
                if np.linalg.norm((p.pos - hpos) * [1, 0, 1]) < 1.2 and (p.name in FRAMES or p.name in LININGS):
                    continue
                if overlap(box, pb):
                    key = (p.name, p.path.split("/")[-1])
                    hits.setdefault(key, round(math.degrees(a)))
        for (pname, where), deg in sorted(hits.items(), key=lambda kv: kv[1]):
            rows.append(f"{node.name} at {np.round(hinge.pos, 1).tolist()}: leaf hits {pname} ({where}) at {deg} deg")
    report("doors that hit something as they swing", rows, limit=40)

    # ---- furniture pushed into the building
    arch = [p for p in parts if p.furniture is None and p.door is None and p.transparency < 0.9
            and folder_of(p) in STRUCTURE_FOLDERS and p.name not in FLAT_ON_FLOOR]
    arch_boxes = [(p, part_box(p, 0.0)) for p in arch]
    rows = []
    seen = set()
    for p in parts:
        if p.furniture is None or p.transparency >= 0.9 or p.name in FLAT_ON_FLOOR:
            continue
        fb = part_box(p, 0.08)
        for q, qb in arch_boxes:
            if p.name == "Pipe" and q.name in THROUGH_ROOF:
                continue  # a stove pipe goes up through the ceiling and roof on purpose
            if overlap(fb, qb):
                model = cap.nodes[p.furniture].name
                key = (model, q.name, tuple(np.round(cap.nodes[p.furniture].pivot[:3], 0)) if cap.nodes[p.furniture].pivot is not None else None)
                if key in seen:
                    continue
                seen.add(key)
                piv = cap.nodes[p.furniture].pivot
                where = np.round(piv[:3] - [0, 0, 0], 1).tolist() if piv is not None else "?"
                rows.append(f"{model} at {where}: {p.name} into {q.name} at {np.round(q.pos, 1).tolist()}")
    report("furniture pushed into walls, floors or stairs", rows, limit=40)

    # ---- partitions across windows
    walls = [p for p in parts if folder_of(p) == "Interior" and p.furniture is None and p.door is None
             and "Wall" in p.name and p.name not in LININGS]
    frames = [p for p in parts if folder_of(p) == "Shell" and p.name in ("Jamb", "Lintel", "Sill", "Mullion")]
    rows = []
    for w in walls:
        wb = part_box(w, 0.05)
        for f in frames:
            if overlap(wb, part_box(f, 0.05)):
                rows.append(f"{w.name} at {np.round(w.pos, 1).tolist()} meets window {f.name} at {np.round(f.pos, 1).tolist()}")
    report("inside walls meeting windows", rows)

    print()
    counts = {}
    for p in parts:
        counts[folder_of(p)] = counts.get(folder_of(p), 0) + 1
    print(f"{len(parts)} parts: " + ", ".join(f"{k} {v}" for k, v in sorted(counts.items(), key=lambda kv: -kv[1])))
    print("RESULT:", "ALL CHECKS PASS" if failures == 0 else f"{failures} FAILED")
    sys.exit(0 if failures == 0 else 1)


if __name__ == "__main__":
    main()
