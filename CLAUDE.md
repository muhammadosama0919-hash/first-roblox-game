# first-roblox-game

A Roblox game built as a first project: collect coins on a generated landscape,
spend them in a shop. Luau source in `src/`, synced into Roblox Studio.

## How this project is worked on

The developer is new to Roblox and does **not** run a local editor or Rojo. The
loop has been:

1. Claude edits `src/**.luau` here and commits.
2. Claude runs `./build.sh` to produce `build/first-roblox-game.rbxl`.
3. The developer downloads that file and opens it in Studio.

`build/` is committed on purpose — it is the delivery mechanism, not a build
artifact to be gitignored. `.gitignore` has an explicit exception explaining
this. If the developer starts running Rojo locally, stop committing it.

**Once the developer has done any work inside Studio, stop sending `.rbxl`.**
It replaces the place wholesale, so an imported mesh, a hand-built rig or any
placed geometry is destroyed with no warning and no merge. Send the `.rbxmx`
models instead; they carry only code and insert into an existing place. This
matters now that meshes are being imported by hand.

**The buildings are delivered as model files, sent straight to the developer.**
`tools/verify/export.py` writes `build/Manor.rbxm`, `build/Villa.rbxm`,
`build/Lodge.rbxm`, `build/Church.rbxm` and `build/Farm.rbxm`: each a complete
building with its own copies of `DoorController` and `Groundwork` inside,
which they download and insert into their place. They asked for the model itself, not an `.rbxl`, and said plainly
that git is never how files reach their machine, so a push is not a delivery.
Send the file.

Send an update as **one zipped folder**, not a scatter of separate files;
they asked for exactly that. The models go at the top, with `previews/`,
`source/`, and a `READ ME FIRST.txt` that says how to insert them and what
changed. Check the zipped models are byte-identical to the verified builds.

Two related traps, both verified against the API reference:
- `MeshPart.MeshId` is **read-only from scripts**, so a mesh cannot be swapped
  onto a part in Luau. Meshes must be imported, or created through
  `AssetService:CreateMeshPartAsync` + `MeshPart:ApplyMesh`.
- The creature rig is assembled at runtime by `CreatureFactory.spawn`, so there
  is **no rig in the Explorer** to edit in Studio. Instructions that assume a
  clickable rig are wrong for this project.

**Their cost curve is inverted from a normal solo dev.** Code is cheap; Studio
work — placing geometry, modelling, animation — is expensive, because they do
all of it by hand. Prefer designs where code generates content. Do not propose
anything needing custom meshes, rigs or animations without saying so plainly.

## Verification: what can and cannot be checked here

There is no Roblox runtime in this environment. Nothing can be playtested.

What **can** be verified, and should be, every time:

- `stylua --check src/` — parses every file. Catches syntax errors only.
- `rojo build` — catches invalid project JSON and bad property names.
- Parsing the built place as XML (`rojo build place.project.json -o x.rbxlx`)
  to confirm instances, properties and embedded source actually landed.
- Simulating pure logic in Python — `World.heightAt` was checked this way and it
  caught a bug that would have flooded 1648 terrain cells outside the pond.
- **Executing a geometry module for real.** `tools/verify/check.sh` runs each
  house module unmodified under the Luau CLI against a shim of the Roblox API
  (`roblox_shim.luau`) and captures every part. Per building (the three
  houses, the church and the farm), it then proves there is no light and
  nothing pale inside, swings every door and gate to see that it hits
  nothing, tests every piece of furniture against the walls, floors and
  stairs and every headstone, bale and cart against the grounds' walls,
  fences and paths, flood-fills with a character-sized probe to prove every room,
  stair and hiding place is reachable and the roofs are not (and that the
  villa's two doors are its only ways out, and that the farm's maze can be
  solved to every corner), exports the `.rbxm` and reads it
  back part by part. `RENDER=1` adds z-buffer renders, where a hole in the
  roof is a hole in the picture. This found a stair whose treads ate into the
  corridor beside it, a wardrobe buried to its waist in a floor, sill logs
  across doorways and door after door that swung into furniture, none of
  which any static check could see. It also type-checks the houses in strict
  mode with `luau-lsp`. Use it for anything built from parts.
  `tools/verify/README.md` has the setup.

What **cannot** be verified here is anything that only fails at runtime. Four
bugs shipped that way; the developer's **Output window** log found each one in
seconds. When something looks wrong, ask for that text. It is worth more than a
screenshot.

## Rules this code follows

**No module may throw while loading.** This caused two dead-server-script bugs.
`require` failing takes down everything downstream — a missing scenery instance
killed leaderstats, coins, saving and the shop at the same time. Anything that
can fail is wrapped, resolved late, and degrades with a message.

**Prefer constructions with no convention to get wrong.** This environment
cannot render, so any geometry resting on "which face of a WedgePart is the
vertical one" is unverifiable. Deriving axes from points instead makes it
checkable with arithmetic.

**Check the API dump for `NotScriptable`, not just whether a property exists.**
`Terrain.Decoration`, `Terrain.GrassLength`, `Terrain.MaterialColors` and
`Lighting.Technology` are real, saveable properties that **error if assigned
from a script**. They belong in the `.project.json` files. Docs live at
`raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/...` —
`create.roblox.com` and `devforum.roblox.com` are blocked by egress here.

**`WaitForChild` always takes a deadline.** Without one, a missing instance is a
silent permanent stall and an empty Output window, which is harder to diagnose
than a crash. Use the local `expect()` helper. `PlayerGui` is the deliberate
exception — Roblox always creates it.

**The server owns every decision that counts.** Players can edit their own
client. `ShopService.purchase` takes its item id as `unknown`, looks the item up
in the shared list rather than trusting the client that it exists, and re-checks
price, ownership and balance. Client scripts only draw and report.

**A failed DataStore read is not an empty save.** `PlayerData.save` refuses to
write a profile that never loaded. Treating a failed read as "no data" is how
Roblox games erase their players.

## Layout

```
default.project.json    Maps src/ onto services. For Rojo live-sync.
place.project.json      Adds Terrain, SpawnLocation and all Lighting. Builds
                        the standalone .rbxl.
build.sh                Regenerates everything in build/.
src/
  server/
    Main.server.luau      Coins, leaderstats, lifecycle, remote handlers.
    PlayerData.luau       DataStore reads/writes. Studio and live use separate
                          store names so playtests cannot touch live saves.
    ShopService.luau      Purchase validation, item effects, sprint state.
    World.luau            Terrain, pond, trees, cabin — all procedural.
    Houses/
      HouseKit.luau       Shared building vocabulary: walls with holes,
                          windows, doors, stairs, rods, triangles, palette.
      Furnish.luau        Furniture. Every piece a Model tagged Furniture.
      Decor.luau          Dead lamps, pictures, trophies, dirt and damage.
      Yard.luau           Outside: headstones, walls, railings, paths, the
                          lych-gate, mausoleum, trees, crows; fences, field
                          gates, bales, wagon, well, scarecrow, corn rows.
      Manor.luau          House #1. Villa.luau is #2, Lodge.luau is #3.
      Church.luau         The church and its churchyard.
      Farm.luau           The barn, silo, windpump, yard and corn maze.
      DoorController.server.luau   Opens every Door-tagged model. A copy is
                          embedded in each exported model.
      Groundwork.server.luau       Also embedded in each model: levels the
                          generated ground under it, stands it there, digs
                          its GroundCut holes, clears the trees out of it.
      ManorSpawn.server.luau       Builds the manor if none is placed, and
                          clears trees from under every building.
  client/
    Main.client.luau      Coin spin, pickup popup.
    Shop.client.luau      Shop menu.
    Sprint.client.luau    Hold Shift; camera FOV kick.
  shared/
    Config.luau           Every tunable number. Change gameplay here.
    Shop.luau             Item list — name, price, effect.
tools/verify/             Runs the buildings without Roblox. See its README.
```

Most visual quality comes from `Lighting` in `place.project.json`, not geometry:
`Future` technology, `Atmosphere`, bloom, colour grading, depth of field, sun
rays. That is the cheapest way to make simple shapes look deliberate.

## Current state

Working: generated terrain with a pond and shoreline, ~90 trees, a cabin, 22
coins, leaderstats, a three-item shop with server-validated purchases, sprint on
Shift, DataStore saving with graceful degradation.

Also working: a Motor6D creature rig with four code-driven animations (walk,
run, feed, attack). Animated by writing joint rotations rather than playing
animation assets, because every `AnimationClipProvider` method takes an asset
id — an authored animation cannot play without being uploaded to Roblox first,
and `Motor6D.Transform` needs no upload. `CreatureDemo` is a showcase to delete
once the creature gets behaviour.

The gable triangles are no longer a guess: they are built from their three
corner points via `triangle()` in `World.luau`, which derives every axis from
the geometry, so there is no wedge orientation convention left to get wrong.
Verified numerically — the two wedges cover exactly the triangle's area for
acute, right and obtuse cases.

Saving is off until the place is published — `GetDataStore` throws outright in
an unpublished place. The code detects this at startup and says so once. The
yellow `[PlayerData]` warnings are expected, not failures.

### The houses

Three derelict horror houses, built entirely in code from Parts and
WedgeParts in `src/server/Houses/`, furnished, and exported as models:

- **Manor** (#1, ~5600 parts): Victorian, three floors. Four rooms round a
  long hall downstairs; upstairs almost all one dining hall, the width of the
  house, with a table laid for twenty; an attic the length of the roof. It
  is asymmetric on purpose: a symmetrical plan with a centred porch read as
  a chapel, and it took a projecting bay and a one-sided porch to make it
  read as a house.
- **Villa** (#2, ~6400 parts): Italianate brick, two floors and a flat roof
  terrace reached through a belvedere. **Exactly two ways out** (front door,
  kitchen door) — the developer asked for that. Every other window is
  barred and the roof is fenced higher than a jump, and `nav.py` proves it.
- **Lodge** (#3, ~3400 parts): one spacious storey of round logs, a great
  room open to the trusses, a fieldstone chimney, trophy room, workshop.

And two larger pieces of the village, each with its grounds, built and
checked the same way:

- **Church** (~6500 parts): stone nave and aisles, chancel, porch, vestry,
  and a tower with a broach spire; eight flights round an open well up to
  the bell. Pews, pulpit, organ and three-part confessional (both hiding
  places), altar, a bier in the tower. The churchyard round it: walls with a
  fallen stretch, railings, a lych-gate and a wicket gate that open, a
  mausoleum with a door (a hiding place), 80-odd graves laid in rows clear
  of paths and gates, dead trees, a yew, crows, an open grave.
- **Farm** (~4000 parts): a gambrel barn with a drive-through aisle,
  twelve stalls with gates, lofts on four sides up a stair, a tack room and
  feed room, a hay door under its hoist; a stave silo you can walk into, a
  windpump and tank, outhouse, tool shed and hen house, a fenced yard with
  field gates, and behind it a maze of dead corn (seeded, one way between
  any two cells) with a scarecrow in the middle. Hiding: the harness and
  tool cupboards, the silo, the outhouse, under the hay wagon.

Loose pieces outside go in `Churchyard`/`Farmyard`; walls, fences, gates'
posts, paths and small buildings in `Grounds`, which the checks treat as
structure. The field gates are Door models whose leaf is an unseen board
with the bars riding on it, so they swing and collide like any door.

What the developer asked for, which a later change must not undo — the
checks enforce the first three:

- **No white inside.** Browns and dark colours only; nothing visible from
  inside is paler than luminance 0.125. Window frames are dark too.
- **No lit lamps.** No light instances, no Neon. Every bulb is dead.
- **Every door opens**, by a prompt on its knob (`DoorController`).
- **Rounded, not square**, wherever the real thing would be turned or
  rolled: legs, rails, arms, knobs. Parts with `Shape` Cylinder or Ball.
- Places to hide are tagged `HidingSpot` with a `Kind` attribute
  (Cupboard, Wardrobe, UnderTable, UnderBed).

Every window is glassless on purpose. In the manor and the lodge that means
a player can climb out through one; only the villa bars them.

Each house's pivot is on the ground in the middle of its footprint, facing
the way the front door faces, so `house:PivotTo(CFrame.new(x, groundY, z))`
stands it on the ground. The world's terrain only exists once the game runs,
so a house placed in Studio's editor cannot be put on it by hand: the
`Groundwork` script inside each house does it at server start, levelling a
pad at the middle height of the ground it covers, moving the house onto it
(height only), digging out any `GroundCut` part inside it (an unseen box
marking a hole the building needs: the open grave, the well — a model can
hold a hole's sides but not make one) and clearing the generator's trees
from its footprint. In a place without the generator it touches nothing. `groundwork.py` runs it
against a mocked world. `ManorSpawn.server.luau` builds a manor at its
`PIVOT` if none is in the place, and also clears trees from under every
house it finds. `DoorController` reads each hinge live on every step, so a
house moved at runtime still swings its doors in the right place.

## Conventions

- Luau, `--!strict`, tabs, formatted with StyLua (`stylua.toml`).
- Rojo pinned to **7.6.1**, not 7.7.0 — 7.7.0 has an open regression
  (rojo-rbx/rojo#1300) where `rojo serve` stops detecting newly created files.
- Comments explain *why*, especially where a choice looks arbitrary or a
  non-obvious failure is being guarded against. Do not narrate what the code
  already says.
