# Changelog

## 0.4.0 (2026-10-16)

### Features
- **Talent build:** the player and target frames show points per talent tree (like `2/8/0`). Your own build is read directly; other players are inspected when you target them (within ~30 yards). NPCs show nothing. Settings panel: *Show Talent Build*, or `/lp build`.
- **Tall portraits** (on by default): the player and target portraits grow into a taller rectangle, with the talent build on its own line above the name. The bars keep their size. Off: square portraits with the build next to the level. `/lp tall`.
- **Mirror Target Text:** the target and focus name and build sit next to the portrait and the level moves to the outer edge, so the target mirrors the player frame. `/lp mirror`.
- **Hide Surnames:** first names only on the player, target, focus, target-of-target and party frames. `/lp surname`.
- Settings panel: per-frame checkboxes are now *Player Portrait*, *Target Portrait*, and so on.
- `/lp` status shows the new settings.

### Performance
- The background check no longer re-processes names every half second, and the talent build does no work while it's off.

## 0.3.0 (2026-10-16)

**BBF Animated Portraits is now Living Portraits.**

### Upgrading from 0.2.x
- Install the new `LivingPortraits` folder and **delete the old `BBF_AnimatedPortraits` folder** from your AddOns. If the old one is still enabled, Living Portraits offers to disable it for you.
- Settings start fresh under the new name (the defaults are what most people use).
- The slash command is now `/lp` (or `/livingportraits`); `/bap` still works.

### Features
- **Settings panel:** Options → AddOns → LivingPortraits (or `/lp options`). Style, frames, camera, bar grow and all the square/circle tuning, in sync with the slash commands.
- **One-click BBF setup:** a button in the panel (or `/lp bbfsetup`) turns on BetterBlizzFrames' No Portrait + Pixel Border mode for every frame, which the square style needs. Your other BBF settings stay as they are, and Undo (`/lp bbfundo`) puts back what you had.
- New name, styled like BetterBlizzFrames in the AddOns list.

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
