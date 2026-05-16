# Roblox Admin Panel

A single-file, client-side admin panel for Roblox — premium UI, no setup
required. Drop it in as a LocalScript or run via executor and the entire
system (ScreenGui, animations, command logic, respawn handling) is
generated automatically.

![status](https://img.shields.io/badge/status-production-blue)
![lua](https://img.shields.io/badge/lua-Luau-blueviolet)
![surface](https://img.shields.io/badge/runtime-client--side-orange)

---

## Quick start

1. Open [`AdminPanel.lua`](./AdminPanel.lua) and edit the `CONFIG` block at
   the top — set `Owner` to your username (or leave blank to allow whoever
   runs the script).
2. Drop the file into `StarterPlayer > StarterPlayerScripts` as a
   LocalScript, or execute it through your executor of choice.
3. Press **Right Control** (configurable) — or tap the floating button on
   mobile — to open the panel.

### One-line loader (for executors)

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/VeloCruel/Dev-Roblox/main/AdminPanel.lua"))()
```

---

## Features

### Self
- Fly (HD Admin–style, upright avatar, smooth lerp, LeftShift = sprint)
- Noclip · Infinite Jump
- Walk-speed / Jump-power / Fly-speed sliders
- Local invisibility (continuous, survives camera occlusion)
- Reset / Sit
- Hitbox extender with size slider

### Players
- Searchable list with avatars + status dots
- Teleport · Bring · Spectate · Stop / Next / Prev Spectate
- View · Freeze · Unfreeze

### Vehicle
- Speed multiplier · Instant acceleration
- Boost impulse · Vehicle fly · Auto-detect

### World
- FOV · Gravity · Day/Night
- ESP highlights · Tracers · Fullbright
- Freecam (WASD + mouse-look)
- Click-TP (Shift + LMB)
- Coordinate / FPS HUD

### Waypoints
- Save current position with a name
- One-click teleport back · Delete · Persisted between sessions

### Server
- Anti-AFK · Auto-Respawn
- Rejoin server · Server-hop
- Copy Job ID · Live server-info pane (place id, players, ping, uptime)

### Logs
- Timestamped command history (200 entries, capped)

### Info / Settings
- Backdrop blur toggle · RGB accent cycle toggle
- Theme presets: Midnight · Cyber · Sunset · Mint · Crimson · Royal
- Full command reference

### Polish
- Glassmorphism surfaces with gradient + inner stroke
- Drop shadow + accent halo tracking the panel every frame
- One-time boot reveal animation
- Click ripples on every button
- Notification stack with kind-tinted glow
- Draggable window · resizable from bottom-right
- Mobile floating button (draggable, tap-vs-drag heuristic)
- Persisted config via executor `writefile` (graceful no-op without it)

---

## Command bar

Prefix with `/` (configurable). Examples:

```
fly                       toggle flight
noclip                    toggle noclip
ws 80                     walkspeed
jp 120                    jumppower
infjump
invis
hitbox 12                 toggle hitbox extender with size

tp Builderman             teleport to player
bring me
spec Player2
spec off
view Player3
freeze Player4
unfreeze Player4
specnext / specprev       cycle through players

freecam                   toggle freecam
clicktp                   toggle shift-click teleport
hud                       toggle coord HUD

wp base                   save current pos as "base"
goto base                 teleport to waypoint
wpdel base

antiafk / autorespawn     server utility toggles
rejoin / hop              rejoin / hop to another server
theme Cyber               switch theme
save / load               persist or reload config

fov 90 / gravity 20
day / night
esp / tracers / fb
vspeed 5 / vboost / vfly
```

---

## Architecture

- **Maid pattern** — every toggle owns a Maid that tracks its
  `RBXScriptConnection`s, instances, and cleanup functions. Toggling off
  unwinds everything.
- **Accent followers** — any UI element that should track the live accent
  color is registered once; `applyAccent()` (or the RGB cycle) walks the
  registry. No global re-paint needed.
- **Rate limiter** — buttons and command bar use a per-key token bucket
  to swallow accidental double-clicks.
- **Modern movers** — `LinearVelocity` + `AlignOrientation` instead of
  deprecated `BodyVelocity`/`BodyGyro`.
- **Respawn-safe** — every active feature is re-applied on
  `CharacterAdded`; toggle state lives on a single `State` table.
- **Persistence** — writes settings to `VeloCruelAdminPanel.json` via the
  executor file API when available, falls back to runtime-only otherwise.

---

## Configuration

The `CONFIG` block at the top of `AdminPanel.lua`:

```lua
local CONFIG = {
    Owner             = "",                              -- "" = any user
    Whitelist         = {},
    Ranks             = {},
    ToggleKey         = Enum.KeyCode.RightControl,
    CommandPrefix     = "/",
    MobileButton      = true,
    PanelTitle        = "ADMIN PANEL",
    PanelSize         = Vector2.new(660, 460),
    PanelMinSize      = Vector2.new(520, 360),
    PanelMaxSize      = Vector2.new(1200, 780),
    Accent            = Color3.fromRGB(120, 150, 255),
    BackgroundAlpha   = 0.18,
    BackdropBlur      = true,
    BackdropBlurSize  = 14,
    RGBCycle          = false,
    RGBCycleSpeed     = 0.06,
    BootAnimation     = true,
}
```

---

## Notes

- **Client-side**. No `RemoteEvent`s or server scripts are required, which
  is the deliberate trade-off for zero-setup. On FilteringEnabled servers
  the panel's *target-other* effects (Bring, Freeze) revert on the next
  physics step; they're best used in your own experiences.
- **God Mode / Heal** are intentionally **not** included — the server is
  authoritative for `Humanoid.Health`, so client-only versions never
  worked reliably and gave false confidence.
- **Hitbox extender** scales `HumanoidRootPart`; effectiveness depends on
  how the host game performs hit detection.

---

## License

MIT — see [`LICENSE`](./LICENSE).
