# BBF Animated Portraits

Live 3D animated portraits for World of Warcraft unit frames. Your character breathes and idles like on the character screen. A companion addon for [BetterBlizzFrames](https://www.curseforge.com/wow/addons/betterblizzframes).

> **Status:** early development. Player frame only (step 1, untested in game).

## How it works

Instead of the flat 2D portrait, a live `PlayerModel` of the unit is drawn over the portrait circle on a dark, circle-masked background. If the model can't load (unit out of range, offline, or a BBF "no portrait" mode is on), the addon steps aside and the normal portrait shows.

It **does not modify BetterBlizzFrames**. BBF is an optional dependency: when installed, this addon loads after it and follows BBF's portrait sizing automatically.

## Install

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
| `/bap inset 0.3-1.2` | Model size relative to the portrait (~0.72 fits inside the circle) |
| `/bap reset` | Restore defaults |

## Supported clients

| Client | Interface | Status |
|---|---|---|
| Classic beta ("Camelot") | 16001 | Target |
| Retail | 120105 | Not yet |

## License

All Rights Reserved. Copyright (c) 2026 Jason Barnachea (nautxx). See [LICENSE](LICENSE).
Not affiliated with BetterBlizzFrames or Blizzard Entertainment.
