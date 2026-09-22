# tools/verify — run the manor without Roblox

There is no Roblox runtime in the environment this project is worked on in, so
this is how `src/server/Manor.luau` gets checked before it is sent anywhere.

`roblox_shim.luau` is just enough of the Roblox API — `Vector3`, `CFrame`,
`Color3`, `Enum`, `Instance.new`, `Random`, `CollectionService` — to let the
real module file execute unmodified and capture every part it creates.
`compose.py` splices the shim and the module into one chunk (Luau's CLI
sandboxes globals per module, so injection does not cross a `require`).

Then, from the captured parts:

- `nav.py` voxelises everything that collides and flood-fills from the foot of
  the front steps with a character-sized probe. Every room, both stairs, the
  attic, the bay and every tagged hiding spot must be reachable, and the roofs
  must not be. A wall half a stud too long across a doorway passes every
  render and fails this.
- `render2.py` rasterises the house with a z-buffer, procedural material
  patterns and edge lines. Not what Studio will show, but honest about what
  geometry exists: a hole in the roof is a hole in the picture.
- `export.py` writes the capture out as a Rojo JSON model, has Rojo build
  `build/Manor.rbxm` and `build/Manor.rbxmx` from it, then reads the `.rbxmx`
  back and checks every part's position, size, rotation matrix, colour,
  material, transparency, collision and tags against the capture. The
  rotation passes through Euler angles on the way in, which is exactly the
  kind of conversion that is silently wrong by a sign.

## Setup

Download the binaries this needs into `bin/` (they are gitignored), and the
API dump the exporter reads material values from:

    mkdir -p bin && cd bin
    curl -sSL -o luau.zip   https://github.com/luau-lang/luau/releases/download/0.700/luau-ubuntu.zip
    curl -sSL -o stylua.zip https://github.com/JohnnyMorganz/StyLua/releases/download/v2.5.2/stylua-linux-x86_64.zip
    curl -sSL -o rojo.zip   https://github.com/rojo-rbx/rojo/releases/download/v7.6.1/rojo-7.6.1-linux-x86_64.zip
    unzip -o -q luau.zip && unzip -o -q stylua.zip && unzip -o -q rojo.zip && chmod +x luau stylua rojo
    cd .. && curl -sSL -o api.json https://raw.githubusercontent.com/MaximumADHD/Roblox-Client-Tracker/roblox/API-Dump.json

Python needs `numpy`, `scipy` and `Pillow`.

## Run

    tools/verify/check.sh

Renders land in `tools/verify/out/`.

## Known differences from a real server

`Random` is a MINSTD generator here, not Roblox's. The structure does not
depend on it; the scatter of rubble, slipped boards and which windows are
broken does, so those land differently on a real server. That is by design.
