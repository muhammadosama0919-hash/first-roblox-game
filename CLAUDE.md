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
- **Executing a geometry module for real.** `tools/verify/check.sh` runs the
  actual `Manor.luau` under the Luau CLI against a shim of the Roblox API
  (`roblox_shim.luau`), captures every part, flood-fills the result with a
  character-sized probe to prove every room, stair and hiding place is
  reachable and the roofs are not, and renders it with a z-buffer so a hole
  in the roof is a hole in the picture. This found a stair whose treads ate
  into the corridor beside it and a wardrobe buried to its waist in a floor,
  neither of which any static check could see. Use it for anything built
  from parts. `tools/verify/README.md` has the setup.

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
  client/
    Main.client.luau      Coin spin, pickup popup.
    Shop.client.luau      Shop menu.
    Sprint.client.luau    Hold Shift; camera FOV kick.
  shared/
    Config.luau           Every tunable number. Change gameplay here.
    Shop.luau             Item list — name, price, effect.
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

`Manor.luau` builds a derelict three-floor manor from ~1400 Parts and
WedgeParts: two storeys of rooms plus an open attic, a switchback stair
through a double-height hall, a projecting gabled bay, a porch, ten tagged
hiding places (`CollectionService` tag `HidingSpot`). It is deliberately
standalone — requires nothing, reads no Config — so it drops into any version
of the project. `ManorSpawn.server.luau` places it: set `PIVOT` there; it finds
the ground itself by raycasting the terrain and clears trees from its
footprint. The house is asymmetric on purpose: a symmetrical plan with a
centred porch read as a chapel, and it took a projecting bay and a one-sided
porch to make it read as a house.

## Conventions

- Luau, `--!strict`, tabs, formatted with StyLua (`stylua.toml`).
- Rojo pinned to **7.6.1**, not 7.7.0 — 7.7.0 has an open regression
  (rojo-rbx/rojo#1300) where `rojo serve` stops detecting newly created files.
- Comments explain *why*, especially where a choice looks arbitrary or a
  non-obvious failure is being guarded against. Do not narrate what the code
  already says.
