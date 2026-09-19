# ForeverTools

World of Warcraft: Forever addon — fast loot, sell junk, auto-repair.

Version **1.0.2**. No libraries. Event-driven only.

## Install

Copy the `ForeverTools` folder into:

```
World of Warcraft/_classic_beta_/Interface/AddOns/ForeverTools/
```

The folder must contain only:

- `ForeverTools.toc`
- `ForeverTools.lua`

Restart the client (or `/reload` after the first copy). Open settings with `/ft` or `/forevertools`.

If the addon shows as out of date, enable **Load out of date AddOns**. The TOC targets Forever beta `16001` (and `120105`).

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

## Sell junk

Opens a vendor → greys are sold automatically. This uses the same `C_MerchantFrame.SellAllJunkItems` call as the vendor **Sell Junk** button, **without** the confirmation dialog. Hold Shift while talking to the vendor to skip.

## Versioning

Each release is committed on `main` and snapshotted on a `vX.Y.Z` branch. The TOC `Version` field matches that snapshot.

## Scope (v1)

In scope: fast loot, grey sell, repair, classic options panel.

Out of scope: auto-quest, auto-gossip, auto-res, minimap button, selling greens/whites, combat meters.

## Author

Geoff Walsh
