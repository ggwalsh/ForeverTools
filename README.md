# ForeverTools

World of Warcraft: Forever addon — fast loot, sell junk, auto-repair, party quests, invites, tooltips.

Version **1.2.0**. No libraries. Event-driven only. Two files.

## Install

Copy the `ForeverTools` folder into:

```
World of Warcraft/_classic_beta_/Interface/AddOns/ForeverTools/
```

The folder must contain only:

- `ForeverTools.toc`
- `ForeverTools.lua`

Restart the client (or `/reload` after the first copy). Open settings with `/ft` or `/forevertools`. `/fp` opens the same panel.

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
| Auto-accept quests | On |
| Share quests with party | On |
| Auto-turn-in quests | On |
| Announce objectives | On |
| Accept guild invites | On |
| Accept friend invites | On |
| Tooltips at cursor | On |
| Detailed tooltips | On |
| Show spell, item, and NPC IDs | On |

Hold **Shift** when opening a vendor, corpse, or quest NPC to skip automation once.

## Party

- Auto-accepts quests from NPCs and from party shares.
- Shares a quest **once** when you pick it up from an NPC — not from a party share, and not again while it is in your log.
- Announces in party/raid chat when a quest objective is full.
- Auto-turns in when you talk to the NPC. If there is more than one reward, it stops so you can choose.
- Accepts a manual group invite from a guild member or a character friend. Each has its own checkbox. Invites are left alone if you are already in a group.

`/fp` opens options. `/fp accept`, `/fp share`, `/fp turnin`, `/fp announce`, and `/fp status` toggle the quest options.

## Tooltips

- **Tooltips at cursor** moves the default tooltip (the one that sits in the bottom right) to the mouse.
- **Detailed tooltips** turns on the game's own enhanced tooltip (`UberTooltips`): cost, range, cast time, and the spell description with the damage numbers the client already fills in.
- **IDs** adds the spell, item, or NPC ID at the bottom of the tooltip.

There is no API for a spell-power coefficient breakdown (the "80% of spell power" math). That needs a spell database, not a toggle. Detailed tooltips show the numbers the game already calculates.

## Sell junk

Opens a vendor → greys are sold automatically. This uses the same `C_MerchantFrame.SellAllJunkItems` call as the vendor **Sell Junk** button, **without** the confirmation dialog. Hold Shift while talking to the vendor to skip.

## Versioning

Each release is committed on `main` and snapshotted on a `vX.Y.Z` branch. The TOC `Version` field matches that snapshot.

Repo: [ggwalsh/ForeverTools](https://github.com/ggwalsh/ForeverTools)

## Author

Geoff Walsh
