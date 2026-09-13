# first-roblox-game

A starter Roblox game: walk around, touch floating coins, watch your score go up.
Small on purpose — it exists so you have something that *runs* on day one, and a
repo layout you can keep growing into.

---

## Step 1 — Install Roblox Studio

Everything in Roblox is built, tested and published from **Roblox Studio**. It is
a free desktop app, and it is **Windows or macOS only** — there is no Linux build
and no web version.

1. Make a Roblox account at <https://www.roblox.com> if you don't have one.
2. Download Studio: <https://create.roblox.com/docs/studio/setup>
3. Open Studio → **New** → pick the **Baseplate** template.
4. Press the **Play** button. You're now standing in your own game.

That's genuinely the whole first step. Do it before anything below.

## Step 2 — Get this code into Studio

Pick one. **Path A needs nothing installed but Studio** — that's the one to use
if you just want to play the thing.

### Path A — open the prebuilt place (no install)

Every change is built here and committed to [`build/`](build/). Download
**`build/first-roblox-game.rbxl`** and open it in Studio. That's it — baseplate,
spawn, coins and all the code, ready to press Play.

**Updating later, once you've built a world:** do *not* open a newer `.rbxl`. It
is a whole place file and would replace everything you made. Instead take the
individual `.rbxmx` models, which carry only code:

| Download | Right-click this in Studio → *Insert from File* |
| --- | --- |
| `build/Shared.rbxmx` | `ReplicatedStorage` |
| `build/Remotes.rbxmx` | `ReplicatedStorage` |
| `build/Server.rbxmx` | `ServerScriptService` |
| `build/Client.rbxmx` | `StarterPlayer` → `StarterPlayerScripts` |

Delete the old folder of the same name first, or you'll end up with `Server` and
`Server1` and only one of them running.

### Path B — live sync with Rojo (one small CLI)

Worth it once Path A's download-and-drag gets tedious. Studio saves a place as
one binary `.rbxl` that git can't diff or merge; Rojo keeps your scripts as
normal `.luau` files here and syncs them into an open Studio session as you save.

```sh
rokit install       # installs the pinned tools — see rokit.toml
rojo plugin install # one-time Studio plugin
rojo serve          # then: Plugins tab → Rojo → Connect
```

Install Rokit first — <https://github.com/rojo-rbx/rokit>. No Rokit? Install Rojo
directly: <https://rojo.space/docs/v7/getting-started/installation/>

To rebuild the files in `build/` yourself: `./build.sh`

> **Saving needs a published place.** Everything else — coins, the shop, the
> movement bonuses — works straight out of the downloaded file. But saving uses
> `DataStoreService`, and data stores belong to a *published* experience, so a
> local `.rbxl` has nothing to save against. The game notices this at startup,
> says so once in the Output window, and plays on without persisting.
>
> To turn saving on, publish once (**File → Publish to Roblox As...**, free),
> then tick **File → Experience Settings → Security → Enable Studio Access to
> API Services**. Order matters — the toggle only means anything after the
> place exists on Roblox.

## Step 3 — Change something

Open `src/shared/Config.luau` and set `coinValue = 10`.

On Path B, save the file and Studio updates by itself. On Path A, either edit the
same value directly in Studio (`ReplicatedStorage` → `Shared` → `Config`), or ask
for a rebuilt `Shared.rbxmx`. Either way the loop — change, play, see it — is
the job.

## Step 4 — Publish

In Studio: **File → Publish to Roblox As...**. Give it a name, and it's a real
game with a real URL you can send to people. Do this early and often; a rough
published game beats a perfect unpublished one.

---

## Connecting Claude directly to Studio

Roblox Studio now ships an **MCP server built in**, which lets an AI client drive
your open place directly — read and edit scripts, run Luau, start a playtest,
read the console, even take viewport screenshots. Claude Code is a supported
client by name.

**This only works with Claude Code installed on the same machine as Studio.**
Everything talks over stdio between two local processes. There is no network
transport and no hosted endpoint, so a cloud-hosted assistant cannot reach it.

1. Update Roblox Studio to the latest version, and open your place.
2. Install Claude Code on that same machine:
   - macOS: `curl -fsSL https://claude.ai/install.sh | bash`
   - Windows (PowerShell): `irm https://claude.ai/install.ps1 | iex`
3. In Studio: **Assistant → `...` → Manage MCP Servers → Enable Studio as MCP server**.
4. In that same panel, open **Quick connect** and toggle on **Claude Code**.
   Studio writes the config for you. If Claude Code isn't listed, install it
   first and restart Studio.
5. Restart Studio and Claude Code. Look for the green connected indicator.
6. Smoke test: `cd` into this repo, run `claude`, and ask it to insert a Part
   into Workspace.

If you'd rather configure it by hand, this is Roblox's published config:

```jsonc
// macOS
{"mcpServers":{"Roblox_Studio":{"command":"/Applications/RobloxStudio.app/Contents/MacOS/StudioMCP"}}}

// Windows
{"mcpServers":{"Roblox_Studio":{"command":"cmd.exe","args":["/c","%LOCALAPPDATA%\\Roblox\\mcp.bat"]}}}
```

> **Watch out:** searching for "roblox mcp" turns up many third-party servers on
> npm and GitHub. None of them are official. The built-in Studio server is the
> one to use — install nothing from npm for this. Roblox's older standalone
> `studio-rust-mcp-server` repo was archived in April 2026; don't start there.

### Using it alongside Rojo

The two tools do different jobs and compose well:

| | Rojo | Studio MCP |
| --- | --- | --- |
| Operates on | files in this repo | the live open place |
| Gives you | version control, code review, history | reading the DataModel, running code, playtesting |

Run `rojo serve` in its own terminal window — **not** as a Claude Code background
task, which dies when the turn ends. Keep the plugin's optional two-way sync
**off** unless you want it, or Studio's edits and Claude's edits will fight.

On Windows, install Claude Code natively and keep the repo on the Windows
filesystem. Running it inside WSL against `/mnt/c` breaks file watching silently
— WSL2 doesn't propagate change notifications across that boundary.

---

## How the code is organised

```
default.project.json    Maps folders here → Roblox services. Rojo reads this.
rokit.toml              Pinned tool versions.
src/
  server/               → ServerScriptService. Trusted. Decides the score.
    Main.server.luau      Coins, leaderstats, save/load lifecycle.
    PlayerData.luau       DataStore reads and writes.
    ShopService.luau      Purchase validation, item effects, sprint state.
    World.luau            Procedural terrain, trees and the cabin.
  client/               → StarterPlayerScripts. Runs on each player's machine.
    Main.client.luau      Coin spin, pickup popup.
    Shop.client.luau      Shop menu.
    Sprint.client.luau    Hold Shift to run, plus the camera kick.
  shared/               → ReplicatedStorage. Both sides can read it.
    Config.luau           Tunable numbers.
    Shop.luau             Item list: names, prices, effects.
```

### The world

Terrain, trees and the cabin are generated in `World.luau` at server start, not
placed by hand in Studio. Heights come from `math.noise`, which is deterministic
— the same coordinates always give the same height, so every server builds an
identical world without storing anything.

The middle is flattened to a clearing so the spawn and the cabin sit level, then
eased back into hills with a smoothstep so the join isn't a cliff. Reshaping the
whole map is a matter of changing `hillHeight`, `worldSize` or `worldSeed` in
`Config.luau`.

Most of the visual difference, though, is `Lighting` in `place.project.json`:
`Future` technology for real shadows, an `Atmosphere` for depth haze, and bloom,
colour grading, depth of field and sun rays on top. That is the cheapest way to
make simple geometry look deliberate — far cheaper than modelling.

### The shop

Three items: Swift Boots (faster), Spring Legs (higher jump), Lucky Charm
(double coins). Bonuses re-apply on every respawn, since a new character starts
with default stats.

Buying goes through a RemoteFunction, and the server does not trust one word of
the request. It looks the item up in the shared list rather than believing the
client about what exists, reads the price from there, and re-checks ownership
and balance before deducting anything. The client script only draws the menu and
displays whatever the server says back — a player editing it can change what
their own menu looks like and nothing else.

### Saving

Progress is written on a timer (`autosaveSeconds`), when a player leaves, and
again on server shutdown via `BindToClose`. The rule that matters most is in
`PlayerData.save`: a profile is never written unless it was successfully read
first. A failed read is not an empty save — treating it as one is how Roblox
games wipe their players' progress.

Studio and live servers use different store names (`PlayerData_v1_studio` vs
`PlayerData_v1`). Data stores belong to the whole experience, so once this place
is published, a Studio playtest would otherwise read and write the same saves
real players use — a bad save routine tested in Studio could corrupt live data.
The split is a convention held up by one line in `PlayerData.luau`, not a
guarantee; the stronger version is a separately published test experience, which
gets different data stores outright.

Availability is probed once at server start rather than per player. In an
unpublished place every request fails identically, and retrying on each join
would stall every player for seconds and fill the console with the same
warning. Offline, the game runs normally and simply doesn't persist.

The split matters more than anything else you'll learn early on. Players can
modify anything running on their own client, so **the server must own every
decision that counts**. The client's job is to make it look good.

In this game: the server spawns coins, detects the touch and awards the point;
the client only spins the coins and draws the "+1 Coin" popup.

File naming is a Rojo convention, not a Roblox one:

| File | Becomes |
| --- | --- |
| `Main.server.luau` | a `Script` (server) |
| `Main.client.luau` | a `LocalScript` (client) |
| `Config.luau` | a `ModuleScript` (either side) |

## What to build next

- **Make the world.** Build geometry by hand in Studio — it's much faster than
  code for anything visual. Only the parts in `src/` need to live in git.
- **Give the shop more to sell.** Adding an item is one entry in
  `src/shared/Shop.luau` — the menu and the purchase check both read that list.
- **Add a win condition.** A timer, a round, a leaderboard. The shop gives coins
  a purpose; a goal gives the session one.

Useful reading:

- Creator docs — <https://create.roblox.com/docs>
- Luau language — <https://luau.org/>
- Rojo — <https://rojo.space/docs/v7/>
