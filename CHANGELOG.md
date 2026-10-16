# Changelog

## 0.1.0 (2026-10-15)

First release. Live 3D animated portraits (idle breathing, like the character screen) for Blizzard unit frames, as a companion to BetterBlizzFrames.

### Features
- Animated portraits on player, target, focus, target-of-target, focus-target and party frames.
- **Square style** (with BBF's No Portrait / Pixel Border modes): a pixel-bordered box beside the bars, the model fills it exactly.
  - Bar stack resized 2:1 health/mana so box and bars line up; name and level on one row inside the box.
  - Mana bar matched to the health bar's width and edges; bar text centered vertically.
  - Shared 1px border lines between box, health and mana.
  - NPCs without mana and BBF's hide-mana option handled.
- **Circle style** (Blizzard frames or BBF with portraits): model behind the frame ring with a soft round edge, centered per frame.
  - Optional clear background (`/bap circlebg`).
- Works with or without BetterBlizzFrames; never modifies BBF.
- Re-applies the layout after BBF rebuilds frames (fonts, names, bar text), target switches and Edit Mode / UI scale changes.
- Settings migrate automatically between versions.
- `/bap` commands for style, sizes, camera, offsets, per-frame toggles, `/bap refresh` and `/bap debug`.
