# RaapWhistle

Ground-spawn quest objects (herbs, crates, bones, "search the wreckage" clickies) are
routinely buried under grass. RaapWhistle lowers the `graphicsGroundClutter` CVar on
demand so the spawns become visible, and puts it back when you are done — no video
options menu round-trip, no `/console` typing.

It can also do this automatically: put a quest ID on the whitelist and RaapWhistle
drops clutter while that quest is active, restoring it afterwards.

## Supported versions

| Flavor | TOC | Interface |
| --- | --- | --- |
| Retail (Midnight) | `RaapWhistle_Mainline.toc` | 120100 |
| Classic Era | `RaapWhistle_Vanilla.toc` | 11509 |
| Burning Crusade Classic | `RaapWhistle_TBC.toc` | 20506 |
| Wrath / Titan Reforged | `RaapWhistle_Wrath.toc` | 38002 |
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

**Keybinding** — Game Menu → Key Bindings → RaapWhistle → *Toggle Ground Clutter*.
Unbound by default.

**Slash command** — `/raapwhistle`:

| Command | Effect |
| --- | --- |
| `/raapwhistle` | opens the options panel |
| `/raapwhistle toggle` | toggles ground clutter now |
| `/raapwhistle add [quest log index]` | adds a quest to the whitelist; with no index, uses the quest currently selected in the quest log |
| `/raapwhistle remove <questId>` | removes a quest ID from the whitelist |
| `/raapwhistle list` | prints the whitelisted quest IDs |

## Options

Interface → AddOns → RaapWhistle:

- **Auto Clutter Toggle** — automatically lower clutter while a whitelisted quest is
  active in its zone, and restore it when it is not.
- **Low Clutter Value** (0–9) — the value used when clutter is reduced. 0 is the
  clearest.
- **High Clutter Value** (0–9) — the value restored afterwards. Set this to whatever
  your normal graphics preset uses (9 on Ultra).
- **Quest Whitelist** — comma-separated quest IDs that drive the automatic toggle.
- **Profiles** — standard AceDB profile management; settings live in
  `RaapWhistleDB`.

## Development

The addon can be exercised outside the game against a mock client, which is useful
when you don't have WoW installed. Requires a standalone Lua 5.x on PATH.

    lua tests/run_tests.lua

`tests/wow_env.lua` fakes the client API and can present either the Wrath Classic
3.4.x surface (`GetQuestLogTitle` / `GetQuestLogSelection`) or the retail one
(`C_QuestLog`), with options to drop `C_Timer`, drop LibStub entirely, cap the
clutter CVar the way a client would, or make `SetCVar` fail. The AceDB test loads
the real vendored `Ace3/AceDB-3.0`.

These cover the addon's own logic. They do **not** verify the real Blizzard event
payloads or the true range of `graphicsGroundClutter` — those still need a live
client.

## Third-party libraries

`Ace3/` and `LibDBIcon-1.0/` are vendored, unmodified copies of third-party
libraries and are distributed under their own licenses (see `Ace3/LICENSE.txt` and
the LibDBIcon source headers). They are not covered by this addon's license.

## License

MIT - see `LICENSE`. This covers the addon itself (`RaapWhistle.lua`, the `.toc`
files, `Bindings.xml`, and `tests/`), not the vendored libraries above.
