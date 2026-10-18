# Changelog

## Unreleased

### Features
- **Class name:** show players' class in its class color on the player, target and focus frames, for when health bars aren't class colored. Pick where: next to the talent build (`Warrior 2/8/0`), above the level, or after the name. Off by default. Settings → General → *Class Name*, or `/lp classtext off|build|level|name`. In circle style (no build line) it goes after the name.

## 0.9.0 (2026-10-18)

### Features
- **Profiles:** load a whole look, Living Portraits and BetterBlizzFrames settings together, in one click, from the new **Profiles** page (Options → AddOns → Living Portraits → Profiles):
  - **Starter:** a clean starting point. Square box portraits with the gold/silver elite border, full names, no talent builds and Blizzard's bar text, on BetterBlizzFrames' own Starter profile with Pixel Border mode.
  - **Naut:** the author's full look. BetterBlizzFrames' Bodify profile with Pixel Border mode and his unit frame look: fonts, textures, class colors, combo points under the player frame, target-of-target placement, less clutter.
  - **BlizzFrames:** living portraits in the round portrait, on BetterBlizzFrames' Forever profile (its Classic Frames look), with bigger player, target and focus models.
  - **Export / Import:** your setup as a text string, to copy to another PC or share.

  Loading or importing replaces both addons' settings; **Undo** puts them back. `/lp profile starter|naut|blizzframes`, `/lp export`, `/lp import`.
- **Welcome on a fresh install:** if BetterBlizzFrames isn't set up for the box portraits yet, Living Portraits offers Starter or Naut once (or recommends BetterBlizzFrames when it isn't installed).

- **One confirmation:** loading a profile, importing, turning on Pixel Border mode and Undo each ask once (what it overwrites, and that it reloads), then reload right away on Yes. Profile buttons show their names in class colors.
- **Addon list icon** for Living Portraits.

### Changes
- **Pixel Border mode** (was *Set up BetterBlizzFrames*, on the Profiles page, `/lp bbfsetup`) only turns on the No Portrait + Pixel Border switches the box style needs and keeps the rest of your BetterBlizzFrames settings. The unit frame look moved into the Naut profile.
- README: a Profiles section (what each profile sets up, the overwrite and Undo note, sharing) with screenshots of the BlizzFrames profile.

### Fixes
- **Pixel Border mode** now turns off BetterBlizzFrames' Classic Frames, which overrides it: with Classic Frames on, the frames stayed classic. Living Portraits also treats Classic Frames as "portraits shown" (circle style) instead of laying out boxes BetterBlizzFrames isn't drawing.

## 0.8.1 (2026-10-18)

### Changes
- **New defaults** (Jason's own setup): bar text `350 (462)` with a shadow, elite icon on the portrait's bottom corner, elite/rare borders off, resting Zzz on the portrait's corner, class resource right-aligned at radius 5. Existing installs move to these only where a setting still has the old default; anything you changed stays.

### Features
- **Set up BetterBlizzFrames in one click:** the settings button (was *Turn on Pixel Border mode*, `/lp bbfsetup`) now also applies the unit frame look Living Portraits is designed for: fonts, bar textures, class colors, combo points under the player frame, target-of-target placement, and less clutter around the portrait. Auras, cast bars, action bars, chat, minimap and dark mode are left alone. **Undo** puts everything back.

## 0.8.0 (2026-10-18)

### Features
- **Class resource under the bars:** in box style, BetterBlizzFrames' combo points ("Move Combo Points under PlayerFrame") no longer cover the mana bar. They sit under the player's bars as pixel-bordered circles in the border color and thickness, or as BetterBlizzFrames' own art, or hidden. Choose the alignment (left, center or right of the mana bar), the size (it scales BetterBlizzFrames' art too) and a color per resource. BetterBlizzFrames' "hide when empty" and "only show filled" still apply. Warlock soul shards (as gems), mage arcane charges and paladin holy charges are supported if WoW Forever ever gives those classes the resource. Settings → Box Style → Class resource, or `/lp resource pixel|bbf|none`, `/lp resourcealign`, `/lp resourcesize`, `/lp resourcecolor`.
- **Resting icon placement:** the Zzz can sit after your name (default) or over the portrait box's top-right corner. `/lp resticon name|corner`.

### Fixes
- **Edit Mode:** the player, target, focus and party selection boxes now include the portrait boxes. The red snap guide lines, snapping and clicking follow that outline too.
- **Edit Mode party frames:** the sample party frames shown while solo get empty portrait boxes of the right size, and their health and mana bars no longer have a gap.

### Changes
- README: class resource section with a screenshot, plus the new commands and Edit Mode behavior.

## 0.7.1 (2026-10-18)

### Changes
- **Bar text shows full numbers:** `1,428,900 (1,428,900)` instead of `1428 K`, with thousands separators. Still works in dungeons and battlegrounds.
- README: party frame and elite target screenshots, sharper player and target screenshots, and an Elite and rare targets section.

## 0.7.0 (2026-10-18)

### Features
- **Bar text:** health and mana as `350 (462)` (current and max) or `350 (76%)` (current and percent), left-aligned and always shown on the player, target, focus and party bars. Works in dungeons and battlegrounds. Choose its look with *Bar Text Style* (outline, shadow, thick outline, or a mix); the font follows BetterBlizzFrames' unit frame number font. `/lp bartext`, `/lp bartextstyle`.
- **Elite and rare targets:** the target and focus portrait and bar borders turn gold (elite, boss) or silver (rare), with colors you can pick. The small elite icon takes the same color and can sit on the portrait's corner, bottom center (default), next to the level, or be hidden. `/lp eliteborder`, `/lp elitecolor`, `/lp rarecolor`, `/lp eliteicon`.
- **Tall portraits per group:** player, target and focus, and party each have their own switch (party is new). `/lp tall [player|target|party]`.
- **Settings panel:** Box Style and Circle Style now have their own pages, each with its own camera distance.
- **Square style is now called Box style** (tall portraits made most boxes rectangles). Your settings carry over; `/lp style box` works, and `square` still does.
- New installs start with mirrored target text, hidden surnames and tall party portraits on.

### Fixes
- **Icons off the portrait:** the player's combat and resting icons sit after the name, party role, leader and disconnect icons sit by the name and in the box, and the target's "??" skull sits where the level goes.
- **Dungeons:** no more Lua errors from the target bar animation, party portraits appear as members zone in, and members who aren't loaded in yet keep the same bar layout (empty box).
- **Battlegrounds:** fewer refresh retries while bar positions are hidden (less lag).
- Turning the addon off or switching to circle style now puts every moved icon and text back.
- Old saved settings from earlier test builds are cleaned up.

## 0.6.0 (2026-10-16)

### Features
- **Focus frame catches up with the target:** tall portrait, talent build above the name, and health and mana growing from empty when you set a new focus.
- **Border Thickness:** Thin, Medium or Heavy (1, 2 or 3px) for the lines around the portrait box and BetterBlizzFrames' bars (Settings → Square style, or `/lp bordersize thin|medium|heavy`). Shared lines stay single and corners are drawn once at every thickness.

### Fixes
- **Target-of-target overlap:** with Edit Mode's small focus frame, the focus-target ran into the focus box. The target-of-target is now moved down just enough to clear the target or focus layout, and put back when you switch to circle style or turn the addon off.
- **Talent builds for target and focus together:** inspecting both no longer cancels one of them; a player who doesn't answer an inspect is retried after 30 seconds.

## 0.5.0 (2026-10-16)

### Features
- **Border Color and Border Opacity** (Settings → Square style, or `/lp bordercolor RRGGBB` and `/lp borderalpha 0-1`): one color and opacity for the 1px lines around the portrait box and BetterBlizzFrames' health and mana bars. Lines that two pieces share are drawn once, so partial opacity looks even. Circle style and turning the addon off give BBF its black borders back.

### Fixes
- Below full border opacity, the bars and box close up instead of leaving a 1px slot that showed the world through between health and mana on some frames (like the target).

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
