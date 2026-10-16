# BBF Animated Portraits

Live 3D animated portraits for World of Warcraft unit frames. Your character breathes and idles like on the character screen. A companion addon for [BetterBlizzFrames](https://www.curseforge.com/wow/addons/betterblizzframes).

> **Status:** v0.2.0, early release. Tested in game on the Classic beta ("Camelot") client, with and without BetterBlizzFrames. See [CHANGELOG](CHANGELOG.md).

## Screenshots

Switching targets: the health and mana bars grow from empty, and each portrait is a live 3D model.

![Cycling targets: bars grow from empty and the portraits animate](docs/screenshots/target-grow.gif)

Square style with BetterBlizzFrames' Pixel Border mode:

| Player | Target and target-of-target |
|---|---|
| ![Player frame with an animated square portrait](docs/screenshots/player-square.png) | ![Target and target-of-target frames with animated square portraits](docs/screenshots/target-square.png) |

## How it works

Instead of the flat 2D portrait, a live `PlayerModel` of the unit is drawn inside the portrait circle, behind the frame's border ring, with a soft vignette so the model's square edges don't show. If the model can't load (unit out of range, offline, or a BBF "no portrait" mode is on), the addon steps aside and the normal portrait shows.

It **does not modify BetterBlizzFrames**. BBF is an optional dependency: when installed, this addon loads after it and follows BBF's portrait sizing automatically.

## Install

Download `BBF_AnimatedPortraits-<version>.zip` from the repo's Releases and unzip it into `World of Warcraft/<client>/Interface/AddOns/`.

Or from source:


1. Put this folder in `World of Warcraft/<client>/Interface/AddOns/`. **The folder must be named `BBF_AnimatedPortraits`** to match the `.toc`.
2. `/reload` or log in.

### Developing from a git checkout

Keep the repo elsewhere and symlink it into AddOns under the required name:

```sh
ln -s ~/GitHub/Main/bbf-animated-portraits \
  "/Applications/World of Warcraft/_classic_beta_/Interface/AddOns/BBF_AnimatedPortraits"
```

## Commands

| Command | Effect |
|---|---|
| `/bap` | Show current settings |
| `/bap toggle` | Turn animated portraits on/off |
| `/bap zoom 0-1` | Camera zoom (1 = head and shoulders, lower = more body) |
| `/bap inset 0.3-1.2 [large\|small]` | Model size relative to the portrait (0.72 keeps corners under the ring; the circle edge follows it) |
| `/bap cam 0.3-2 [large\|small]` | Camera distance (lower = closer, bigger face) |
| `/bap calibrate` | Circle: tint the circle edge red to line it up with the ring; toggle again to finish |
| `/bap offset <group> x y` | Circle: nudge the portrait inside its ring (groups: player, target, focus, tot, party) |
| `/bap grow` | Toggle the health and mana bars growing from empty when you pick a new target (`/bap grow debug` traces it in chat) |
| `/bap growtime 0.1-2` | How long the target bar grow takes, in seconds (default 0.35) |
| `/bap vignette` | Toggle the crisp circle edge that hides the model's square edges |
| `/bap style square\|circle` | Square box beside the bars (needs BBF No Portrait / Pixel Border) or round portrait |
| `/bap bg 0-1` | Square: opacity of the dark background behind the model (default 0 = none) |
| `/bap extend 0-30 [large\|small]` | Square: make the health+mana stack taller; the box grows with it and stays aligned (default large 10, small 6) |
| `/bap namerow 0-24 [large\|tot\|party]` | Square: height of the name + level row inside the box, above the health bar (default large 12, tot 9, party 0) |
| `/bap split 0.4-0.85` | Square: health bar's share of the stack (default 0.66, mana gets the rest) |
| `/bap alignmana` | Square: toggle lining up the mana bar with the health bar next to the box (undoes live) |
| `/bap gap 0-20` | Square: space between the box and the bars (1 = borders share one line) |
| `/bap barspacing 0-10` | Square: space between health and mana (0 = borders share one line) |
| `/bap unit <group>` | Toggle a frame group: `player`, `target`, `focus`, `tot`, `party` |
| `/bap reset` | Restore defaults |
| `/bap refresh` | Re-apply the layout now (e.g. after changing BBF settings) |
| `/bap debug [unit]` | Print the frame's real positions, for bug reports (default: target) |

## Supported clients

| Client | Interface | Status |
|---|---|---|
| Classic beta ("Camelot") | 16001 | Supported |
| Retail | 120105 | Not yet |

## Releasing

1. Bump `## Version` in the `.toc` and add a `CHANGELOG.md` entry.
2. Commit, then tag: `git tag -a v<version> -m "v<version>"`.
3. `tools/package.sh` builds `dist/BBF_AnimatedPortraits-<version>.zip` (only the files WoW needs).
4. `git push --follow-tags`, then attach the zip to a GitHub release.

## License

All Rights Reserved. Copyright (c) 2026 Jason Barnachea (nautxx). See [LICENSE](LICENSE).
Not affiliated with BetterBlizzFrames or Blizzard Entertainment.
