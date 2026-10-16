# Changelog

## 0.2.1 (2026-10-16)

Public test release. Please report anything odd, especially in battlegrounds.

### Fixes
- Battlegrounds: targeting enemy players no longer floods Lua errors or leaves the target's health bar invisible after the bar grow. WoW hides some values (enemy health and its text) from addons in PvP; the grow and bar-text centering now skip them safely.

### Performance
- One target change no longer reloads the same 3D model two or three times: refresh requests are combined into one per frame.
- The bar grow no longer creates new garbage every frame, and the 0.5s background check does less work.

## 0.2.0 (2026-10-15)

### Features
- Target health and mana bars grow from empty when you pick a new target, keeping BBF's bar textures and class colors. On by default; `/bap grow` toggles it, `/bap growtime` sets the speed (default 0.35s).

### Fixes
- Square style: the name is left-aligned and the level right-aligned on every frame, whichever font BBF uses. Previously BBF's fixed-width, centered name box indented the name with Blizzard's default font.
- Target and focus now use the same name-left / level-right layout as the player frame.

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
