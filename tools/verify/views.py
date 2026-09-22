#!/usr/bin/env python3
"""
Preview renders of a captured house.

    views.py Manor              every shot
    views.py Manor hero cut     only shots whose file name contains a word

Exterior shots from four sides and above; a top-down cutaway of each floor
(everything that starts above the cut removed, so rooms, furniture and doors
read like a plan); and eye-level shots inside, at the height a player's
camera sits.
"""

import math
import pathlib
import sys

import numpy as np

import capture
import raster
from houses import HOUSES

HERE = pathlib.Path(__file__).parent


def main():
    name = sys.argv[1] if len(sys.argv) > 1 else "Manor"
    only = sys.argv[2:]
    cfg = HOUSES[name]
    G = cfg["G"]
    cap = capture.load(HERE / "work" / f"{name}.tsv")
    parts = cap.parts
    out = HERE / "out" / name
    out.mkdir(parents=True, exist_ok=True)

    lo, hi = raster.extent(parts)
    centre = (lo + hi) / 2
    radius = float(np.linalg.norm(hi - lo) / 2)

    earth = np.array([0.19, 0.15, 0.12])
    ground = []
    reach, tiles = 420.0, 14
    for i in range(tiles):
        for j in range(tiles):
            x0 = -reach + 2 * reach * i / tiles
            x1 = -reach + 2 * reach * (i + 1) / tiles
            z0 = -reach + 2 * reach * j / tiles
            z1 = -reach + 2 * reach * (j + 1) / tiles
            ground.append(([[x0, 0.02, z0], [x1, 0.02, z0], [x1, 0.02, z1], [x0, 0.02, z1]],
                           earth * (0.9 + 0.1 * ((i + j) % 2))))

    def wanted(file):
        return not only or any(w in file for w in only)

    def eye_for(direction, target, fov, margin, size):
        d = np.array(direction, float)
        d /= np.linalg.norm(d)
        W, H = size
        half = math.radians(fov) / 2
        hhalf = math.atan(math.tan(half) * W / H)
        return np.array(target, float) + d * radius * margin / math.sin(min(half, hhalf))

    def shoot(file, eye, target, keep=None, fov=38.0, size=(1500, 950), with_ground=True, **kw):
        tris, owner, extra = raster.soup(parts, keep, ground if with_ground else None)
        img = raster.render(parts, tris, owner, eye, target, size=size, fov=fov, extra_colours=extra, **kw)
        img.save(out / file)
        print(f"{name}/{file}: {len(tris)} tris")

    base = np.array([centre[0], (lo[1] + hi[1]) / 2, centre[2]])
    exterior = [
        ("01-hero.png", (0.78, 0.24, 0.85), base + np.array([0, -4.0, 0]), 36),
        ("02-front.png", (0.05, 0.12, 1.0), base + np.array([0, -2.0, 0]), 34),
        ("03-right.png", (1.0, 0.14, 0.15), base, 34),
        ("04-back.png", (-0.6, 0.22, -0.9), base, 36),
        ("05-left.png", (-1.0, 0.18, 0.3), base, 34),
        ("06-above.png", (0.35, 1.0, 0.55), base, 36),
    ]
    for file, direction, target, fov in exterior:
        if wanted(file):
            shoot(file, eye_for(direction, target, fov, 1.0, (1500, 950)), target, fov=fov)

    # A ground-level shot of the front, as a player walking up would see it.
    if wanted("07-approach.png"):
        front_z = hi[2]
        shoot("07-approach.png", np.array([centre[0] + 30, 5.5, front_z + 45]),
              np.array([centre[0] - 5, 16, front_z - 25]), fov=55)

    views = cfg.get("views", {})
    for file, cut in views.get("cut", []):
        if not wanted(file):
            continue
        cutY = cut + G
        floorY = cutY - 9.5

        def keep(p, cutY=cutY, floorY=floorY):
            lo_, hi_ = p.aabb()
            return lo_[1] < cutY and hi_[1] > floorY - 1.5

        target = np.array([centre[0], floorY, centre[2]])
        eye = target + np.array([0.0, 1.0, 0.55]) / np.linalg.norm([0.0, 1.0, 0.55]) * radius * 2.0
        shoot(file, eye, target, keep=keep, fov=40, with_ground=False, fog_near=1e4, fog_far=2e4)

    for file, eye, target in views.get("eye", []):
        if not wanted(file):
            continue
        e = np.array(eye, float) + [0, G, 0]
        t = np.array(target, float) + [0, G, 0]
        shoot(file, e, t, fov=70, near=0.3)


if __name__ == "__main__":
    main()
