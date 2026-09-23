# Changelog

## 1.1.2 — 2026-09-22

- Party quests stay in ForeverTools. Dropped the extra slash command and the saved-settings import from the other party addon.

## 1.1.1 — 2026-09-22

- Junk summary uses each item's vendor price (stack included), not the change in your gold
- No more "Sold 1 junk for 0c" when repair or a secret gold value hid the real amount
- Counts the greys that actually left your bags

## 1.1.0 — 2026-09-22

- Party section: auto-accept NPC and party quests; share once from NPC pickup; auto-turn-in (stops on multiple rewards); announce full objectives in party/raid
- Hold Shift at a quest NPC to skip. `/fp accept|share|turnin|announce|status`
- Master enable still unregisters every feature, including party

## 1.0.3 — 2026-09-21

- Fast loot takes each corpse slot once. It no longer retries every 0.05s when bags are full
- Inventory-full error stops the loot pass for that window; slots reset on `LOOT_CLOSED`

## 1.0.2 — 2026-09-19

- Auto-sell junk uses `C_MerchantFrame.SellAllJunkItems` (the same call as the vendor Sell Junk confirm) so greys vendor without the confirmation click
- If that dialog still appears, it is accepted automatically while Sell junk is enabled
- Also listens for Forever's `PLAYER_INTERACTION_MANAGER_FRAME_SHOW` vendor event (not only `MERCHANT_SHOW`)
- TOC Interface set to `16001, 120105` so the Forever beta does not mark the addon out of date
- Secret-safe bag quality/price reads so Midnight-family clients do not error and skip the sell pass

## 1.0.1 — 2026-09-19

- Auto-sell junk actually sells on Forever's vendor UI
- Uses `C_MerchantFrame.SellAllJunkItems` so it does not wait on the confirmation click
- Grey detection no longer depends on bag quality/price being present
- Merchant session tracked from `MERCHANT_SHOW`/`CLOSED`

## 1.0.0 — 2026-09-19

First tagged build from the v1 spec.

- Fast loot when Auto Loot would already fire (Shift skip, master-loot threshold respected)
- Sell poor-quality vendor items, cap 11 per merchant visit
- Repair at merchants, optional guild funds first
- Classic dialog options panel (`/ft`, `/forevertools`)
- Account-wide SavedVariables only; no libraries
