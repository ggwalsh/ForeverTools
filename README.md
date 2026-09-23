# ForeverTools

World of Warcraft: Forever addon — fast loot, sell junk, auto-repair, party quests.

Version **1.1.1**. No libraries. Event-driven only. Two files.

## Install

Copy the `ForeverTools` folder into:

```
World of Warcraft/_classic_beta_/Interface/AddOns/ForeverTools/
```

The folder must contain only:

- `ForeverTools.toc`
- `ForeverTools.lua`

**Disable or delete `Interface/AddOns/ForeverParty`.** Those features now live in ForeverTools. Leaving both enabled double-accepts quests.

Restart the client (or `/reload` after the first copy). Open settings with `/ft` or `/forevertools`. `/fp` and `/foreverparty` still work.

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

Hold **Shift** when opening a vendor, corpse, or quest NPC to skip automation once.

## Party (from ForeverParty)

- Auto-accepts quests from NPCs and from party shares.
- Shares a quest **once** when you pick it up from an NPC — not from a party share, and not again while it is in your log.
- Announces in party/raid chat when a quest objective is full.
- Auto-turns in when you talk to the NPC. If there is more than one reward, it stops so you can choose.

If `ForeverPartyDB` is still loaded (ForeverParty enabled for one session), those four toggles copy into `ForeverToolsDB` before defaults fill in.

```
/fp                 open options (same as /ft)
/fp status          print party toggles
/fp accept          toggle auto-accept
/fp share           toggle auto-share
/fp turnin          toggle auto-turn-in
/fp announce        toggle objective chat
```

## Sell junk

Opens a vendor → greys are sold automatically. This uses the same `C_MerchantFrame.SellAllJunkItems` call as the vendor **Sell Junk** button, **without** the confirmation dialog. Hold Shift while talking to the vendor to skip.

## Versioning

Each release is committed on `main` and snapshotted on a `vX.Y.Z` branch. The TOC `Version` field matches that snapshot.

Repo: [ggwalsh/ForeverTools](https://github.com/ggwalsh/ForeverTools)

## Author

Geoff Walsh
