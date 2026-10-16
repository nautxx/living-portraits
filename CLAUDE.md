# Project notes: BBF Animated Portraits

Context for anyone (human or AI) picking up this project.

## Goal
Make Blizzard unit-frame portraits show a live 3D model with the idle "breathing"
animation, like the character screen, as a **companion addon** to BetterBlizzFrames (BBF).

## Key decisions
| Decision | Choice | Why |
|---|---|---|
| Fork BBF vs companion | **Companion addon** | BBF is "All Rights Reserved" (Bodify), so it can't be redistributed. Editing BBF directly is also wiped on every BBF update. |
| BBF dependency | `OptionalDeps` | Loads after BBF so we see its portrait resizing; still works without BBF. |
| Render approach | `PlayerModel` + `SetUnit()` + `SetPortraitZoom()` | Idle animation plays automatically. ModelScene (char screen) is heavier with no masking benefit. |
| Circle problem | **Model behind the ring + vignette** (option B) | Mask textures can't clip Model frames. First in-game test (inscribed square above the ring) showed hard square cut lines and a small face. Now the model sits under Blizzard's border ring, which hides its corners, and a vignette hides its straight edges. Rejected: tuning only (cut lines stay visible), square portrait art (big restyle). |
| Square style | **Default when BBF No Portrait / Pixel Border is on** | A square box can't have masking problems: the model fills it exactly. Box = BBF's 1px black pixel border recipe, anchored beside the bars (`UNITS[unit].bars` / `.side`), height = health top to mana bottom. Bigger box = taller bar stack (`stackExtra` large 10 / small 6, split `hpShare` 0.66 health / rest mana), so box and bars always align. A name row (`nameRow` large 12 / tot 9 / party 0, grouped by `UNITS[unit].row`) sits inside the box above the health bar: name + level on one line (every frame: name left, level right; ToT: no level), pinned via a `SetPoint` hook. Each pinned text's box shrinks to its text width (re-fit on `SetText`/`SetFont`/`SetWidth`, name capped short of the level): BBF gives names a fixed-width box and the player's `bbfName` ignores later `SetJustifyH` (stays centered), which indented the name with Blizzard's default font so BBF re-positioning doesn't move them (BBF's `bbfName` follows the real name automatically). Bar texts are re-centered vertically in their bars (`CenterBarTexts`; BBF's fixed y offsets were tuned for the thin bars). Falls back to circle where BBF still shows portraits. Boxes are parented to the **unit frame** (`UNITS[unit].frame`), never via the portrait: BBF's No Portrait mode reparents the player container and ToT/party portraits to a hidden frame. `LayoutBars` resizes health and mana (bar + BBF posFrame, which carries border/bg/mask), keeps each top edge fixed whatever its anchor point, moves mana down by the health growth (unless it's anchored to the health bar, e.g. ToT), and with `alignMana` shifts it to line up with the health bar on the box side (Blizzard offsets target/focus mana ~8px). Original anchor/heights are stored on the bar/text and restored by `RestoreBars` (circle style, disabled, extend 0). Out of combat only. |
| Rounded corners | **No: keep square** | Matches BBF's Pixel Border style exactly. Rejected: rounded box only (3D model corners can't be clipped, would peek past the curve) and rounded box + bars (needs custom border/mask art and takes over BBF's bar styling; fragile across BBF updates). |
| Touching Blizzard's portrait | **Hide only, never alter** | Hidden while the model shows, restored after. Never change its texture, alpha or color (Blizzard changes those itself). |
| Repo location | `~/GitHub/Main/bbf-animated-portraits`, symlinked into AddOns as `BBF_AnimatedPortraits` | The beta client folder is temporary. One repo can feed multiple clients. |

## Architecture (Core.lua)
- `UNITS[unit]` describes each unit in one place: layout groups (`size` large/small, `offset`, `row`, `side`) and frame lookups (`frame()`, then `portrait`/`ring`/`bars`/`texts`, each taking the unit frame). **Add new units here** (and to `UNIT_LIST`, the fixed iteration order). Read lookups with `Lookup(unit, key)` / `UnitFrameOf(unit)`.
- `GROUPS` maps slash-command names (`player`, `target`, `focus`, `tot`, `party`) to units.
- **Layering (bottom to top)**, all created by `CreateLayers(unit)`:
  1. `bgFrame` (child of the unit frame root, level = container − 2): dark circle with its own mask (`TempPortraitAlphaMask`).
  2. `model` (child of root, level = container − 1): `PlayerModel` square sized `portrait × sizes[large|small].inset` (0.72). At 0.72 its corners stay under the ring's outer edge.
  3. Blizzard's container: the 2D portrait (hidden while active), our `vignette` texture (same sublevel as the portrait, `media/vignette.tga`) and the border ring art (one sublevel up). The ring covers the model's corners; the vignette is a **crisp circle edge** at the model's straight edges (`VIGNETTE_EDGE` = 0.72, scaled with inset, capped at portrait size), with a dark band out to the ring.
- Circle edge: `vignette.tga` is an inverted disc (clear inside, soft fade over the last 12% of the radius, opaque corners) sized exactly like the model, so it rounds off the model's square without extending past it. The dark area out to the ring is `bgFrame` (portrait-sized circle, under the ring). Earlier versions scaled a band past the model and it peeked outside the ring.
- Centering: `offsets[player|target|focus|tot|party]` nudge model, edge and backing together (`/bap offset`; defaults measured in game from a calibrate screenshot by fitting circles to the red edge and the ring's inner edge: player (-0.5, 0.6), target/focus (0.6, 0.3), ToT (-1.3, 2.2), party unmeasured); `/bap calibrate` tints the edge red to line it up with the ring by eye (the edge and backing are the same color, so screenshots can't measure it).
- Containers below level 2 get raised to 2 while active (and restored): the target's container is level 0 in the BACKGROUND strata, so the model couldn't sit beneath it and drew on top (flat bottom, no circle edge). Found via `/bap debug`.
- **Layer relative to the ring's frame, not the portrait's.** On target/focus the ring (`TargetFrameContainer.FrameTexture`, LOW strata, level ~501) and the portrait (an unnamed child frame in the BACKGROUND strata, alongside other frames at levels 2-3, one of which draws a dark circle with BBF on) live in different frames. `UNITS[unit].ring` finds the ring; the circle edge is created on the ring's frame one sublevel beneath the ring texture, and model/backing sit at ring level -1/-2 in the ring's strata. On player/ToT/party the ring and portrait share a frame, so this is the same as before. Diagnosed with `/fstack`.
- While active, Blizzard's portrait is hidden (`Hide()`), and a `hooksecurefunc(portrait, "Show")` re-hides it if anything re-shows it. It's restored on deactivate only if it was shown before. Neither Blizzard nor BBF shows or hides these portraits (Blizzard only does for boss frames), so the risk of fighting them is low. **Side effect:** BBF spec/class icon portraits are covered while the model shows (model wins).
- The layers are no longer inside the unit frame, so they follow it via `container:HookScript("OnShow"/"OnHide")`, and `Refresh` checks `container:IsVisible()`.
- Alpha mirrors `portrait:SetAlpha` (party out-of-range fade) onto bg, model and vignette.
- **Settings migration:** saved settings win over new defaults, so when a default must change for existing installs, bump `SETTINGS_VERSION` and reset those keys in `MigrateSettings()`.
- Camera: `SetPortraitZoom(db.zoom)` + `SetCamDistanceScale(sizes[size].cam)` (0.85, lower = bigger face). `UNITS[unit].size` is `large` (player/target/focus) or `small` (ToT/party).
- `Refresh(unit)`: show or hide the layers and `SetUnit()` (a full model reload). Split into `RefreshSquare` / `RefreshCircle`. Events and container `OnShow` go through `QueueRefresh(unit)`, which coalesces requests into one refresh per unit on the next frame (one target change fires `PLAYER_TARGET_CHANGED`, `UNIT_TARGET` and often `UNIT_PORTRAIT_UPDATE`); slash commands and the ticker call `Refresh` directly. It hides when disabled, when BBF's `HasNoPortrait(unit)` is true, or when the unit is missing, not visible or disconnected.
- `Tick()` (every 0.5s) compares `UnitState(unit)` (GUID + a visible/connected code, two plain values: no string built per tick) with the last refresh (`StateChanged`/`MarkState`) and refreshes only on change. This covers changes with no reliable event: ToT/FoT swaps, party members entering or leaving view range.
- `Safe(v)` drops "secret" values (`issecretvalue`) so comparisons and concatenation never error.
- Events: `PLAYER_ENTERING_WORLD` (0.5s delay so BBF finishes resizing; starts the ticker), `PLAYER_TARGET_CHANGED` (target + ToT), `PLAYER_FOCUS_CHANGED` (focus + FoT), `UNIT_TARGET` (ToT/FoT), `GROUP_ROSTER_UPDATE` (party), `UNIT_MODEL_CHANGED`, `UNIT_PORTRAIT_UPDATE`, `UNIT_CONNECTION`.
- Target bar grow (`StartGrow`/`GrowStep`, `/bap grow`, `/bap growtime`, trace with `/bap grow debug`): post-hooks `TargetFrame:Update()` (Blizzard calls it on target change, login and `UNIT_TARGETABLE_CHANGED`, after setting the bar values). For `growTime` seconds an overlay `StatusBar` (`bar.bapGrowBar`, same strata/level, fill one sublevel above Blizzard's so bar texts stay on top) mirrors the bar's live min/max/value and the fill's look (`CopyBarStyle`, every frame, mask list rebuilt only when the fill's masks change so nothing is allocated per frame: texture/atlas, vertex color RGB only (its alpha follows our `SetAlpha(0)` and hid the overlay), desaturation, blend, mask textures (Blizzard's `HealthBarMask`/`ManaBarMask` clip the fill's end; unmasked, the overlay grew past it), because BBF class colors are a desaturated fill + tint, sometimes set on the fill texture directly) while its **width** eases 0 → bar width; Blizzard's fill is hidden with `SetAlpha(0)` and restored after (only if still 0). Width does the lerp because values can be secret: tainted code can't do math on them and `C_CurveUtil` `AddPoint` only takes secrets when untainted, but `SetValue`/`SetMinMaxValues` accept them. Rejected: `SetValue(v, ExponentialEaseOut)` on Blizzard's bar (Blizzard's immediate re-sets cancelled it; grew only once in game) and growing from our own `PLAYER_TARGET_CHANGED` (can run before Blizzard's handler, animating to the old target's value).
- SavedVariables: `BBFAnimatedPortraitsDB` (defaults merged on `ADDON_LOADED`).
- Slash: `/bap`.

## Blizzard / BBF frame paths (WoW Forever beta, internal name "Camelot", client 1.60.1.70374)

Verified against Blizzard's UI source: `github.com/Gethe/wow-ui-source`, branch **`forever`** (same build as the client). Camelot loads the Mainline ("Family") unit-frame XML.
Also exported locally from the client (`exportInterfaceFiles code`) to `_classic_beta_/BlizzardInterfaceCode/`. The unit-frame files match the mirror byte-for-byte (ignoring CRLF).

| Unit | Portrait (layer) | Mask | Border art (layer) |
|---|---|---|---|
| player | `PlayerFrame.PlayerFrameContainer.PlayerPortrait` (BACKGROUND 1) | `PlayerPortraitMask` | `FrameTexture` (BACKGROUND 2) |
| target / focus | `TargetFrame/FocusFrame.TargetFrameContainer.Portrait` (BACKGROUND 1) | `PortraitMask` (CircleMask) | `FrameTexture` (BACKGROUND 2) |
| targettarget / focustarget | `TargetFrame/FocusFrame.totFrame.Portrait` 37×37 (BACKGROUND 1) | `PortraitMask` (CircleMask) | `FrameTexture` (BACKGROUND 2) |
| party1–4 | `PartyFrame.MemberFrame1..4.Portrait` (BACKGROUND) | `PortraitMask` (CircleMask) | `Texture` (ARTWORK) |

**Findings that affect the design:**
- The border art sits only **one sublevel above** the portrait on player, target and ToT, so a texture at "portrait sublevel + 1" shares the border's sublevel (undefined draw order). **Fixed** by moving our layers into a separate holder frame with its own mask.
- Blizzard changes the portrait itself: party portraits fade with `SetAlpha` when out of range (`PartyMemberFrame.lua:399`) and get `SetVertexColor` tints (`:671-677`). The target portrait is greyed when tapped (`TargetFrame.lua:329`) and reset to alpha 1 (`:156`). **Don't hide the portrait via alpha**: Blizzard will overwrite it.
- Party member frames come from a frame pool (`PartyFrame.lua:56-59`) and are assigned as `MemberFrameN` on init.

**Shared borders:** box↔bars `squareGap` 1 and health↔mana `barSpacing` 0 make adjacent 1px borders overlap into one line. Mana's vertical position is measured after layout and corrected (`bapDY`), which also closes BBF's ToT health/mana gap; mana's border width is forced to health's (`alignMana`).

**When to hand layout back to BBF:** only when the user turns something off (disabled, unit toggled off, circle style, `namerow 0`). Transient states (no target, frame hidden, out of range) just hide the box and keep bars/names pinned; restoring there let BBF's name/level positions stick after target switches (diagnosed via `/bap debug`).

**NPCs with no power:** Blizzard hides the mana bar, but BBF (pixel border) reparents the mana posFrame/border/background to `frame.noPortraitMode` so an empty mana slot stays visible. `GetBarFrames` treats a visible slot as the mana row; if BBF hides the slot too (hide-mana option), health takes the whole stack (`LayoutBars` no-mana path).

**BBF runtime re-layouts:** BBF rebuilds parts of its layout when settings change (fonts → `BBF.SetCustomFonts`, names → `ApplyNameLayout(s)`, bar text → `UpdateNoPortraitText`, …). `HookBBF()` hooks those (`BBF_RELAYOUT_FUNCS`) and queues a debounced `RefreshAll`. Add new ones there if another BBF setting knocks the layout out.

BBF code that touches portraits (read only, for compatibility):
- `forever/BetterBlizzFrames.lua` ~5143–5164: resizes portraits and masks (player 61, target/focus 56).
- `forever/modules/classicFrames.lua` ~343, ~660: the Classic Frames mode repositions portraits.
- `forever/modules/noPortrait.lua`: `BBF.HasNoPortrait(unit)`; we skip when true.
- `BBF.SpecPortraits()` (~5528) and `forever/modules/healer.lua` `UpdateSecretPortrait`: spec and healer icon portraits. **Open question:** should icons win over the model?

## Roadmap
- [x] Step 1: player frame, inscribed square, `/bap` tuning
- [ ] Test step 1 in game (screenshot, then tune zoom/inset defaults)
- [x] Step 2: target + focus (`PLAYER_TARGET_CHANGED`, `PLAYER_FOCUS_CHANGED`), untested in game
- [x] Step 3: party frames, ToT/FoT, untested in game
- [ ] Per-group inset/zoom (small ToT/party portraits may need a larger inset)
- [ ] Decide final circle treatment (inscribed vs cover ring vs square art)
- [ ] Conflict rule with BBF spec/healer portraits
- [ ] Options panel (Settings API) to replace or complement `/bap`
- [ ] Retail support (`## Interface` list, verify frame paths)

## Test checklist
- [ ] Model appears and animates on the player frame after login and `/reload`
- [ ] Target / focus: model swaps when the target changes; NPC targets look reasonable
- [ ] ToT / FoT: model follows when your target changes its target
- [ ] Party: models appear; a member out of view range falls back to the 2D portrait and returns when in range
- [ ] `/bap unit tot` / `/bap unit party` toggle cleanly
- [ ] With BBF spec icons on: note which wins on target/focus (open question)
- [ ] No square corners poking outside the portrait ring
- [ ] Square: box sits flush beside the bars on every frame (player/ToT/party left, target/focus right)
- [ ] Square: border matches BBF's pixel border; face size OK (`/bap cam 0.8 square`, `/bap extend 10`)
- [ ] Circle (BBF portraits on): nothing pokes outside the ring at inset 0.84
- [ ] No straight cut lines visible inside the circle (vignette)
- [ ] Face size feels right on large and small frames (tune `/bap cam`)
- [ ] Level badge, rest/PvP/leader/combat icons still draw on top of the model
- [ ] `/bap toggle` brings back the normal 2D portrait
- [ ] Party members out of range fade like Blizzard's portrait
- [ ] Mount, shapeshift and gear changes update the model
- [ ] Vehicle / possess: no broken portrait
- [ ] `/bap toggle` restores the normal portrait cleanly
- [ ] BBF "no portrait" mode: the addon stays hidden
- [ ] Classic Frames mode in BBF: the model stays aligned
- [ ] No Lua errors (`/console scriptErrors 1`)

## Conventions
- One step per commit; test in game before starting the next step.
- Commit messages follow the rules in **Commit messages** below.
- **Don't commit without asking.** Leave changes uncommitted for Jason to review, then commit when he approves.
- **Geometry limit (measured in game):** the ring opening is ~0.85 × portrait size and the ring's outer edge ~1.04 ×. A square model can't fill the opening without its corners passing the outer edge (needs inset ≤ 1.04/√2 ≈ 0.73). So the picture ends on a crisp circle at ~85% of the opening, with a dark band to the ring. Tried and rejected: inset 0.82 + wide fade (looked heavy), inset 1.0 + thin fade (corners protruded).
- Never edit BBF files. A clean backup of BBF v2.1.7 is at `_classic_beta_/Interface/AddOns_backup/`.
- Git author: Jason <jrbarnachea@gmail.com>. Remote: `github.com/nautxx/bbf-animated-portraits` (private).

## Commit messages

Put a Conventional Commits prefix on every commit title: `type: short imperative summary`.

- `feat`: new capability or behavior (a new unit frame, a new slash command, a new option)
- `fix`: bug fix
- `chore`: maintenance with no user-visible behavior change (TOC bumps, config, cleanup, license)
- `docs`: README, CLAUDE.md or comment-only changes
- `refactor`: code restructuring with no behavior change
- `test`: test-only changes
- `style`: formatting or whitespace, no logic change
- `perf`: performance improvement
- `revert`: reverts a previous commit

After the colon: lowercase, imperative mood ("add", not "added" or "adds"), no trailing period, ideally under ~70 characters. Example: `feat: add animated portraits to target and focus frames`.

When a commit touches only one thing, the title alone is enough, so skip the body. When a commit bundles several distinct changes, add a blank line after the title and a short bullet per change:

```
feat: add animated portraits to target and focus frames

- add target/focus entries to GetPortraitInfo()
- refresh on PLAYER_TARGET_CHANGED and PLAYER_FOCUS_CHANGED
- document new frame paths in CLAUDE.md
```
