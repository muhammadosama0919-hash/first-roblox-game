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

Studio saves your game as a single binary `.rbxl` file, which git can't diff or
merge. The standard fix is **Rojo**: your scripts stay as normal `.luau` files in
this repo, and Rojo live-syncs them into an open Studio session. Edit in VS Code,
see it change in Studio instantly.

**Install the tools** (Rokit pins the versions listed in `rokit.toml`):

```sh
# Install Rokit itself: https://github.com/rojo-rbx/rokit
rokit install
```

No Rokit? Install Rojo directly instead — <https://rojo.space/docs/v7/getting-started/installation/>

**Install the Studio plugin**, once:

```sh
rojo plugin install
```

**Start syncing:**

```sh
rojo serve
```

Then in Studio: the **Rojo** button in the Plugins tab → **Connect**. Your
`src/` folder appears in the Explorer. Press Play and collect a coin.

## Step 3 — Change something

Open `src/shared/Config.luau` and set `coinValue = 10`. Save. Studio updates
without you doing anything else. That loop — edit, save, play — is the job.

## Step 4 — Publish

In Studio: **File → Publish to Roblox As...**. Give it a name, and it's a real
game with a real URL you can send to people. Do this early and often; a rough
published game beats a perfect unpublished one.

---

## How the code is organised

```
default.project.json    Maps folders here → Roblox services. Rojo reads this.
rokit.toml              Pinned tool versions.
src/
  server/               → ServerScriptService. Trusted. Decides the score.
  client/               → StarterPlayerScripts. Runs on each player's machine.
  shared/               → ReplicatedStorage. Both sides can read it.
```

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

- **Save the score.** Right now it resets when you leave. `DataStoreService` is
  the fix, and it's the single biggest jump in making a game feel real.
- **Make the world.** Build geometry by hand in Studio — it's much faster than
  code for anything visual. Only the parts in `src/` need to live in git.
- **Add a goal.** A shop, a timer, a win condition. Coins with nothing to spend
  them on gets old in about thirty seconds.

Useful reading:

- Creator docs — <https://create.roblox.com/docs>
- Luau language — <https://luau.org/>
- Rojo — <https://rojo.space/docs/v7/>
