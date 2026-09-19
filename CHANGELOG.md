# Changelog

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
