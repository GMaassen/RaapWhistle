# RaapWhistle

Ground-spawn quest objects (herbs, crates, bones, "search the wreckage" clickies) are
routinely buried under grass. RaapWhistle lowers the `graphicsGroundClutter` CVar on
demand so the spawns become visible, and puts it back when you are done — no video
options menu round-trip, no `/console` typing.

Mostly it does this by itself. Quest objectives are typed, and one of those types
is exactly what this addon exists for: **object** objectives are world objects you
click — the buried crate, the pile of bones, "search the wreckage". RaapWhistle
watches your quest log for those and lowers clutter while you are working on one.
You can also whitelist quest IDs by hand.

Restoring hands back **whatever you were running at**, captured on the way down —
not a configured constant — so the addon cannot quietly change your graphics
settings. It also restores on logout, since the CVar persists in the client config
and would otherwise follow you around even with the addon uninstalled.

## Supported versions

| Flavor | TOC | Interface |
| --- | --- | --- |
| Retail (Midnight) | `RaapWhistle_Mainline.toc` | 120100 |
| Classic Era | `RaapWhistle_Vanilla.toc` | 11509 |
| Burning Crusade Classic | `RaapWhistle_TBC.toc` | 20506 |
| Wrath Classic (3.4.5) | `RaapWhistle_Wrath.toc` | 30405 |
| anything else (fallback) | `RaapWhistle.toc` | multi-value |

`RaapWhistle.toc` is the generic fallback the client uses when no flavor-specific file
matches; it declares every currently live interface number, so Cataclysm and Mists
Classic are covered too.

## Installation

Copy the whole `RaapWhistle` folder into:

```
World of Warcraft/<flavor>/Interface/AddOns/
```

so that `Interface/AddOns/RaapWhistle/RaapWhistle.toc` exists. Restart the client (or
`/reload`) and enable RaapWhistle in the AddOns list.

The bundled `Ace3/` and `LibDBIcon-1.0/` directories must stay inside the addon
folder — they are loaded from the .toc, not as standalone addons.

## Usage

**Minimap button** — left-click toggles ground clutter between the low and high
values. The button can be dragged around the minimap and hidden via LibDBIcon.

**Peek** — the usual reason to want this is "let me see for twenty seconds".
`/raapwhistle peek` drops clutter and puts it back on its own, so you cannot forget
and leave the client on low grass. Peeking again while one is running extends it
rather than starting a second; a manual toggle cancels it; and if you walk into a
tracked quest zone mid-peek, clutter simply stays low.

**Keybinding** — Game Menu → Key Bindings → RaapWhistle → *Toggle Ground Clutter*
and *Peek Ground Clutter*. Both unbound by default.

**Slash command** — `/raapwhistle`:

| Command | Effect |
| --- | --- |
| `/raapwhistle` | opens the options panel |
| `/raapwhistle toggle` | toggles ground clutter now |
| `/raapwhistle peek [seconds]` | lowers clutter briefly, then restores it (default 20s) |
| `/raapwhistle add [quest log index]` | adds a quest to the whitelist; with no index, uses the quest currently selected in the quest log |
| `/raapwhistle remove <questId>` | removes a quest ID from the whitelist |
| `/raapwhistle list` | prints the tracked quest IDs, marking the auto-detected ones |
| `/raapwhistle ignore <questId>` | stops tracking a quest and stops re-detecting it |
| `/raapwhistle unignore <questId>` | undoes that |
| `/raapwhistle zones <questId>` | prints the zones learned for a quest |
| `/raapwhistle zones <questId> clear` | forgets them, so they can be learned again |

## Options

Interface → AddOns → RaapWhistle:

- **Auto Clutter Toggle** — automatically lower clutter while a whitelisted quest is
  active in one of its learned zones, and restore it when it is not.
- **Low Clutter Value** (0–9) — the value used when clutter is reduced. 0 is the
  clearest. Always kept below the high value; the two meeting would leave the addon
  unable to tell the states apart.
- **Peek Duration** — how long `/raapwhistle peek` and the peek keybinding last.
- **Restore To** — *Whatever it was before* (default) hands back the value captured
  when clutter was lowered. *The High Clutter Value* restores a fixed number instead.
- **High Clutter Value** (0–9) — only used when **Restore To** is set to the fixed
  value, and disabled otherwise.
- **Detect Search Quests** (on) — track quests that have an object objective,
  without you having to add anything.
- **Also Detect Collection Quests** (off) — see below.
- **Quest Whitelist** — comma-separated quest IDs tracked by hand. These are never
  touched by detection and survive it being switched off.

### What gets detected

Only **object** objectives by default. Ground spawns that count *items* report as
`item`, and so does every "collect 8 murloc fins" quest where the fins drop from
kills — matching those would dim the grass nearly everywhere and defeat the point.
**Also Detect Collection Quests** turns that broader match on if you would rather
have the recall than the precision.

I have not been able to check this against a live client, so which of the two is
right for the spawns you care about is genuinely open. The setting is there so it
is your call rather than a guess baked into the code.

Detection will occasionally be wrong. `/raapwhistle ignore <questId>` is the veto —
without it the only remedy would be switching the whole feature off. Auto-detected
entries show as `(auto)` in `/raapwhistle list`, and adding one by hand converts it
to a manual entry.

### Zones

A whitelisted quest only lowers clutter in zones it has been *seen* in, so a quest
in your log does not dim grass across the world.

`/raapwhistle add` learns the zone you are standing in immediately — you asked for
it explicitly. Auto-detected quests always learn passively, so expect roughly half a
minute in the right zone before clutter drops; add the quest by hand if you want it
now. Passive learning works the same either way: a zone counts only once you
are still in it 30 seconds later, so flying over somewhere on the way to an objective
never gets it tracked. A quest holds at most 8 zones. `/raapwhistle zones <questId>
clear` resets them if one is learned wrongly.
- **Profiles** — standard AceDB profile management; settings live in
  `RaapWhistleDB`.

## Development

The addon can be exercised outside the game against a mock client, which is useful
when you don't have WoW installed. Requires a standalone Lua 5.x on PATH.

    lua tests/run_tests.lua
    lua tests/check_toc.lua

`tests/wow_env.lua` fakes the client API and can present either the Wrath Classic
3.4.x surface (`GetQuestLogTitle` / `GetQuestLogSelection`) or the retail one
(`C_QuestLog`), with options to drop `C_Timer`, drop LibStub entirely, cap the
clutter CVar the way a client would, or make `SetCVar` fail. The AceDB test loads
the real vendored `Ace3/AceDB-3.0`.

`tests/check_toc.lua` is a static pass over the `.toc` manifests: every listed file
must exist, every flavor must load the same files in the same order, and the
declared interface numbers and `## SavedVariables` must be well formed. This is the
failure that made the addon dead on arrival — Ace3 sat in the repo, referenced by
nothing — so it is worth catching mechanically.

Both run on every push and pull request (`.github/workflows/tests.yml`), against
Lua 5.1 (what the game runs) and 5.4.

These cover the addon's own logic. They do **not** verify the real Blizzard event
payloads or the true range of `graphicsGroundClutter` — those still need a live
client.

## Releases

Pushing a `v*` tag builds the addon zip and attaches it to a GitHub release, via
the [BigWigs packager](https://github.com/BigWigsMods/packager):

    git tag -a v0.2.0 -m "v0.2.0" && git push origin v0.2.0

`.pkgmeta` keeps `tests/` and `.github/` out of the shipped zip. Uploading to
CurseForge, WoWInterface or Wago happens only if `CF_API_KEY`, `WOWI_API_TOKEN` or
`WAGO_API_TOKEN` are set as repository secrets; without them the workflow just
builds the zip, which is all a personal addon needs.

## Third-party libraries

`Ace3/` and `LibDBIcon-1.0/` are vendored, unmodified copies of third-party
libraries and are distributed under their own licenses (see `Ace3/LICENSE.txt` and
the LibDBIcon source headers). They are not covered by this addon's license.

## License

MIT - see `LICENSE`. This covers the addon itself (`RaapWhistle.lua`, the `.toc`
files, `Bindings.xml`, and `tests/`), not the vendored libraries above.
