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

What **cannot** be verified here is anything that only fails at runtime. Four
bugs shipped that way; the developer's **Output window** log found each one in
seconds. When something looks wrong, ask for that text. It is worth more than a
screenshot.

## Rules this code follows

**No module may throw while loading.** This caused two dead-server-script bugs.
`require` failing takes down everything downstream — a missing scenery instance
killed leaderstats, coins, saving and the shop at the same time. Anything that
can fail is wrapped, resolved late, and degrades with a message.

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

Known unverified: the **roof gable triangles** on the cabin use `WedgePart`
orientation reasoned about from first principles and never rendered. If they
point the wrong way, flip the sign on the Y rotation in `buildHouse`.

Saving is off until the place is published — `GetDataStore` throws outright in
an unpublished place. The code detects this at startup and says so once. The
yellow `[PlayerData]` warnings are expected, not failures.

## Conventions

- Luau, `--!strict`, tabs, formatted with StyLua (`stylua.toml`).
- Rojo pinned to **7.6.1**, not 7.7.0 — 7.7.0 has an open regression
  (rojo-rbx/rojo#1300) where `rojo serve` stops detecting newly created files.
- Comments explain *why*, especially where a choice looks arbitrary or a
  non-obvious failure is being guarded against. Do not narrate what the code
  already says.
