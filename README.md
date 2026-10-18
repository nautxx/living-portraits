# Living Portraits

Live 3D animated portraits for World of Warcraft unit frames. Your character breathes and idles like on the character screen. A companion addon for [BetterBlizzFrames](https://www.curseforge.com/wow/addons/betterblizzframes).

> Formerly **BBF Animated Portraits**. Upgrading? Delete the old `BBF_AnimatedPortraits` folder from AddOns (if it's still enabled, Living Portraits offers to disable it for you); settings start fresh under the new name. `/bap` still works as an alias for `/lp`.

> **Status:** v0.8.0, public test release. Tested in game on the **WoW Forever beta**, with and without BetterBlizzFrames. See [CHANGELOG](CHANGELOG.md).

## Best with BetterBlizzFrames

Living Portraits works on its own, but it's built to be used with [BetterBlizzFrames](https://www.curseforge.com/wow/addons/betterblizzframes) (BBF), and that's how it looks best.

| | Without BBF | With BBF |
|---|---|---|
| Style | Circle: the model inside Blizzard's round portrait | **Box**: a pixel-bordered box beside the bars (shown below), or circle if you keep BBF's portraits |
| Bars and names | Blizzard's default layout | Resized so the box and bars line up, name and level in one row |
| Extras | Bar text (`350 (462)` or `350 (76%)`) | Also talent builds, tall portraits, mirrored target text, gold/silver elite and rare borders, combo points under the bars and Edit Mode outlines that fit the portrait (box style only) |
| Setup | Nothing to do | One click: **Turn on** in the settings panel (or `/lp bbfsetup`) switches on BBF's Pixel Border mode |

## Screenshots

Switching targets: the bars grow from empty, each player's talent build appears above their name, and every portrait is a live 3D model.

![Cycling player targets: bars grow from empty, talent builds appear, and the portraits animate](docs/screenshots/target-grow.gif)

Tall portraits with Mirror Target Text, on BetterBlizzFrames' Pixel Border mode. The player and target frames mirror each other, and party frames get living portraits too:

| Player | Target and focus | Party |
|---|---|---|
| <img src="docs/screenshots/player-square.png" alt="Player frame with a tall living portrait, talent build 2/0/11 above the name, the resting Zzz after it, and bar text 412 (412) and 904 (904)" width="312"> | <img src="docs/screenshots/target-square.png" alt="Target Binjuice (0/25/0) and the small focus frame Deady (0/9/0), both mirrored, with bar text and their targets-of-target below" width="559"> | <img src="docs/screenshots/party-box.png" alt="Four party frames with tall living portraits, role and leader icons next to each name" width="228"> |

### Elite and rare targets

Elite and boss targets get a gold portrait and bar border, rares a silver one (both colors are adjustable). The elite icon takes the same color and sits on the portrait; the "??" skull takes the level's spot. Health and mana show as full numbers with the bar text option:

<img src="docs/screenshots/elite-box.png" alt="Lady Sylvanas Windrunner as the target: gold portrait and bar borders, gold elite icon on the portrait&#39;s corner, the boss skull next to her name, and health 1,428,900 (1,428,900)" width="348">

### Class resource

Combo points sit under the player's bars as pixel-bordered circles in the border color (or BetterBlizzFrames' own art, or hidden), lined up left, center or right of the mana bar, with your choice of size and color. The resting Zzz can sit after your name, as here, or over the portrait's top-right corner:

<img src="docs/screenshots/class-resource.png" alt="Player frame with five empty pixel-bordered combo point circles under the mana bar, aligned right, and the resting Zzz after the name" width="328">

## How it works

Instead of the flat 2D portrait, a live `PlayerModel` of the unit is drawn in one of two styles:

- **Box** (when BBF's No Portrait / Pixel Border mode is on): a box with BBF's 1px border beside the health and mana bars. The model fills it exactly.
- **Circle** (Blizzard's frames, or BBF with portraits): the model sits behind the frame's border ring, with a soft round edge so its square corners don't show.

In Edit Mode, the box style's selection outline, snap guide lines and click area cover the portrait box too, and the sample party frames shown while solo get empty boxes of the right size.

If the model can't load (unit out of range, not zoned in yet, or offline), the circle style steps aside and the normal portrait shows; the box style keeps an empty box so the bars stay lined up, and the model appears when they're back in range.

It **never modifies BetterBlizzFrames' files**. BBF is an optional dependency: when installed, this addon loads after it and follows its layout. The only BBF settings it ever changes are the No Portrait + Pixel Border switches, and only when you click **Turn on** (with Undo).

## Install

Download `LivingPortraits-<version>.zip` from the repo's Releases and unzip it into `World of Warcraft/<client>/Interface/AddOns/`.

Or from source:

1. Put this folder in `World of Warcraft/<client>/Interface/AddOns/`. **The folder must be named `LivingPortraits`** to match the `.toc`.
2. `/reload` or log in.

### Developing from a git checkout

Keep the repo elsewhere and symlink it into AddOns under the required name:

```sh
ln -s ~/GitHub/Main/living-portraits \
  "/Applications/World of Warcraft/_classic_beta_/Interface/AddOns/LivingPortraits"
```

(The WoW Forever beta installs into the `_classic_beta_` folder.)

## Settings

Open **Options → AddOns → LivingPortraits** (or type `/lp options`):

- **General:** turn it on/off, hide surnames, box or circle style, and which frames get a living portrait.
- **Camera:** zoom (both styles). Face distance is on each style's page.
- **Bar text:** Blizzard/BBF's own, or left-aligned `current (max)` / `current (percent)` that's always shown.
- **Target bars:** the grow-from-empty animation (target and focus) and its speed.
- **Box Style** (its own page): distance, talent builds, mirrored target text, tall portraits (player, target & focus, party), border color, thickness and opacity, elite/rare border and icon, the resting icon spot, class resource (combo points under the bars: pixel circles, BetterBlizzFrames' art or none, with alignment, size and colors), plus box and bar sizing.
- **Circle Style** (its own page): distance for large and small frames, background, round edge and model size.

The box style needs BetterBlizzFrames' **No Portrait + Pixel Border** mode. The **Turn on** button under *BetterBlizzFrames* switches it on for every frame (your other BBF settings stay as they are) and reloads the UI; **Undo** puts back what you had.

## Commands

`/lp` (or `/livingportraits`; the old `/bap` still works). Everything here is also in the settings panel.

**General**

| Command | Effect |
|---|---|
| `/lp` | Show current settings |
| `/lp options` | Open the settings panel |
| `/lp toggle` | Turn living portraits on/off |
| `/lp unit <group>` | Toggle a frame group: `player`, `target`, `focus`, `tot`, `party` |
| `/lp style box\|circle` | Box beside the bars (needs BBF's No Portrait / Pixel Border) or round portrait |
| `/lp surname` | First names only (hide surnames) on the player, target, focus, target-of-target and party frames |
| `/lp zoom 0-1` | Camera zoom (1 = head and shoulders, lower = more body) |
| `/lp cam 0.3-2 [large\|small\|box]` | Camera distance (lower = closer, bigger face) |
| `/lp bartext default\|max\|percent` | Health and mana text on the player, target, focus and party bars: Blizzard/BBF's own (default), or left-aligned and always shown as `350 (462)` (max) or `350 (76%)` (percent) |
| `/lp bartextstyle outline_shadow\|outline\|shadow\|thick\|thick_shadow` | Outline and shadow of the left-aligned bar text (default: thin outline + shadow); the font follows BetterBlizzFrames' unit frame number font |
| `/lp grow` | Toggle the target's and focus's health and mana growing from empty when they change |
| `/lp growtime 0.1-2` | How long the grow takes, in seconds (default 0.35) |
| `/lp bbfsetup` / `/lp bbfundo` | Turn on BBF's No Portrait + Pixel Border mode for every frame / put back your previous BBF settings (reload to apply) |
| `/lp reset` | Restore defaults |

**Box style**

| Command | Effect |
|---|---|
| `/lp build` | Toggle talent builds (points per tree, like `2/8/0`) on the player, target and focus |
| `/lp tall [player\|target\|party]` | Toggle tall portraits per group: a taller rectangle, with the build on its own line above the name on player, target and focus (off: square, build next to the level). On by default for all three. No group toggles player + target/focus together |
| `/lp mirror` | Mirror the target and focus text to match the player frame: name and build next to the portrait, level on the outer edge |
| `/lp eliteborder` | Toggle the gold (elite, boss) and silver (rare) portrait and bar borders on the target and focus (on by default) |
| `/lp elitecolor RRGGBB` / `/lp rarecolor RRGGBB` | Border colors for elite/boss (default `ffc71a`, gold) and rare (default `c7ccdb`, silver) targets |
| `/lp eliteicon top\|bottom\|center\|level\|hidden` | Where the target/focus elite icon goes: the portrait's outer top corner, outer bottom corner, bottom center (default), next to the level, or hidden |
| `/lp bordercolor RRGGBB` | Color of the 1px lines around the portrait box and the bars (default `000000`, black) |
| `/lp bordersize thin\|medium\|heavy` | Thickness of those lines: 1, 2 or 3px (default thin) |
| `/lp borderalpha 0-1` | Opacity of those lines (default 1). Below 1, the box and bars close up so no gap shows where a line was |
| `/lp bg 0-1` | Opacity of the dark background behind the model (default 0 = none) |
| `/lp extend 0-30 [large\|small]` | Make the health + mana stack taller; the box grows with it (default large 10, small 6) |
| `/lp namerow 0-24 [large\|tot\|party]` | Height of the name + level row above the health bar (default large 12, tot 9, party 0) |
| `/lp split 0.4-0.85` | Health bar's share of the stack (default 0.66; mana gets the rest) |
| `/lp alignmana` | Toggle lining up the mana bar with the health bar next to the box |
| `/lp gap 0-20` | Space between the box and the bars (1 = borders share one line) |
| `/lp barspacing 0-10` | Space between health and mana (0 = borders share one line) |
| `/lp resticon name\|corner` | Where the player's resting Zzz goes: after the name (default) or over the portrait box's top-right corner |
| `/lp resource pixel\|bbf\|none` | Class resource under the player's bars: pixel-bordered circles (default; gems for soul shards), BetterBlizzFrames' own combo point art, or hidden |
| `/lp resourcealign left\|center\|right` | Line the class resource up with the mana bar's left edge, middle (default) or right edge |
| `/lp resourcesize 2-16` | Circle radius inside the border (default 6); also scales BetterBlizzFrames' combo points |
| `/lp resourcecolor [combo\|shards\|arcane\|holy] RRGGBB` | Filled color per resource (defaults: red, purple, blue, gold); no resource = your class's |

**Circle style**

| Command | Effect |
|---|---|
| `/lp circlebg 0-1` | Opacity of the dark background inside the ring (0 = clear) |
| `/lp vignette` | Toggle the round edge that hides the model's square corners |
| `/lp inset 0.3-1.2 [large\|small]` | Model size relative to the portrait (default 0.80) |
| `/lp calibrate` | Tint the round edge red to line it up with the ring; toggle again to finish |
| `/lp offset <group> x y` | Nudge the portrait inside its ring (groups: player, target, focus, tot, party) |

**Troubleshooting**

| Command | Effect |
|---|---|
| `/lp refresh` | Re-apply the layout now (e.g. after changing BBF settings) |
| `/lp debug [unit]` | Print the frame's real positions, for bug reports (default: target) |
| `/lp grow debug` | Trace the bar grow in chat |

## Known limitations

- **Talent builds** only show for players within inspect range (about 30 yards), and the game may refuse to share enemy players' talents. NPCs never show one.
- **Target-of-target placement:** when the target or focus layout would run into its target-of-target (for example with Edit Mode's small focus frame), the ToT frame is moved down just enough to clear it, and put back when you switch to circle style or turn the addon off.
- **No layout changes in combat:** WoW blocks resizing unit-frame bars mid-fight, so box-style layout changes made in combat (settings, BBF re-layouts) are skipped and apply on the next refresh, such as a target change or `/lp refresh`. That's also why the build line stays reserved on NPC targets.
- **BBF's spec / healer icon portraits** are covered by the 3D model while it shows.
- **Class resource:** only rogue and druid combo points exist on WoW Forever as far as we can tell (Blizzard's own displays define nothing else), so warlock, mage and paladin show nothing until the game adds those resources.

## Feedback

Found a bug or have an idea? Open an issue: https://github.com/nautxx/living-portraits/issues. For layout bugs, `/lp debug target` output plus a screenshot helps a lot.

## Supported clients

| Client | Interface | Status |
|---|---|---|
| WoW Forever beta | 16001 | Supported |
| Retail | 120105 | Not yet |

## License

All Rights Reserved. Copyright (c) 2026 Jason Barnachea (nautxx). See [LICENSE](LICENSE).
Not affiliated with BetterBlizzFrames or Blizzard Entertainment.
