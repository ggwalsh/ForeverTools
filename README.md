# ForeverTools

World of Warcraft: Forever addon — fast loot, sell junk, auto-repair.

Version **1.0.1**. No libraries. Event-driven only.

## Install

Copy the `ForeverTools` folder into:

```
World of Warcraft/_classic_beta_/Interface/AddOns/ForeverTools/
```

The folder must contain only:

- `ForeverTools.toc`
- `ForeverTools.lua`

Restart the client (or `/reload` after the first copy). Open settings with `/ft` or `/forevertools`.

## Defaults

| Toggle | Default |
|---|---|
| Enable ForeverTools | On |
| Fast loot | On |
| Require Auto Loot setting | On |
| Sell junk (poor quality) | On |
| Repair gear | On |
| Prefer guild funds | Off |
| Print summary in chat | On |

Hold **Shift** when opening a vendor or corpse to skip automation once.

## Versioning

Each release is committed on `main` and snapshotted on a `vX.Y.Z` branch. The TOC `Version` field matches that snapshot.

## Scope (v1)

In scope: fast loot, grey sell, repair, classic options panel.

Out of scope: auto-quest, auto-gossip, auto-res, minimap button, selling greens/whites, combat meters.

## Author

Geoff Walsh
