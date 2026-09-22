# tools/verify — run the houses without Roblox

There is no Roblox runtime in the environment this project is worked on in, so
this is how the houses in `src/server/Houses/` get checked before they are sent
anywhere. Everything is per house: `Manor`, `Villa` or `Lodge`.

`roblox_shim.luau` is just enough of the Roblox API — `Vector3`, `CFrame`,
`Color3`, `Enum`, `Instance.new`, `Random`, `CollectionService` — to let the
real module files execute unmodified and capture every part they create.
`compose.py` splices the shim, the shared kit (`HouseKit`, `Furnish`, `Decor`)
and one house into a single chunk, because Luau's CLI sandboxes globals per
module and injection does not cross a `require`. It writes the capture to
`work/<House>.tsv`, which every other tool reads through `capture.py`.

Then, from the capture:

- `checks.py` — the build ran without a warning; there is no light anywhere
  (every lamp is dead); nothing seen from inside is paler than a luminance
  ceiling, so there is no white; every door is swung shut-to-open in steps
  and may not pass through anything; no piece of furniture is pushed into a
  wall, floor or stair. Walls and wedges are tested as the solids they are,
  not as bounding boxes.
- `nav.py` — voxelises everything that collides and flood-fills from outside
  the front door with a character-sized probe. Every room, stair and tagged
  hiding place must be reachable, and the roofs must not be. For a house
  marked `sealed` in `houses.py` (the villa) it also shuts every door and
  floods from inside: anything it still reaches outside is a way out the
  house was not meant to have.
- `views.py` — preview renders into `out/<House>/`: four sides, above, a
  plan cutaway of each floor, and eye-level shots in each room. `raster.py`
  is the z-buffer behind them. Not what Studio will show, but honest about
  what geometry exists: a hole in a roof is a hole in the picture.
- `export.py` — writes the capture as a Rojo JSON model, has Rojo build
  `build/<House>.rbxm` and `.rbxmx`, then reads the `.rbxmx` back and checks
  every part's position, size, rotation matrix, colour, material, shape,
  transparency, collision, tags and attributes against the capture, plus the
  model's pivot, its doors and the `DoorController` and `Groundwork` scripts
  inside it. The `.rbxm`, the file that actually gets sent, is built back
  into XML by Rojo and gets the same checks.

And one check that is not per house: `groundwork.py` runs the real
`Groundwork.server.luau`, the script in every house that levels the
generated ground under it, stands it there and clears the trees out, against
a mocked world with a slope, a turned house and trees in and out of it.

`houses.py` says, for each house, what the walkability check must reach and
must not, and where the renders look.

## Setup

Download the binaries this needs into `bin/` (they are gitignored), and the
API dump the exporter reads material values from:

    mkdir -p bin && cd bin
    curl -sSL -o luau.zip   https://github.com/luau-lang/luau/releases/download/0.700/luau-ubuntu.zip
    curl -sSL -o stylua.zip https://github.com/JohnnyMorganz/StyLua/releases/download/v2.5.2/stylua-linux-x86_64.zip
    curl -sSL -o rojo.zip   https://github.com/rojo-rbx/rojo/releases/download/v7.6.1/rojo-7.6.1-linux-x86_64.zip
    curl -sSL -o lsp.zip    https://github.com/JohnnyMorganz/luau-lsp/releases/download/1.50.0/luau-lsp-linux.zip
    curl -sSL -o globalTypes.d.luau https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/main/scripts/globalTypes.d.luau
    for z in *.zip; do unzip -o -q "$z"; done && chmod +x luau stylua rojo luau-lsp
    cd .. && curl -sSL -o api.json https://raw.githubusercontent.com/MaximumADHD/Roblox-Client-Tracker/roblox/API-Dump.json

Python needs `numpy`, `scipy` and `Pillow`.

## Run

    tools/verify/check.sh                 every house
    tools/verify/check.sh Lodge           one house
    RENDER=1 tools/verify/check.sh        and write the renders

Or one step at a time, from this folder:

    python3 compose.py Villa && python3 checks.py Villa && python3 nav.py Villa
    python3 views.py Villa hero cut       only shots whose file name has a word
    python3 export.py Villa

## Known differences from a real server

`Random` is a MINSTD generator here, not Roblox's. The structure does not
depend on it; the scatter of rubble, slipped boards and which windows are
broken does, so a house built live by code lands those differently. The model
files are exported from the capture, so what they contain is exactly what was
checked here.
