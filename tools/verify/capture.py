#!/usr/bin/env python3
"""
Read a capture written by compose.py into parts and nodes.

One loader for every tool, so the renderer, the walkability check, the
exporter and the checks all agree on what a line means. A part knows its
shape, tags and attributes, and which door or piece of furniture it belongs
to, because those are found through the tree rather than by name.
"""

import json
import pathlib

import numpy as np


class Part:
    __slots__ = ("cls", "name", "path", "size", "pos", "R", "colour", "material",
                 "transparency", "collide", "tags", "id", "parent", "query", "shadow",
                 "shape", "touch", "attrs", "reflectance", "door", "furniture")

    def corners(self):
        """The eight corners of the part's box, in world space."""
        signs = np.array([[sx, sy, sz] for sx in (-1, 1) for sy in (-1, 1) for sz in (-1, 1)])
        return (signs * (self.size / 2)) @ self.R.T + self.pos

    def aabb(self):
        half = np.abs(self.R) @ (self.size / 2)
        return self.pos - half, self.pos + half


class Node:
    __slots__ = ("id", "cls", "name", "parent", "tags", "attrs", "kids", "pivot")


class Capture:
    def __init__(self):
        self.parts = []
        self.nodes = {}
        self.lights = []
        self.warnings = []
        self.prints = []
        self.errors = []
        self.hiding = None
        self.reported = None
        self.entrance = None

    def ancestors(self, nid):
        out = []
        while nid in self.nodes:
            out.append(self.nodes[nid])
            nid = self.nodes[nid].parent
        return out

    def root(self):
        roots = [n for n in self.nodes.values() if n.parent not in self.nodes and n.cls == "Model"]
        assert len(roots) == 1, f"expected one root model, found {[n.name for n in roots]}"
        return roots[0]

    def tagged_nodes(self, tag):
        return [n for n in self.nodes.values() if tag in n.tags]


def _vec(text):
    return np.array([float(v) for v in text.split(",")])


def _attrs(text):
    return json.loads(text) if text else {}


def load(path):
    cap = Capture()
    for line in pathlib.Path(path).read_text().splitlines():
        f = line.split("\t")
        kind = f[0]
        if kind == "PART":
            p = Part()
            p.cls, p.name, p.path = f[1], f[2], f[3]
            p.size = _vec(f[4])
            p.pos = _vec(f[5])
            p.R = np.column_stack([_vec(f[6]), _vec(f[7]), _vec(f[8])])  # local -> world
            p.colour = _vec(f[9])
            p.material = f[10]
            p.transparency = float(f[11])
            p.collide = f[12] == "true"
            p.tags = [t for t in f[13].split(",") if t]
            p.id = int(f[14])
            p.parent = int(f[15])
            p.query = f[16] == "true"
            p.shadow = f[17] == "true"
            p.shape = f[18] if len(f) > 18 else "Block"
            p.touch = f[19] == "true" if len(f) > 19 else True
            p.attrs = _attrs(f[20]) if len(f) > 20 else {}
            p.reflectance = float(f[21]) if len(f) > 21 else 0.0
            p.door = None
            p.furniture = None
            cap.parts.append(p)
        elif kind == "NODE":
            n = Node()
            n.id, n.cls, n.name, n.parent = int(f[1]), f[2], f[3], int(f[4])
            n.tags = [t for t in f[5].split(",") if t] if len(f) > 5 else []
            n.attrs = _attrs(f[6]) if len(f) > 6 else {}
            # Pivot: position, then the right, up and back columns.
            n.pivot = _vec(f[7]) if len(f) > 7 and f[7] else None
            n.kids = []
            cap.nodes[n.id] = n
        elif kind == "LIGHT":
            cap.lights.append(dict(id=int(f[1]), cls=f[2], name=f[3], parent=int(f[4]),
                                   colour=_vec(f[5]), brightness=float(f[6]),
                                   range=float(f[7]), shadows=f[8] == "true"))
        elif kind == "WARN":
            cap.warnings.append(f[1] if len(f) > 1 else "")
        elif kind == "PRINT":
            cap.prints.append(f[1] if len(f) > 1 else "")
        elif kind in ("ERROR", "BADPART"):
            cap.errors.append(line)
        elif kind == "HIDING":
            cap.hiding = int(f[1])
        elif kind == "REPORTED":
            cap.reported = int(f[1])
        elif kind == "ENTRANCE":
            cap.entrance = (_vec(f[1]), _vec(f[2]))

    for n in cap.nodes.values():
        if n.parent in cap.nodes:
            cap.nodes[n.parent].kids.append(n.id)

    for p in cap.parts:
        for n in cap.ancestors(p.parent):
            if p.door is None and "Door" in n.tags:
                p.door = n.id
            if p.furniture is None and "Furniture" in n.tags:
                p.furniture = n.id
    return cap


def luminance(colour):
    """Relative luminance of an sRGB colour, 0 black to 1 white."""
    c = np.asarray(colour, dtype=float)
    lin = np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)
    return float(0.2126 * lin[0] + 0.7152 * lin[1] + 0.0722 * lin[2])
