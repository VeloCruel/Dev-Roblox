# Changelog

## v1.4 — Server companion

### Added
- **Server-authoritative mode**. The same file now detects via
  `RunService:IsServer()` whether it's running as a Script in
  `ServerScriptService`. If so, it publishes
  `ReplicatedStorage.AdminPanelRemotes.Action` and handles a strict
  command vocabulary (god / kill / heal / freeze / kick / mass actions).
  Every action is gated by `caller.Name == CONFIG.Owner`.
- **Admin tab** on the client — appears only when the server companion
  is online. Renders a banner so it's obvious the dangerous tooling
  is unlocked. Sections: Self · Target Actions · Mass.
- New commands (no-op without the companion):
  `god` · `ungod` · `heal` · `killme` · `kill <p>` · `killall` ·
  `healall` · `respawn <p>` · `respawnall` · `freezeall` · `unfreezeall` ·
  `bringall` · `kick <p> [reason]`

### Changed
- `CONFIG.Owner` now ships set to `"Chikasid"` — only that user sees the
  panel (case-insensitive match).
- Authorization check is case-insensitive for both `Owner` and
  `Whitelist`.

## v1.3 — Power features

### Added
- **Waypoints** tab — save the current position with a name, one-click
  teleport back, delete. Persisted between sessions.
- **Freecam** — scriptable independent camera (WASD + mouse-look,
  scroll-wheel adjusts speed, LeftShift = 3× sprint).
- **Anti-AFK** — uses `VirtualUser` on `LocalPlayer.Idled` to prevent
  the idle kick.
- **Auto-Respawn** — re-runs `LoadCharacter` on death.
- **Hitbox extender** — resizes `HumanoidRootPart` with a size slider;
  re-enforced via Heartbeat in case the host game keeps clobbering it.
- **Click-TP** — Shift + LMB on any world surface teleports there.
- **Coordinate HUD** — corner overlay with live X/Y/Z, speed, FPS.
- **Server** tab — Rejoin · Server-hop · Copy Job ID · live info pane
  (place id, job id, players, ping, uptime).
- **Theme picker** — 6 presets (Midnight, Cyber, Sunset, Mint, Crimson,
  Royal). Applied through the accent-follower registry, so every UI
  element retints instantly.
- **Config persistence** — settings + waypoints are written to
  `VeloCruelAdminPanel.json` via the executor file API when present;
  loaded automatically at boot.
- **Spectate cycle** — Next / Previous buttons walk the player list.
- New commands: `freecam`, `clicktp`, `hud`, `antiafk`, `autorespawn`,
  `rejoin`, `hop`, `wp`, `goto`, `wpdel`, `specnext`, `specprev`,
  `theme`, `save`, `load`, `hitbox`.

## v1.2 — Premium UI overhaul

### Added
- Glassmorphism surfaces (gradient + inner stroke + transparency stack)
- Drop shadow + neon halo behind the panel
- Toggleable backdrop `BlurEffect` on Lighting while open
- Optional RGB accent cycle that drives every UI element subscribed
  through a single follower registry
- Avatars in the title bar, target card, and player rows
- Sidebar tabs reworked with icon + sliding accent indicator
- Toggles with neon glow when active
- Sliders with gradient fill and animated thumb
- Buttons get hover glow + click ripple originating at the cursor
- One-time boot loading animation
- Resize handle on the panel
- Notifications redesigned with kind-tinted stripe + side glow

## v1.1 — Stability pass

### Changed
- **Invisible** rewired to a continuous `RenderStepped` loop on
  `LocalTransparencyModifier` so the camera system stops un-hiding the
  avatar.
- **Fly** redesigned in HD Admin style — upright avatar (camera-yaw
  only), smooth lerped velocity, LeftShift = 2× sprint.

### Removed
- **God Mode** and **Heal** removed. Both relied on client-side
  `Humanoid.Health` writes that don't replicate on FilteringEnabled
  servers, so they never actually worked.

## v1.0 — Initial release

Single-file production rebuild:
- Strict Luau with type annotations
- Maid pattern for per-feature connection / instance lifetime
- Modern movers: `LinearVelocity` + `AlignOrientation`
- Rate-limited button presses + command bar
- Self / Players / Vehicle / World / Logs / Info tabs
- Notifications, draggable panel, mobile FAB, respawn-safe toggles
