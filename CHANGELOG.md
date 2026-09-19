# Changelog

## 1.0.1 — 2026-09-19

- Auto-sell junk actually sells on Forever's vendor UI
- Uses `C_MerchantFrame.SellAllJunkItems` (the same call as the vendor Sell Junk button) so it does not wait on the confirmation click
- If that API still pops a confirm, the addon accepts the junk-sell dialog
- Grey detection no longer depends on bag quality/price being present (secret-value clients)
- Merchant session tracked from `MERCHANT_SHOW`/`CLOSED` instead of `MerchantFrame:IsShown()`

## 1.0.0 — 2026-09-19

First tagged build from the v1 spec.

- Fast loot when Auto Loot would already fire (Shift skip, master-loot threshold respected)
- Sell poor-quality vendor items, cap 11 per merchant visit
- Repair at merchants, optional guild funds first
- Classic dialog options panel (`/ft`, `/forevertools`)
- Account-wide SavedVariables only; no libraries
