# Crafter's Journal

A World of Warcraft: Forever addon to **level every profession the cheapest way** and keep track of your **recipe collection**.

- Cheapest route from your current skill to the cap, step by step, with real Auction House prices.
- Trainers by rank, with a waypoint to the nearest one.
- Every recipe of each profession: which you know, which you can learn now, and where to get the rest.
- English, Spanish and German.

Download it from CurseForge (link coming soon).

## Development

- The addon code is this folder. In WoW, `Interface\AddOns\CraftersJournal` can be a directory junction to it.
- Data is generated from the WoW Forever client tables (wago.tools), CMaNGOS and QuestieDB: `python tools/build_data.py` regenerates `Data/` and runs the tests.
- Recipe and item names in Spanish and German come from the Forever client tables in those languages: `python tools/fetch_names.py esES deDE` downloads them from wago.tools (needs internet) and `python tools/gen_names.py` generates `Data/Names_<locale>.lua` (and adds it to the `.toc`). On a client that runs in the addon's language, recipe names come from the game itself.
- `python tools/check_data.py` compares `Data/*.lua` with the client tables in `tools/wago` (names, reagents, crafted items, skill thresholds, recipe scrolls and prices).
- `python tools/package.py` builds the release zip in `dist/` (the same as the CurseForge packager: no `tools/` or `docs/`, development mode off).
- Features in progress are only visible in development mode (`ES.DEV`, see `Core.lua`). Releases are published by `.github/workflows/release.yml` when a `v*` tag is pushed.
- Roadmap: `docs/PLAN.md` (in Spanish).
