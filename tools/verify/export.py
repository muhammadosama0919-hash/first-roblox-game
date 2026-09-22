#!/usr/bin/env python3
"""
Turn a captured house into Roblox model files, and prove the files are right.

    export.py Manor          build/Manor.rbxm and build/Manor.rbxmx
    export.py Villa
    export.py Lodge

The capture (work/<House>.tsv, from compose.py) is what the real module
built. This writes it out as a Rojo JSON model, has Rojo produce the .rbxm
and .rbxmx from that, so every property is encoded by the same library Rojo
uses for everything else, and then reads the .rbxmx back and checks it
against the capture, part by part: position, size, the full rotation matrix,
colour, material, shape, transparency, collision, tags and attributes; and
for the house as a whole, its pivot, its doors and the scripts inside it.
The .rbxm, which is the file that gets sent, goes back through Rojo into XML
and gets the same checks.

The model carries its own copies of DoorController and Groundwork as
Scripts, so the moment it is inserted, with nothing else in the place, its
doors open, and in this project's generated world it stands itself on the
ground and clears the trees out of its rooms. Its pivot is on the ground at
the middle of the footprint, facing the way the house faces, so
`house:PivotTo(CFrame.new(x, groundY, z))` stands it on the ground.

Rojo takes a CFrame as twelve numbers: the position, then the rotation
matrix row by row. A row is (right.x, up.x, back.x), which is how the basis
vectors that came out of the module are laid across, so nothing is
converted on the way in; but a transposed matrix is a rotation that looks
plausible from most angles, so the readback compares every matrix anyway.
"""

import base64
import json
import pathlib
import struct
import subprocess
import sys
import xml.etree.ElementTree as ET

import numpy as np

import capture

HERE = pathlib.Path(__file__).parent
ROOT = HERE.parent.parent
BUILD = ROOT / "build"
WORK = HERE / "work"
# The scripts every house model carries inside it, by the name they get there.
EMBEDDED = {
    "DoorController": ROOT / "src" / "server" / "Houses" / "DoorController.server.luau",
    "Groundwork": ROOT / "src" / "server" / "Houses" / "Groundwork.server.luau",
}
ROJO = HERE / "bin" / "rojo"
if not ROJO.exists():
    ROJO = "rojo"

SHAPE_TOKENS = {"Ball": 0, "Block": 1, "Cylinder": 2}


# --------------------------------------------------------------------------
# The capture as a tree
# --------------------------------------------------------------------------


def cframe12(pos, R):
    """Rojo's twelve numbers: position, then the rotation matrix row by row."""
    return [float(v) for v in pos] + [float(R[i, j]) for i in range(3) for j in range(3)]


def optional_cframe(pivot):
    """A node's pivot (position, right, up, back) as Rojo's OptionalCFrame."""
    pos = pivot[0:3]
    R = np.column_stack([pivot[3:6], pivot[6:9], pivot[9:12]])
    return {"OptionalCFrame": {"position": [float(v) for v in pos], "orientation": R.tolist()}}


def part_json(p):
    props = {
        "Anchored": True,
        "Size": [float(v) for v in p.size],
        "CFrame": cframe12(p.pos, p.R),
        "Color": [float(v) for v in p.colour],
        "Material": p.material,
        "TopSurface": "Smooth",
        "BottomSurface": "Smooth",
        "CanCollide": p.collide,
    }
    if p.cls == "Part" and p.shape != "Block":
        props["Shape"] = p.shape
    if p.transparency:
        props["Transparency"] = p.transparency
    if p.reflectance:
        props["Reflectance"] = p.reflectance
    if not p.query:
        props["CanQuery"] = False
    if not p.touch:
        props["CanTouch"] = False
    if not p.shadow:
        props["CastShadow"] = False
    if p.tags:
        props["Tags"] = p.tags
    out = {"name": p.name, "className": p.cls, "properties": props}
    if p.attrs:
        out["attributes"] = p.attrs
    return out


def node_json(cap, node, children_of):
    out = {"name": node.name, "className": node.cls}
    props = {}
    if node.cls == "Model" and node.pivot is not None:
        props["WorldPivotData"] = optional_cframe(node.pivot)
    if node.tags:
        props["Tags"] = node.tags
    if props:
        out["properties"] = props
    if node.attrs:
        out["attributes"] = node.attrs
    kids = []
    for kind, item in children_of.get(node.id, []):
        kids.append(node_json(cap, item, children_of) if kind == "node" else part_json(item))
    if kids:
        out["children"] = kids
    return out


def build_tree(cap):
    root = cap.root()
    children_of = {}
    for n in cap.nodes.values():
        children_of.setdefault(n.parent, []).append(("node", n))
    for p in cap.parts:
        children_of.setdefault(p.parent, []).append(("part", p))
    tree = node_json(cap, root, children_of)
    for name, path in EMBEDDED.items():
        tree.setdefault("children", []).append(
            {"name": name, "className": "Script", "properties": {"Source": path.read_text()}}
        )
    del tree["name"]  # the root takes its name from the file
    return root, tree


def rojo_build(project, out):
    return subprocess.run([str(ROJO), "build", str(project), "-o", str(out)], capture_output=True, text=True)


# --------------------------------------------------------------------------
# Reading the .rbxmx back
# --------------------------------------------------------------------------


def prop(item, name):
    props = item.find("Properties")
    if props is None:
        return None
    for child in props:
        if child.get("name") == name:
            return child
    return None


def read_cframe(el):
    g = lambda k: float(el.find(k).text)
    pos = np.array([g("X"), g("Y"), g("Z")])
    R = np.array([[g(f"R{i}{j}") for j in range(3)] for i in range(3)])
    return pos, R


def read_colour(el):
    v = int(el.text) & 0xFFFFFFFF
    return np.array([((v >> 16) & 0xFF) / 255, ((v >> 8) & 0xFF) / 255, (v & 0xFF) / 255])


def read_tags(el):
    if el is None or not (el.text or "").strip():
        return []
    raw = base64.b64decode("".join((el.text or "").split()))
    return [t.decode() for t in raw.split(b"\0") if t]


def read_attributes(el):
    """Roblox's attribute blob: a count, then name, type byte and value each."""
    if el is None or not (el.text or "").strip():
        return {}
    raw = base64.b64decode("".join((el.text or "").split()))
    out = {}
    (count,) = struct.unpack_from("<I", raw, 0)
    i = 4
    for _ in range(count):
        (n,) = struct.unpack_from("<I", raw, i)
        i += 4
        name = raw[i : i + n].decode()
        i += n
        kind = raw[i]
        i += 1
        if kind == 0x02:  # string
            (n,) = struct.unpack_from("<I", raw, i)
            i += 4
            out[name] = raw[i : i + n].decode()
            i += n
        elif kind == 0x03:  # bool
            out[name] = raw[i] != 0
            i += 1
        elif kind == 0x06:  # double
            (out[name],) = struct.unpack_from("<d", raw, i)
            i += 8
        elif kind == 0x05:  # float
            (out[name],) = struct.unpack_from("<f", raw, i)
            i += 4
        else:
            raise ValueError(f"attribute {name}: type 0x{kind:02x} not decoded")
    return out


def verify(rbxmx, cap, root, material_values, quiet=False):
    doc = ET.parse(rbxmx).getroot()
    problems = []

    def key(cls, name, pos, size):
        return (cls, name, tuple(np.round(pos, 2)), tuple(np.round(size, 2)))

    expected = {}
    for p in cap.parts:
        expected.setdefault(key(p.cls, p.name, p.pos, p.size), []).append(p)

    checked = 0
    worst_rot = 0.0
    shapes = {"Ball": 0, "Cylinder": 0}
    attr_parts = 0
    for item in doc.iter("Item"):
        cls = item.get("class")
        if cls not in ("Part", "WedgePart"):
            continue
        name = prop(item, "Name").text
        pos, R = read_cframe(prop(item, "CFrame"))
        size_el = prop(item, "size")
        size = np.array([float(size_el.find(k).text) for k in ("X", "Y", "Z")])
        bucket = expected.get(key(cls, name, pos, size))
        if not bucket:
            problems.append(f"{cls} {name} at {np.round(pos, 2).tolist()} is in the file but not in the capture")
            continue
        p = bucket.pop()
        checked += 1
        worst_rot = max(worst_rot, float(np.abs(R - p.R).max()))

        colour = read_colour(prop(item, "Color3uint8"))
        if np.abs(colour - p.colour).max() > 1.5 / 255:
            problems.append(f"{name}: colour {colour} != {p.colour}")
        mat = int(prop(item, "Material").text)
        if mat != material_values[p.material]:
            problems.append(f"{name}: material {mat} != {p.material}")
        if cls == "Part":
            shape_el = prop(item, "shape")
            shape = int(shape_el.text) if shape_el is not None else SHAPE_TOKENS["Block"]
            if shape != SHAPE_TOKENS[p.shape]:
                problems.append(f"{name}: shape {shape} != {p.shape}")
            elif p.shape in shapes:
                shapes[p.shape] += 1
        tr_el = prop(item, "Transparency")
        tr = float(tr_el.text) if tr_el is not None else 0.0
        if abs(tr - p.transparency) > 1e-3:
            problems.append(f"{name}: transparency {tr} != {p.transparency}")
        for pname, want in (("CanCollide", p.collide), ("CanTouch", p.touch), ("CanQuery", p.query), ("CastShadow", p.shadow)):
            el = prop(item, pname)
            got = (el.text == "true") if el is not None else True
            if got != want:
                problems.append(f"{name}: {pname} {got} != {want}")
        tags = read_tags(prop(item, "Tags"))
        if sorted(tags) != sorted(p.tags):
            problems.append(f"{name}: tags {tags} != {p.tags}")
        attrs = read_attributes(prop(item, "AttributesSerialize"))
        if attrs != p.attrs:
            problems.append(f"{name}: attributes {attrs} != {p.attrs}")
        elif attrs:
            attr_parts += 1

    missing = sum(len(v) for v in expected.values())

    # The house as a whole: its pivot, its doors, its scripts.
    models = [i for i in doc.iter("Item") if i.get("class") == "Model"]
    top = doc.find("Item")
    pivot_ok = False
    if top is not None and top.get("class") == "Model":
        el = prop(top, "WorldPivotData")
        if el is not None and el.find("CFrame") is not None:
            pos, R = read_cframe(el.find("CFrame"))
            want_R = np.column_stack([root.pivot[3:6], root.pivot[6:9], root.pivot[9:12]])
            pivot_ok = np.abs(pos - root.pivot[0:3]).max() < 1e-3 and np.abs(R - want_R).max() < 1e-4
    if not pivot_ok:
        problems.append("the house model's WorldPivot is missing or wrong")
    doors = [m for m in models if "Door" in read_tags(prop(m, "Tags"))]
    want_doors = len(cap.tagged_nodes("Door"))
    if len(doors) != want_doors:
        problems.append(f"{len(doors)} Door models in the file, {want_doors} in the capture")
    for d in doors:
        a = read_attributes(prop(d, "AttributesSerialize"))
        if not isinstance(a.get("OpenAngle"), float):
            problems.append(f"door {prop(d, 'Name').text} has no OpenAngle")
    # Each embedded script directly inside the house, source byte for byte
    # what is in src/, and no other code anywhere in the model.
    top_scripts = {}
    for i in top.findall("Item") if top is not None else []:
        if i.get("class") == "Script":
            top_scripts[prop(i, "Name").text] = (prop(i, "Source").text or "").strip()
    code = sum(1 for i in doc.iter("Item") if i.get("class") in ("Script", "LocalScript", "ModuleScript"))
    scripts_ok = code == len(EMBEDDED) and all(
        top_scripts.get(name) == path.read_text().strip() for name, path in EMBEDDED.items()
    )
    if not scripts_ok:
        problems.append(f"the model's scripts are not exactly {', '.join(EMBEDDED)} as they are in src/")
    lights = sum(1 for i in doc.iter("Item") if i.get("class") in ("PointLight", "SpotLight", "SurfaceLight"))

    if not quiet:
        print(f"  parts checked   {checked} of {len(cap.parts)}")
        print(f"  parts missing   {missing}")
        print(f"  worst rotation  {worst_rot:.2e}   (any convention error would be ~1e0)")
        print(f"  round parts     {shapes['Cylinder']} cylinders, {shapes['Ball']} balls")
        print(f"  doors           {len(doors)}, each with its OpenAngle")
        print(f"  hiding places   {attr_parts} parts carry attributes")
        print(f"  pivot           {'ground level, middle of the footprint' if pivot_ok else 'WRONG'}")
        print(f"  scripts         {', '.join(EMBEDDED) + ' inside the model' if scripts_ok else 'WRONG'}")
        print(f"  lights          {lights}")
    if worst_rot > 1e-4:
        problems.append(f"rotation matrices differ by up to {worst_rot}")
    if missing:
        problems.append(f"{missing} captured parts are not in the file")
    if lights:
        problems.append(f"{lights} lights in the file; every lamp should be dead")
    return problems


def main():
    house = sys.argv[1] if len(sys.argv) > 1 else "Manor"
    cap = capture.load(WORK / f"{house}.tsv")
    if cap.errors:
        print("the capture has errors; not exporting:\n  " + "\n  ".join(cap.errors[:5]))
        sys.exit(1)
    print(f"capture: {len(cap.parts)} parts, {len(cap.tagged_nodes('Door'))} doors")

    api = json.load(open(HERE / "api.json")) if (HERE / "api.json").exists() else None
    if api is None:
        print("!! api.json not next to this script; see README.md")
        sys.exit(1)
    material_values = {i["Name"]: i["Value"] for e in api["Enums"] if e["Name"] == "Material" for i in e["Items"]}

    root, tree = build_tree(cap)
    model_json = WORK / f"{house}.model.json"
    project = WORK / f"{house}.project.json"
    model_json.write_text(json.dumps(tree, separators=(",", ":")))
    project.write_text(json.dumps({"name": house, "tree": {"$path": model_json.name}}, indent=2) + "\n")

    BUILD.mkdir(exist_ok=True)
    rbxmx = BUILD / f"{house}.rbxmx"
    rbxm = BUILD / f"{house}.rbxm"
    for out in (rbxmx, rbxm):
        res = rojo_build(project, out)
        if res.returncode != 0:
            print(f"rojo refused the model:\n{res.stderr.strip()[-800:]}")
            sys.exit(1)
    print(f"wrote {rbxmx.name} ({rbxmx.stat().st_size:,} bytes) and {rbxm.name} ({rbxm.stat().st_size:,} bytes)")
    print("readback:")
    problems = verify(rbxmx, cap, root, material_values)

    # The .rbxm is the file that gets sent, and it cannot be read here
    # directly. Rojo can: a project whose tree is the .rbxm builds back into
    # XML, which gets the same checks. Numbers go through 32-bit floats in
    # the binary format, which the checks' tolerances already allow for.
    back = WORK / f"{house}.rbxm.project.json"
    back.write_text(json.dumps({"name": house, "tree": {"$path": str(rbxm.resolve())}}) + "\n")
    back_xml = WORK / f"{house}.from-rbxm.rbxmx"
    res = rojo_build(back, back_xml)
    if res.returncode != 0:
        problems.append(f"rojo could not read {rbxm.name} back: {res.stderr.strip()[-300:]}")
    else:
        binary = [f"{rbxm.name}: {p}" for p in verify(back_xml, cap, root, material_values, quiet=True)]
        print(f"  {rbxm.name:15} read back through Rojo: {'matches' if not binary else 'DIFFERS'}")
        problems += binary

    for p in problems[:20]:
        print("  !!", p)
    if problems:
        print(f"EXPORT FAILED: {len(problems)} problems")
        sys.exit(1)
    print("EXPORT OK: both files match the capture")


if __name__ == "__main__":
    main()
