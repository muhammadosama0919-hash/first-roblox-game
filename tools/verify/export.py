#!/usr/bin/env python3
"""
Turn the captured manor into a Roblox model file, and prove the file is right.

The capture (parts.tsv) is what the real module built. This writes it out as
a Rojo JSON model, has Rojo produce the .rbxm and .rbxmx from that — so every
property is encoded by the same library Rojo uses for everything else, not by
hand — and then reads the .rbxmx back and checks every part against the
capture: position, size, full rotation matrix, colour, material, transparency,
collision and tags.

Rojo takes a CFrame as twelve numbers: the position, then the rotation matrix
row by row. A row is (right.x, up.x, back.x), which is how the basis vectors
that came out of the module are laid across, so nothing is converted on the
way in — but a transposed matrix is a rotation that looks plausible from most
angles, so the readback compares every matrix anyway.
"""

import base64
import json
import pathlib
import subprocess
import sys
import xml.etree.ElementTree as ET

import numpy as np

HERE = pathlib.Path(__file__).parent
ROOT = HERE.parent.parent
BUILD = ROOT / "build"
ROJO = HERE / "bin" / "rojo"
if not ROJO.exists():
    ROJO = "rojo"

TSV = HERE / "parts.tsv"
MODEL_JSON = HERE / "Manor.model.json"
PROJECT = HERE / "manor.project.json"


# --------------------------------------------------------------------------
# Read the capture into a tree
# --------------------------------------------------------------------------


def vec(text):
    return [float(v) for v in text.split(",")]


def load(tsv):
    nodes = {}
    for line in tsv.read_text().splitlines():
        f = line.split("\t")
        kind = f[0]
        if kind == "NODE":
            nodes[int(f[1])] = dict(cls=f[2], name=f[3], parent=int(f[4]), kids=[], props={})
        elif kind == "LIGHT":
            r, g, b = vec(f[5])
            nodes[int(f[1])] = dict(cls=f[2], name=f[3], parent=int(f[4]), kids=[], props={
                "Color": [r, g, b],
                "Brightness": float(f[6]),
                "Range": float(f[7]),
                "Shadows": f[8] == "true",
            })
        elif kind == "PART":
            nid, parent = int(f[14]), int(f[15])
            r, u, b = vec(f[6]), vec(f[7]), vec(f[8])
            props = {
                "size": vec(f[4]),
                "pos": vec(f[5]),
                "r": r, "u": u, "b": b,
                "colour": vec(f[9]),
                "material": f[10],
                "transparency": float(f[11]),
                "collide": f[12] == "true",
                "tags": [t for t in f[13].split(",") if t],
                "query": f[16] == "true" if len(f) > 16 else True,
                "castShadow": f[17] == "true" if len(f) > 17 else True,
            }
            nodes[nid] = dict(cls=f[1], name=f[2], parent=parent, kids=[], props=props)

    for nid, n in nodes.items():
        if n["parent"] in nodes:
            nodes[n["parent"]]["kids"].append(nid)

    roots = [nid for nid, n in nodes.items() if n["cls"] == "Model" and n["name"] == "Manor"]
    assert len(roots) == 1, f"expected one Manor model, found {len(roots)}"
    return nodes, roots[0]


# --------------------------------------------------------------------------
# CFrame as Rojo's twelve numbers: position, then the matrix row by row
# --------------------------------------------------------------------------


def cframe12(pos, r, u, b):
    return list(pos) + [r[0], u[0], b[0], r[1], u[1], b[1], r[2], u[2], b[2]]


# --------------------------------------------------------------------------
# Write the Rojo JSON model
# --------------------------------------------------------------------------


def to_json(nodes, nid):
    n = nodes[nid]
    out = {"name": n["name"], "className": n["cls"]}
    p = n["props"]

    if n["cls"] in ("Part", "WedgePart"):
        props = {
            "Anchored": True,
            "Size": p["size"],
            "CFrame": cframe12(p["pos"], p["r"], p["u"], p["b"]),
            "Color": p["colour"],
            "Material": p["material"],
            "TopSurface": "Smooth",
            "BottomSurface": "Smooth",
            "CanCollide": p["collide"],
        }
        if p["transparency"]:
            props["Transparency"] = p["transparency"]
        if not p["query"]:
            props["CanQuery"] = False
        if not p["castShadow"]:
            props["CastShadow"] = False
        if p["tags"]:
            props["Tags"] = p["tags"]
        out["properties"] = props
    elif n["cls"] in ("PointLight", "SpotLight", "SurfaceLight"):
        out["properties"] = dict(p)

    kids = [to_json(nodes, k) for k in n["kids"]]
    if kids:
        out["children"] = kids
    return out


def write_model(nodes, root):
    # No pivot is set: this Rojo accepts neither WorldPivotData nor a
    # PrimaryPart reference from JSON, so Studio gives the model its default
    # bounding-box pivot. Ground level is 7 studs above the model's bottom.
    tree = to_json(nodes, root)
    del tree["name"]                      # the root takes its name from the file
    MODEL_JSON.write_text(json.dumps(tree, separators=(",", ":")))
    PROJECT.write_text(json.dumps({"name": "Manor", "tree": {"$path": "Manor.model.json"}}, indent=2) + "\n")


def rojo_build(out):
    return subprocess.run([str(ROJO), "build", str(PROJECT), "-o", str(out)],
                          capture_output=True, text=True)


# --------------------------------------------------------------------------
# Read the .rbxmx back and compare with the capture
# --------------------------------------------------------------------------


def prop(item, name):
    for child in item.find("Properties"):
        if child.get("name") == name:
            return child
    return None


def read_cframe(el):
    g = lambda k: float(el.find(k).text)
    pos = [g("X"), g("Y"), g("Z")]
    m = [[g(f"R{i}{j}") for j in range(3)] for i in range(3)]
    right = [m[0][0], m[1][0], m[2][0]]
    up = [m[0][1], m[1][1], m[2][1]]
    back = [m[0][2], m[1][2], m[2][2]]
    return pos, right, up, back


def read_colour(el):
    v = int(el.text) & 0xFFFFFFFF
    return [((v >> 16) & 0xFF) / 255, ((v >> 8) & 0xFF) / 255, (v & 0xFF) / 255]


def read_tags(el):
    if el is None or not (el.text or "").strip():
        return []
    raw = base64.b64decode("".join((el.text or "").split()))
    return [t.decode() for t in raw.split(b"\0") if t]


def verify(rbxmx, nodes, material_values):
    root = ET.parse(rbxmx).getroot()

    # Index the capture by a key that is unique in practice: class, name,
    # position and size to two decimals.
    def key(cls, name, pos, size):
        return (cls, name, tuple(round(v, 2) for v in pos), tuple(round(v, 2) for v in size))

    expected = {}
    for n in nodes.values():
        if n["cls"] in ("Part", "WedgePart"):
            p = n["props"]
            expected.setdefault(key(n["cls"], n["name"], p["pos"], p["size"]), []).append(n)

    checked = 0
    worst_rot = 0.0
    problems = []
    for item in root.iter("Item"):
        cls = item.get("class")
        if cls not in ("Part", "WedgePart"):
            continue
        name = prop(item, "Name").text
        pos, right, up, back = read_cframe(prop(item, "CFrame"))
        size_el = prop(item, "size")
        size = [float(size_el.find(k).text) for k in ("X", "Y", "Z")]

        bucket = expected.get(key(cls, name, pos, size))
        if not bucket:
            problems.append(f"{cls} {name} at {pos} is in the file but not in the capture")
            continue
        n = bucket.pop()
        p = n["props"]
        checked += 1

        for got, want in ((right, p["r"]), (up, p["u"]), (back, p["b"])):
            worst_rot = max(worst_rot, float(np.abs(np.array(got) - np.array(want)).max()))

        colour = read_colour(prop(item, "Color3uint8"))
        if np.abs(np.array(colour) - np.array(p["colour"])).max() > 1.5 / 255:
            problems.append(f"{name}: colour {colour} != {p['colour']}")

        mat = int(prop(item, "Material").text)
        if mat != material_values[p["material"]]:
            problems.append(f"{name}: material {mat} != {p['material']}")

        tr_el = prop(item, "Transparency")
        tr = float(tr_el.text) if tr_el is not None else 0.0
        if abs(tr - p["transparency"]) > 1e-3:
            problems.append(f"{name}: transparency {tr} != {p['transparency']}")

        cc_el = prop(item, "CanCollide")
        cc = (cc_el.text == "true") if cc_el is not None else True
        if cc != p["collide"]:
            problems.append(f"{name}: CanCollide {cc} != {p['collide']}")

        tags = read_tags(prop(item, "Tags"))
        if sorted(tags) != sorted(p["tags"]):
            problems.append(f"{name}: tags {tags} != {p['tags']}")

    missing = sum(len(v) for v in expected.values())
    lights = sum(1 for i in root.iter("Item") if i.get("class") == "PointLight")
    want_lights = sum(1 for n in nodes.values() if n["cls"] == "PointLight")
    if lights != want_lights:
        problems.append(f"{lights} PointLights in file, {want_lights} in capture")

    print(f"  parts checked   {checked}")
    print(f"  parts missing   {missing}")
    print(f"  worst rotation  {worst_rot:.2e}   (any convention error would be ~1e0)")
    print(f"  lights          {lights}")
    if worst_rot > 1e-4:
        problems.append(f"rotation matrices differ by up to {worst_rot}")
    if missing:
        problems.append(f"{missing} captured parts are not in the file")
    return problems


def main():
    nodes, root = load(TSV)
    parts = sum(1 for n in nodes.values() if n["cls"] in ("Part", "WedgePart"))
    print(f"capture: {parts} parts, {sum(1 for n in nodes.values() if n['cls'] == 'PointLight')} lights")

    api = json.load(open(HERE / "api.json")) if (HERE / "api.json").exists() else None
    if api is None:
        print("!! api.json not next to this script; see README.md")
        sys.exit(1)
    material_values = {i["Name"]: i["Value"] for e in api["Enums"] if e["Name"] == "Material" for i in e["Items"]}

    BUILD.mkdir(exist_ok=True)
    rbxmx = BUILD / "Manor.rbxmx"
    rbxm = BUILD / "Manor.rbxm"

    write_model(nodes, root)
    res = rojo_build(rbxmx)
    if res.returncode != 0:
        print(f"rojo refused the model:\n{res.stderr.strip()[-600:]}")
        sys.exit(1)

    res = rojo_build(rbxm)
    if res.returncode != 0:
        print(res.stderr)
        sys.exit(1)

    print(f"wrote {rbxmx.name} ({rbxmx.stat().st_size:,} bytes) and {rbxm.name} ({rbxm.stat().st_size:,} bytes)")
    print("readback:")
    problems = verify(rbxmx, nodes, material_values)
    for p in problems[:20]:
        print("  !!", p)
    if problems:
        print(f"EXPORT FAILED: {len(problems)} problems")
        sys.exit(1)
    print("EXPORT OK: file matches capture")


if __name__ == "__main__":
    main()
