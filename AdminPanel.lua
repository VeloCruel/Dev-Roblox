--!strict
--[[
================================================================================
  ADMIN PANEL — single-file edition  ·  premium UI overhaul
================================================================================
  • One Lua file. No remotes, modules, folders, or instances to set up by
    hand. Drop in as a LocalScript or execute and the entire system —
    ScreenGui, ambient blur, state, commands, respawn handling — is built
    automatically.
  • Pure client-side. No server script required, which is the deliberate
    trade-off for zero-setup beginner friendliness; on FilteringEnabled
    servers, target-other physics actions (Bring / Freeze) revert next
    physics step.

  SETUP
    1.  Edit CONFIG below — set Owner to your username (or leave blank to
        allow whoever runs the script).
    2.  Run.  Press the toggle key (default = RightControl) or tap the
        floating button on mobile.
================================================================================
]]

-- ── CONFIG ────────────────────────────────────────────────────────────────
local CONFIG = {
    Owner             = "",
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
    BackgroundAlpha   = 0.18,    -- 0 = opaque, 1 = invisible
    BackdropBlur      = true,    -- BlurEffect behind panel while open
    BackdropBlurSize  = 14,
    RGBCycle          = false,   -- animate accent through hue spectrum
    RGBCycleSpeed     = 0.06,    -- hue/second
    BootAnimation     = true,    -- one-time loading reveal
}

-- ── SERVICES ──────────────────────────────────────────────────────────────
local Players          = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService       = game:GetService("RunService")
local TweenService     = game:GetService("TweenService")
local Lighting         = game:GetService("Lighting")
local Workspace        = game:GetService("Workspace")
local CoreGui          = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer
local Camera      = Workspace.CurrentCamera

-- ── AUTH ──────────────────────────────────────────────────────────────────
local function authorized(name: string): boolean
    if CONFIG.Owner == "" then return true end
    if name == CONFIG.Owner then return true end
    for _, w in ipairs(CONFIG.Whitelist) do
        if w == name then return true end
    end
    return false
end

if not authorized(LocalPlayer.Name) then return end

-- ╔══════════════════════════════════════════════════════════════════════╗
-- ║  THEME & ASSETS                                                       ║
-- ╚══════════════════════════════════════════════════════════════════════╝
local Theme = {
    Bg          = Color3.fromRGB(12, 14, 20),
    Bg2         = Color3.fromRGB(18, 20, 28),
    Bg3         = Color3.fromRGB(24, 27, 36),
    Bg4         = Color3.fromRGB(32, 36, 48),
    Surface     = Color3.fromRGB(22, 25, 34),

    Border      = Color3.fromRGB(48, 54, 72),
    BorderSoft  = Color3.fromRGB(36, 40, 54),

    Text        = Color3.fromRGB(236, 238, 244),
    TextDim     = Color3.fromRGB(155, 160, 175),
    TextMuted   = Color3.fromRGB(108, 114, 130),

    Accent      = CONFIG.Accent,
    AccentSoft  = Color3.fromRGB(165, 185, 255),
    AccentDeep  = Color3.fromRGB(75, 95, 200),

    Ok          = Color3.fromRGB(86, 210, 140),
    Warn        = Color3.fromRGB(240, 184, 80),
    Err         = Color3.fromRGB(240, 100, 100),
}

-- Built-in Roblox UI assets used for glow / shadow / corner / icons.
local Asset = {
    DropShadow  = "rbxassetid://6014261993",   -- 9-slice drop shadow
    DropSlice   = Rect.new(49, 49, 450, 450),
    SoftGlow    = "rbxassetid://5028857084",   -- radial glow
    SoftGlowSlice = Rect.new(24, 24, 76, 76),
    SearchIcon  = "rbxassetid://3926305904",   -- atlas icon
}

local Tween = {
    Snap   = TweenInfo.new(0.12, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
    Fast   = TweenInfo.new(0.18, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
    Med    = TweenInfo.new(0.28, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
    Slow   = TweenInfo.new(0.45, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
    Pop    = TweenInfo.new(0.32, Enum.EasingStyle.Back,  Enum.EasingDirection.Out),
    Ripple = TweenInfo.new(0.55, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
}

-- ╔══════════════════════════════════════════════════════════════════════╗
-- ║  UTILITIES                                                            ║
-- ╚══════════════════════════════════════════════════════════════════════╝

-- Instance factory.  Parent is set last so the whole subtree commits in
-- a single replication step.
local function new(class: string, props: { [string]: any }?, children: { Instance }?): Instance
    local inst   = Instance.new(class)
    local parent: Instance? = nil
    if props then
        for k, v in pairs(props) do
            if k == "Parent" then parent = v else (inst :: any)[k] = v end
        end
    end
    if children then
        for _, c in ipairs(children) do c.Parent = inst end
    end
    if parent then inst.Parent = parent end
    return inst
end

local function tw(o: Instance, info: TweenInfo, goal: { [string]: any }): Tween
    local t = TweenService:Create(o, info, goal)
    t:Play()
    return t
end

local function safe(fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then warn("[AdminPanel] " .. tostring(err)) end
end

-- ── Maid: per-feature lifetime of connections / instances / cleanup fns.
local Maid = {}
Maid.__index = Maid
function Maid.new() return setmetatable({ _items = {} }, Maid) end
function Maid:give(item) table.insert(self._items, item); return item end
function Maid:clean()
    for i = #self._items, 1, -1 do
        local item = self._items[i]; self._items[i] = nil
        if typeof(item) == "RBXScriptConnection" then item:Disconnect()
        elseif typeof(item) == "Instance"         then item:Destroy()
        elseif type(item) == "function"           then pcall(item) end
    end
end

-- ── Token-bucket rate limit (per key).
local rateState: { [string]: number } = {}
local function rate(key: string, gap: number): boolean
    local now = os.clock()
    if (rateState[key] or 0) + gap > now then return false end
    rateState[key] = now
    return true
end

-- ── Accent-color subscribers, driven by optional RGB cycle.
local accentFollowers: { [Instance]: string } = {}
local function follow(inst: Instance, prop: string?)
    accentFollowers[inst] = prop or "BackgroundColor3"
    (inst :: any)[prop or "BackgroundColor3"] = Theme.Accent
end

local liveAccent = Theme.Accent
local function applyAccent(c: Color3)
    liveAccent = c
    for inst, prop in pairs(accentFollowers) do
        if inst.Parent then (inst :: any)[prop] = c end
    end
end

-- ── Character helpers
local function char()     return LocalPlayer.Character end
local function humanoid() local c = char(); return c and c:FindFirstChildOfClass("Humanoid") end
local function hrp()      local c = char(); return c and c:FindFirstChild("HumanoidRootPart") end

local function findPlayer(query: string): Player?
    if not query or query == "" then return nil end
    query = query:lower()
    if query == "me"     then return LocalPlayer end
    if query == "random" then
        local pool = {}
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= LocalPlayer then table.insert(pool, p) end
        end
        return pool[math.random(1, math.max(1, #pool))]
    end
    for _, p in ipairs(Players:GetPlayers()) do
        if p.Name:lower() == query or p.DisplayName:lower() == query then return p end
    end
    for _, p in ipairs(Players:GetPlayers()) do
        if p.Name:lower():sub(1, #query) == query
        or p.DisplayName:lower():sub(1, #query) == query then return p end
    end
    return nil
end

local function rankOf(name: string): string
    if name == CONFIG.Owner then return "Owner" end
    if CONFIG.Ranks[name] then return CONFIG.Ranks[name] end
    for _, w in ipairs(CONFIG.Whitelist) do
        if w == name then return "Admin" end
    end
    return "Member"
end

local function avatarFor(userId: number): string
    return ("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150"):format(userId)
end

-- ╔══════════════════════════════════════════════════════════════════════╗
-- ║  STATE                                                                ║
-- ╚══════════════════════════════════════════════════════════════════════╝
local State = {
    fly         = false, flySpeed    = 70,
    noclip      = false,
    walkSpeed   = 16,    walkSpeedOn = false,
    jumpPower   = 50,    jumpPowerOn = false,
    infJump     = false,

    invisible   = false,
    spectating  = nil :: Player?,
    target      = nil :: Player?,

    vSpeedMult  = 1, vInstant = false, vFly = false,

    fov         = 70,  fovOn     = false,
    gravity     = workspace.Gravity, gravityOn = false,
    esp         = false, tracers = false, fullbright = false,
}

local Maids = {
    fly = Maid.new(), noclip = Maid.new(), infJump = Maid.new(),
    invis = Maid.new(), vfly = Maid.new(), tracers = Maid.new(), rgb = Maid.new(),
}

local Log: { string } = {}
local LogCap          = 200
local logChanged: BindableEvent

-- ╔══════════════════════════════════════════════════════════════════════╗
-- ║  VISUAL PRIMITIVES — shadow, glow, glass, ripple                      ║
-- ╚══════════════════════════════════════════════════════════════════════╝

-- Soft drop shadow placed BEHIND the parent (rendered as a sibling).
local function dropShadow(target: GuiObject, opts: { [string]: any }?)
    opts = opts or {}
    local img = new("ImageLabel", {
        Name                   = "Shadow",
        BackgroundTransparency = 1,
        Image                  = Asset.DropShadow,
        ImageColor3            = (opts and opts.Color)        or Color3.fromRGB(0, 0, 0),
        ImageTransparency      = (opts and opts.Transparency) or 0.4,
        ScaleType              = Enum.ScaleType.Slice,
        SliceCenter            = Asset.DropSlice,
        AnchorPoint            = Vector2.new(0.5, 0.5),
        Position               = UDim2.fromScale(0.5, 0.5) + UDim2.fromOffset(0, (opts and opts.Y) or 6),
        Size                   = UDim2.new(1, (opts and opts.Spread) or 40, 1, (opts and opts.Spread) or 40),
        ZIndex                 = target.ZIndex - 1,
        Parent                 = target.Parent,
    }) :: ImageLabel
    return img
end

-- Neon glow halo (radial). Sits behind the target.
local function neonGlow(target: GuiObject, opts: { [string]: any }?)
    opts = opts or {}
    local img = new("ImageLabel", {
        Name                   = "Glow",
        BackgroundTransparency = 1,
        Image                  = Asset.SoftGlow,
        ImageColor3            = (opts and opts.Color)        or Theme.Accent,
        ImageTransparency      = (opts and opts.Transparency) or 0.55,
        ScaleType              = Enum.ScaleType.Slice,
        SliceCenter            = Asset.SoftGlowSlice,
        AnchorPoint            = Vector2.new(0.5, 0.5),
        Position               = UDim2.fromScale(0.5, 0.5),
        Size                   = UDim2.new(1, (opts and opts.Spread) or 20, 1, (opts and opts.Spread) or 20),
        ZIndex                 = target.ZIndex - 1,
        Parent                 = target,
    }) :: ImageLabel
    if opts and opts.FollowAccent then follow(img, "ImageColor3") end
    return img
end

-- Glass surface: rounded frame with backdrop transparency, subtle inner
-- stroke, and a soft top-light gradient. Returns the frame.
local function glassSurface(props: { [string]: any }, children: { Instance }?): Frame
    local defaults = {
        BackgroundColor3       = Theme.Surface,
        BackgroundTransparency = 0.18,
        BorderSizePixel        = 0,
    }
    for k, v in pairs(defaults) do
        if props[k] == nil then props[k] = v end
    end
    local f = new("Frame", props, children) :: Frame
    new("UICorner", { CornerRadius = UDim.new(0, props.Radius or 10), Parent = f })
    new("UIStroke", {
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
        Color           = Theme.BorderSoft,
        Thickness       = 1,
        Transparency    = 0.35,
        Parent          = f,
    })
    new("UIGradient", {
        Rotation = 90,
        Color    = ColorSequence.new(Color3.fromRGB(255, 255, 255)),
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0.85),
            NumberSequenceKeypoint.new(0.4, 1),
            NumberSequenceKeypoint.new(1, 1),
        }),
        Parent = f,
    })
    return f
end

-- Click ripple originating at (lx, ly) inside the parent button.
local function ripple(parent: GuiObject, lx: number, ly: number)
    if not parent.ClipsDescendants then parent.ClipsDescendants = true end
    local rp = new("Frame", {
        BackgroundColor3       = Color3.fromRGB(255, 255, 255),
        BackgroundTransparency = 0.7,
        BorderSizePixel        = 0,
        AnchorPoint            = Vector2.new(0.5, 0.5),
        Position               = UDim2.fromOffset(lx, ly),
        Size                   = UDim2.fromOffset(0, 0),
        ZIndex                 = parent.ZIndex + 10,
        Parent                 = parent,
    }, { new("UICorner", { CornerRadius = UDim.new(1, 0) }) }) :: Frame

    local maxDim = math.max(parent.AbsoluteSize.X, parent.AbsoluteSize.Y) * 2.4
    local t = tw(rp, Tween.Ripple, {
        Size                   = UDim2.fromOffset(maxDim, maxDim),
        BackgroundTransparency = 1,
    })
    t.Completed:Connect(function() rp:Destroy() end)
end

-- ╔══════════════════════════════════════════════════════════════════════╗
-- ║  ROOT GUI — finds a safe parent, wipes any previous instance          ║
-- ╚══════════════════════════════════════════════════════════════════════╝
local function resolveGuiParent(): Instance
    local fns = { rawget(getfenv(), "gethui"), rawget(getfenv(), "get_hidden_gui") }
    for _, f in ipairs(fns) do
        if typeof(f) == "function" then
            local ok, parent = pcall(f)
            if ok and parent then return parent end
        end
    end
    if pcall(function() return CoreGui:GetChildren() end) then return CoreGui end
    return LocalPlayer:WaitForChild("PlayerGui")
end

local guiParent = resolveGuiParent()
local existing  = guiParent:FindFirstChild("AdminPanel")
if existing then existing:Destroy() end

local gui = new("ScreenGui", {
    Name           = "AdminPanel",
    ResetOnSpawn   = false,
    IgnoreGuiInset = true,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    DisplayOrder   = 10000,
    Parent         = guiParent,
}) :: ScreenGui

-- Notifications layer (top-right)
local notifLayer = new("Frame", {
    Name                   = "Notifications",
    AnchorPoint            = Vector2.new(1, 0),
    Position               = UDim2.new(1, -18, 0, 18),
    Size                   = UDim2.new(0, 300, 1, -36),
    BackgroundTransparency = 1,
    Parent                 = gui,
}, {
    new("UIListLayout", {
        Padding             = UDim.new(0, 10),
        HorizontalAlignment = Enum.HorizontalAlignment.Right,
        SortOrder           = Enum.SortOrder.LayoutOrder,
    }),
}) :: Frame

-- Tracer overlay
local tracerLayer = new("Frame", {
    Name                   = "Tracers",
    Size                   = UDim2.fromScale(1, 1),
    BackgroundTransparency = 1,
    ZIndex                 = 1,
    Parent                 = gui,
}) :: Frame

-- ╔══════════════════════════════════════════════════════════════════════╗
-- ║  NOTIFICATIONS                                                        ║
-- ╚══════════════════════════════════════════════════════════════════════╝
local function notify(text: string, kind: string?)
    kind = kind or "info"
    local color: Color3 = ({
        info = Theme.Accent, ok = Theme.Ok, warn = Theme.Warn, err = Theme.Err,
    })[kind] or Theme.Accent

    local card = glassSurface({
        BackgroundColor3       = Theme.Bg2,
        BackgroundTransparency = 0.1,
        Size                   = UDim2.new(1, 0, 0, 0),
        AutomaticSize          = Enum.AutomaticSize.Y,
        Position               = UDim2.new(1.4, 0, 0, 0),
        Radius                 = 10,
        Parent                 = notifLayer,
    })
    dropShadow(card, { Spread = 30, Transparency = 0.55, Y = 4 })

    new("Frame", {
        Name             = "Stripe",
        BackgroundColor3 = color,
        BorderSizePixel  = 0,
        Position         = UDim2.new(0, 8, 0, 10),
        Size             = UDim2.new(0, 3, 1, -20),
        Parent           = card,
    }, { new("UICorner", { CornerRadius = UDim.new(0, 2) }) })

    -- Soft inset glow tinted with kind color
    local glow = new("ImageLabel", {
        BackgroundTransparency = 1,
        Image                  = Asset.SoftGlow,
        ImageColor3            = color,
        ImageTransparency      = 0.85,
        ScaleType              = Enum.ScaleType.Slice,
        SliceCenter            = Asset.SoftGlowSlice,
        AnchorPoint            = Vector2.new(0, 0.5),
        Position               = UDim2.new(0, 0, 0.5, 0),
        Size                   = UDim2.new(0, 50, 1, 20),
        ZIndex                 = card.ZIndex,
        Parent                 = card,
    })
    glow.ZIndex = card.ZIndex

    new("TextLabel", {
        BackgroundTransparency = 1,
        Position               = UDim2.new(0, 22, 0, 10),
        Size                   = UDim2.new(1, -32, 0, 0),
        AutomaticSize          = Enum.AutomaticSize.Y,
        Font                   = Enum.Font.Gotham,
        Text                   = text,
        TextColor3             = Theme.Text,
        TextSize               = 13,
        TextWrapped            = true,
        TextXAlignment         = Enum.TextXAlignment.Left,
        Parent                 = card,
    })
    new("UIPadding", {
        PaddingBottom = UDim.new(0, 10),
        Parent        = card,
    })

    tw(card, Tween.Pop, { Position = UDim2.new(0, 0, 0, 0) })

    task.delay(3.6, function()
        if not card.Parent then return end
        local t = tw(card, Tween.Fast, {
            Position               = UDim2.new(1.4, 0, 0, 0),
            BackgroundTransparency = 1,
        })
        t.Completed:Wait()
        card:Destroy()
    end)
end

local function pushLog(line: string)
    table.insert(Log, ("[%s] %s"):format(os.date("%H:%M:%S"), line))
    if #Log > LogCap then table.remove(Log, 1) end
    if logChanged then logChanged:Fire() end
end

-- ╔══════════════════════════════════════════════════════════════════════╗
-- ║  FEATURE LOGIC                                                        ║
-- ╚══════════════════════════════════════════════════════════════════════╝

-- ── Fly  ──  HD Admin–style: upright avatar, camera-yaw facing,
-- smooth lerped velocity. LeftShift acts as a sprint multiplier.
local function startFly()
    local root = hrp()
    local hum  = humanoid()
    if not root or not hum then return end

    local att = new("Attachment", { Name = "AdminFlyAtt", Parent = root }) :: Attachment
    local lv  = new("LinearVelocity", {
        Name           = "AdminFlyLV",
        Attachment0    = att,
        MaxForce       = math.huge,
        VectorVelocity = Vector3.zero,
        RelativeTo     = Enum.ActuatorRelativeTo.World,
        Parent         = root,
    }) :: LinearVelocity
    local ao  = new("AlignOrientation", {
        Name           = "AdminFlyAO",
        Attachment0    = att,
        Mode           = Enum.OrientationAlignmentMode.OneAttachment,
        AlignType      = Enum.AlignType.AllAxes,
        MaxTorque      = math.huge,
        Responsiveness = 90,
        Parent         = root,
    }) :: AlignOrientation

    Maids.fly:give(att); Maids.fly:give(lv); Maids.fly:give(ao)

    -- Hand orientation control to AlignOrientation and let the humanoid
    -- stop fighting the body movers while flying.
    local prevAutoRotate = hum.AutoRotate
    hum.AutoRotate    = false
    hum.PlatformStand = true
    Maids.fly:give(function()
        local h = humanoid()
        if h then
            h.PlatformStand = false
            h.AutoRotate    = prevAutoRotate
        end
    end)

    local currentVel = Vector3.zero
    Maids.fly:give(RunService.RenderStepped:Connect(function(dt: number)
        local cam = Workspace.CurrentCamera
        -- Camera vectors flattened to the XZ plane → character stays upright.
        local fwd  = cam.CFrame.LookVector
        local rgt  = cam.CFrame.RightVector
        local hFwd = Vector3.new(fwd.X, 0, fwd.Z)
        local hRgt = Vector3.new(rgt.X, 0, rgt.Z)
        if hFwd.Magnitude > 0 then hFwd = hFwd.Unit end
        if hRgt.Magnitude > 0 then hRgt = hRgt.Unit end

        local input = Vector3.zero
        if UserInputService:IsKeyDown(Enum.KeyCode.W)            then input += hFwd end
        if UserInputService:IsKeyDown(Enum.KeyCode.S)            then input -= hFwd end
        if UserInputService:IsKeyDown(Enum.KeyCode.A)            then input -= hRgt end
        if UserInputService:IsKeyDown(Enum.KeyCode.D)            then input += hRgt end
        if UserInputService:IsKeyDown(Enum.KeyCode.Space)        then input += Vector3.yAxis end
        if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)  then input -= Vector3.yAxis end

        local sprint = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) and 2 or 1
        local target = (input.Magnitude > 0 and input.Unit or Vector3.zero) * State.flySpeed * sprint
        currentVel   = currentVel:Lerp(target, math.clamp(dt * 9, 0, 1))
        lv.VectorVelocity = currentVel

        if hFwd.Magnitude > 0 then
            ao.CFrame = CFrame.lookAt(Vector3.zero, hFwd)
        end
    end))
end

local function stopFly() Maids.fly:clean() end
local function setFly(on: boolean)
    if State.fly == on then return end
    State.fly = on
    if on then startFly() else stopFly() end
end

-- ── Noclip
local function setNoclip(on: boolean)
    if State.noclip == on then return end
    State.noclip = on
    Maids.noclip:clean()
    if not on then return end
    Maids.noclip:give(RunService.Stepped:Connect(function()
        local c = char(); if not c then return end
        for _, d in ipairs(c:GetDescendants()) do
            if d:IsA("BasePart") and d.CanCollide then d.CanCollide = false end
        end
    end))
end

-- ── Walkspeed / JumpPower / Infinite jump
local function applyWalkSpeed()
    local h = humanoid()
    if h then h.WalkSpeed = State.walkSpeedOn and State.walkSpeed or 16 end
end
local function applyJumpPower()
    local h = humanoid(); if not h then return end
    h.UseJumpPower = true
    h.JumpPower    = State.jumpPowerOn and State.jumpPower or 50
end
local function setInfJump(on: boolean)
    if State.infJump == on then return end
    State.infJump = on
    Maids.infJump:clean()
    if not on then return end
    Maids.infJump:give(UserInputService.JumpRequest:Connect(function()
        local h = humanoid(); if h then h:ChangeState(Enum.HumanoidStateType.Jumping) end
    end))
end

-- ── Local invisibility
-- LocalTransparencyModifier is continuously managed by the camera system
-- (used for first-person occlusion), so we have to reapply every frame to
-- keep the character hidden from the local viewport. This hides you from
-- yourself; other players still see you normally — that's a server-side
-- effect and is intentionally outside the scope of this client-only panel.
local function setInvisible(on: boolean)
    if State.invisible == on then return end
    State.invisible = on
    Maids.invis:clean()
    if not on then
        local c = char(); if not c then return end
        for _, d in ipairs(c:GetDescendants()) do
            if d:IsA("BasePart") then d.LocalTransparencyModifier = 0
            elseif d:IsA("Decal") then d.Transparency             = 0 end
        end
        return
    end
    Maids.invis:give(RunService.RenderStepped:Connect(function()
        local c = char(); if not c then return end
        for _, d in ipairs(c:GetDescendants()) do
            if d:IsA("BasePart") then d.LocalTransparencyModifier = 1
            elseif d:IsA("Decal") then d.Transparency             = 1 end
        end
    end))
end

local function resetChar() local h = humanoid(); if h then h.Health = 0 end end
local function sitNow()    local h = humanoid(); if h then h.Sit = true end end

-- ── Player ops
local function teleportTo(p: Player)
    local me, them = hrp(), p.Character and p.Character:FindFirstChild("HumanoidRootPart")
    if me and them then me.CFrame = them.CFrame * CFrame.new(0, 0, 3) end
end
local function bring(p: Player)
    local me, them = hrp(), p.Character and p.Character:FindFirstChild("HumanoidRootPart")
    if me and them then them.CFrame = me.CFrame * CFrame.new(0, 0, -3) end
end

local frozen: { [Player]: boolean } = {}
local function setFreeze(p: Player, on: boolean)
    local part = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
    if not part then return end
    if on then
        frozen[p] = part.Anchored
        part.Anchored = true
    else
        part.Anchored = frozen[p] or false
        frozen[p] = nil
    end
end

local function setSpectate(p: Player?)
    State.spectating = p
    if p and p.Character then
        local h = p.Character:FindFirstChildOfClass("Humanoid")
        if h then Camera.CameraSubject = h end
    else
        local h = humanoid(); if h then Camera.CameraSubject = h end
    end
end

local function viewAtPlayer(p: Player)
    local part = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
    if part then
        Camera.CameraType = Enum.CameraType.Scriptable
        Camera.CFrame     = CFrame.new(part.Position + Vector3.new(0, 4, 8), part.Position)
        task.delay(2, function() Camera.CameraType = Enum.CameraType.Custom end)
    end
end

-- ── Vehicle
local function getVehicle(): (Model?, VehicleSeat?)
    local c = char(); if not c then return nil, nil end
    local h = c:FindFirstChildOfClass("Humanoid"); if not h then return nil, nil end
    local seat = h.SeatPart
    if not (seat and seat:IsA("VehicleSeat")) then return nil, nil end
    return seat:FindFirstAncestorOfClass("Model"), seat
end
local function applyVehicleTuning()
    local _, seat = getVehicle(); if not seat then return end
    if seat:GetAttribute("AP_origMax") == nil then
        seat:SetAttribute("AP_origMax",    seat.MaxSpeed)
        seat:SetAttribute("AP_origTorque", seat.Torque)
    end
    seat.MaxSpeed = (seat:GetAttribute("AP_origMax")    or 50) * State.vSpeedMult
    seat.Torque   = (seat:GetAttribute("AP_origTorque") or 1)  * (State.vInstant and 4 or 1)
end
local function vehicleBoost()
    local m, s = getVehicle()
    if not m or not s then notify("No vehicle detected", "warn"); return end
    local primary = m.PrimaryPart or s
    primary.AssemblyLinearVelocity += primary.CFrame.LookVector * 90
end
local function setVehicleFly(on: boolean)
    if State.vFly == on then return end
    State.vFly = on
    Maids.vfly:clean()
    if not on then return end

    local m, s = getVehicle()
    if not m or not s then notify("No vehicle detected", "warn"); State.vFly = false; return end
    local primary = m.PrimaryPart or s

    local att = new("Attachment", { Parent = primary }) :: Attachment
    local lv  = new("LinearVelocity", {
        Attachment0    = att,
        MaxForce       = math.huge,
        VectorVelocity = Vector3.zero,
        Parent         = primary,
    }) :: LinearVelocity
    local ao  = new("AlignOrientation", {
        Attachment0    = att,
        Mode           = Enum.OrientationAlignmentMode.OneAttachment,
        MaxTorque      = math.huge,
        Responsiveness = 150,
        AlignType      = Enum.AlignType.AllAxes,
        Parent         = primary,
    }) :: AlignOrientation
    Maids.vfly:give(att); Maids.vfly:give(lv); Maids.vfly:give(ao)

    Maids.vfly:give(RunService.RenderStepped:Connect(function()
        local cam = Workspace.CurrentCamera
        local dir = Vector3.zero
        if UserInputService:IsKeyDown(Enum.KeyCode.W) then dir += cam.CFrame.LookVector  end
        if UserInputService:IsKeyDown(Enum.KeyCode.S) then dir -= cam.CFrame.LookVector  end
        if UserInputService:IsKeyDown(Enum.KeyCode.A) then dir -= cam.CFrame.RightVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.D) then dir += cam.CFrame.RightVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.Space)       then dir += Vector3.yAxis end
        if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then dir -= Vector3.yAxis end
        lv.VectorVelocity = (dir.Magnitude > 0 and dir.Unit or Vector3.zero) * 90 * State.vSpeedMult
        ao.CFrame         = cam.CFrame
    end))
end

-- ── World
local function applyFOV()     if State.fovOn     then Camera.FieldOfView = State.fov     end end
local function applyGravity() if State.gravityOn then Workspace.Gravity  = State.gravity end end
local function setTimeOfDay(h: number) Lighting.ClockTime = h end

-- ── ESP / Tracers
local Highlights:  { [Player]: Highlight } = {}
local TracerLines: { [Player]: Frame }     = {}

local function clearESPFor(p: Player) local h = Highlights[p]; if h then h:Destroy() end; Highlights[p] = nil end
local function attachESPTo(p: Player)
    if p == LocalPlayer or not p.Character then return end
    clearESPFor(p)
    Highlights[p] = new("Highlight", {
        FillColor           = Theme.AccentSoft,
        FillTransparency    = 0.6,
        OutlineColor        = Color3.fromRGB(255, 255, 255),
        OutlineTransparency = 0,
        DepthMode           = Enum.HighlightDepthMode.AlwaysOnTop,
        Adornee             = p.Character,
        Parent              = p.Character,
    }) :: Highlight
end
local function setESP(on: boolean)
    State.esp = on
    for p in pairs(Highlights) do clearESPFor(p) end
    if not on then return end
    for _, p in ipairs(Players:GetPlayers()) do attachESPTo(p) end
end

local function clearTracerFor(p: Player) local l = TracerLines[p]; if l then l:Destroy() end; TracerLines[p] = nil end
local function makeTracerFor(p: Player)
    if p == LocalPlayer then return end
    clearTracerFor(p)
    TracerLines[p] = new("Frame", {
        BackgroundColor3 = Theme.AccentSoft,
        BorderSizePixel  = 0,
        AnchorPoint      = Vector2.new(0.5, 0),
        Parent           = tracerLayer,
    }, { new("UICorner", { CornerRadius = UDim.new(1, 0) }) }) :: Frame
end
local function setTracers(on: boolean)
    State.tracers = on
    Maids.tracers:clean()
    for p in pairs(TracerLines) do clearTracerFor(p) end
    if not on then return end
    for _, p in ipairs(Players:GetPlayers()) do makeTracerFor(p) end
    Maids.tracers:give(RunService.RenderStepped:Connect(function()
        local vp = Camera.ViewportSize
        local ox, oy = vp.X / 2, vp.Y
        for p, line in pairs(TracerLines) do
            local part = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
            if part then
                local screen, onScreen = Camera:WorldToViewportPoint(part.Position)
                if onScreen then
                    local dx, dy = screen.X - ox, screen.Y - oy
                    local dist   = math.sqrt(dx * dx + dy * dy)
                    line.Visible  = true
                    line.Size     = UDim2.fromOffset(2, dist)
                    line.Position = UDim2.fromOffset(ox, oy)
                    line.Rotation = math.deg(math.atan2(dy, dx)) - 90
                else
                    line.Visible = false
                end
            else
                line.Visible = false
            end
        end
    end))
end

-- ── Fullbright
local FBBackup: { [string]: any } = {}
local function setFullbright(on: boolean)
    if State.fullbright == on then return end
    State.fullbright = on
    if on then
        FBBackup = {
            Ambient = Lighting.Ambient, OutdoorAmbient = Lighting.OutdoorAmbient,
            Brightness = Lighting.Brightness, FogEnd = Lighting.FogEnd,
            GlobalShadows = Lighting.GlobalShadows, ClockTime = Lighting.ClockTime,
        }
        Lighting.Ambient        = Color3.fromRGB(180, 180, 180)
        Lighting.OutdoorAmbient = Color3.fromRGB(180, 180, 180)
        Lighting.Brightness     = 2
        Lighting.FogEnd         = 1e5
        Lighting.GlobalShadows  = false
    else
        for k, v in pairs(FBBackup) do (Lighting :: any)[k] = v end
        table.clear(FBBackup)
    end
end

-- ╔══════════════════════════════════════════════════════════════════════╗
-- ║  BACKDROP BLUR (ambient glassmorphism cue)                            ║
-- ╚══════════════════════════════════════════════════════════════════════╝
local panelBlur: BlurEffect?
local function setBackdropBlur(on: boolean)
    if not CONFIG.BackdropBlur then return end
    if on then
        if not panelBlur then
            panelBlur = Instance.new("BlurEffect")
            panelBlur.Name = "AdminPanelBlur"
            panelBlur.Size = 0
            panelBlur.Parent = Lighting
        end
        tw(panelBlur :: BlurEffect, Tween.Med, { Size = CONFIG.BackdropBlurSize })
    elseif panelBlur then
        local b = panelBlur
        panelBlur = nil
        local t = tw(b, Tween.Fast, { Size = 0 })
        t.Completed:Connect(function() b:Destroy() end)
    end
end

-- ╔══════════════════════════════════════════════════════════════════════╗
-- ║  PANEL CHROME                                                         ║
-- ╚══════════════════════════════════════════════════════════════════════╝

local panel = new("Frame", {
    Name                   = "Panel",
    AnchorPoint            = Vector2.new(0.5, 0.5),
    Position               = UDim2.fromScale(0.5, 0.5),
    Size                   = UDim2.fromOffset(CONFIG.PanelSize.X, CONFIG.PanelSize.Y),
    BackgroundColor3       = Theme.Bg,
    BackgroundTransparency = CONFIG.BackgroundAlpha,
    BorderSizePixel        = 0,
    Visible                = false,
    Active                 = true,
    ClipsDescendants       = true,
    ZIndex                 = 2,
    Parent                 = gui,
}, {
    new("UICorner", { CornerRadius = UDim.new(0, 16) }),
    new("UIStroke", {
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
        Color           = Theme.Border,
        Thickness       = 1,
        Transparency    = 0.25,
    }),
    new("UIGradient", {
        Rotation = 115,
        Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Color3.fromRGB(30, 35, 50)),
            ColorSequenceKeypoint.new(0.5, Color3.fromRGB(16, 18, 26)),
            ColorSequenceKeypoint.new(1, Color3.fromRGB(10, 11, 18)),
        }),
    }),
}) :: Frame

-- Layered: drop shadow + outer accent glow halo
local shadowImg = dropShadow(panel, { Spread = 80, Transparency = 0.4, Y = 12 })
local haloImg   = new("ImageLabel", {
    Name                   = "Halo",
    BackgroundTransparency = 1,
    Image                  = Asset.SoftGlow,
    ImageColor3            = Theme.Accent,
    ImageTransparency      = 0.85,
    ScaleType              = Enum.ScaleType.Slice,
    SliceCenter            = Asset.SoftGlowSlice,
    AnchorPoint            = Vector2.new(0.5, 0.5),
    Position               = UDim2.fromScale(0.5, 0.5),
    Size                   = UDim2.new(1, 80, 1, 80),
    ZIndex                 = 1,
    Parent                 = gui,
}) :: ImageLabel
follow(haloImg, "ImageColor3")

-- Halo + shadow tail the panel
local function trackPanel()
    haloImg.Position   = panel.Position
    haloImg.Size       = UDim2.fromOffset(panel.AbsoluteSize.X + 80, panel.AbsoluteSize.Y + 80)
    shadowImg.Position = UDim2.fromOffset(panel.AbsolutePosition.X + panel.AbsoluteSize.X * 0.5,
                                          panel.AbsolutePosition.Y + panel.AbsoluteSize.Y * 0.5 + 12)
    shadowImg.Size     = UDim2.fromOffset(panel.AbsoluteSize.X + 80, panel.AbsoluteSize.Y + 80)
end

-- Title bar ────────────────────────────────────────────────────────────
local titleBar = new("Frame", {
    Name                   = "TitleBar",
    BackgroundTransparency = 1,
    Size                   = UDim2.new(1, 0, 0, 50),
    ZIndex                 = 3,
    Parent                 = panel,
}) :: Frame

-- Avatar
local avatarBox = new("Frame", {
    Name             = "Avatar",
    AnchorPoint      = Vector2.new(0, 0.5),
    Position         = UDim2.new(0, 16, 0.5, 0),
    Size             = UDim2.fromOffset(32, 32),
    BackgroundColor3 = Theme.Bg3,
    BorderSizePixel  = 0,
    Parent           = titleBar,
}, {
    new("UICorner", { CornerRadius = UDim.new(1, 0) }),
    new("UIStroke", { Color = Theme.Accent, Thickness = 1.5, Transparency = 0.2 }),
    new("ImageLabel", {
        Name                   = "Image",
        BackgroundTransparency = 1,
        Image                  = avatarFor(LocalPlayer.UserId),
        Size                   = UDim2.fromScale(1, 1),
    }),
}) :: Frame
follow(avatarBox:FindFirstChildOfClass("UIStroke") :: Instance, "Color")

new("TextLabel", {
    BackgroundTransparency = 1,
    Position               = UDim2.new(0, 58, 0, 6),
    Size                   = UDim2.new(0.5, 0, 0, 22),
    Font                   = Enum.Font.GothamBold,
    Text                   = CONFIG.PanelTitle,
    TextColor3             = Theme.Text,
    TextSize               = 15,
    TextXAlignment         = Enum.TextXAlignment.Left,
    Parent                 = titleBar,
})
new("TextLabel", {
    Name                   = "Sub",
    BackgroundTransparency = 1,
    Position               = UDim2.new(0, 58, 0, 26),
    Size                   = UDim2.new(0.5, 0, 0, 16),
    Font                   = Enum.Font.Gotham,
    Text                   = ("%s · %s"):format(LocalPlayer.DisplayName, rankOf(LocalPlayer.Name)),
    TextColor3             = Theme.TextDim,
    TextSize               = 12,
    TextXAlignment         = Enum.TextXAlignment.Left,
    Parent                 = titleBar,
})

local function titleBtn(label: string, glyph: string, offX: number, hover: Color3): TextButton
    local b = new("TextButton", {
        Name                   = label,
        AnchorPoint            = Vector2.new(1, 0.5),
        Position               = UDim2.new(1, offX, 0.5, 0),
        Size                   = UDim2.fromOffset(30, 30),
        BackgroundColor3       = Theme.Bg3,
        BackgroundTransparency = 0.15,
        BorderSizePixel        = 0,
        Font                   = Enum.Font.GothamBold,
        Text                   = glyph,
        TextColor3             = Theme.Text,
        TextSize               = 14,
        AutoButtonColor        = false,
        Parent                 = titleBar,
    }, {
        new("UICorner", { CornerRadius = UDim.new(0, 8) }),
        new("UIStroke", { Color = Theme.BorderSoft, Transparency = 0.4 }),
    }) :: TextButton
    b.MouseEnter:Connect(function() tw(b, Tween.Fast, { BackgroundColor3 = hover }) end)
    b.MouseLeave:Connect(function() tw(b, Tween.Fast, { BackgroundColor3 = Theme.Bg3 }) end)
    return b
end

local minBtn   = titleBtn("Minimize", "–", -54, Theme.Bg4)
local closeBtn = titleBtn("Close",    "×", -16, Theme.Err)

-- Sidebar ──────────────────────────────────────────────────────────────
local sidebar = glassSurface({
    Name                   = "Sidebar",
    BackgroundColor3       = Theme.Bg2,
    BackgroundTransparency = 0.15,
    Position               = UDim2.new(0, 12, 0, 58),
    Size                   = UDim2.new(0, 150, 1, -116),
    ZIndex                 = 3,
    Parent                 = panel,
    Radius                 = 12,
}, {
    new("UIPadding", {
        PaddingTop    = UDim.new(0, 10), PaddingBottom = UDim.new(0, 10),
        PaddingLeft   = UDim.new(0, 8),  PaddingRight  = UDim.new(0, 8),
    }),
    new("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }),
})

-- Content ──────────────────────────────────────────────────────────────
local content = glassSurface({
    Name                   = "Content",
    BackgroundColor3       = Theme.Bg2,
    BackgroundTransparency = 0.22,
    Position               = UDim2.new(0, 170, 0, 58),
    Size                   = UDim2.new(1, -182, 1, -116),
    ClipsDescendants       = true,
    ZIndex                 = 3,
    Parent                 = panel,
    Radius                 = 12,
})

-- Command bar ──────────────────────────────────────────────────────────
local cmdBar = glassSurface({
    Name                   = "Cmd",
    BackgroundColor3       = Theme.Bg2,
    BackgroundTransparency = 0.18,
    Position               = UDim2.new(0, 12, 1, -48),
    Size                   = UDim2.new(1, -24, 0, 36),
    ZIndex                 = 3,
    Parent                 = panel,
    Radius                 = 12,
})

new("Frame", {
    Name             = "PrefixDot",
    AnchorPoint      = Vector2.new(0, 0.5),
    Position         = UDim2.new(0, 14, 0.5, 0),
    Size             = UDim2.fromOffset(6, 6),
    BackgroundColor3 = Theme.Accent,
    BorderSizePixel  = 0,
    Parent           = cmdBar,
}, { new("UICorner", { CornerRadius = UDim.new(1, 0) }) })
follow(cmdBar:FindFirstChild("PrefixDot") :: Frame)

new("TextLabel", {
    BackgroundTransparency = 1,
    Position               = UDim2.new(0, 26, 0, 0),
    Size                   = UDim2.new(0, 16, 1, 0),
    Font                   = Enum.Font.GothamBold,
    Text                   = CONFIG.CommandPrefix,
    TextColor3             = Theme.Accent,
    TextSize               = 14,
    Parent                 = cmdBar,
})
local prefixGlyph = cmdBar:FindFirstChildOfClass("TextLabel") :: TextLabel
follow(prefixGlyph, "TextColor3")

local cmdInput = new("TextBox", {
    BackgroundTransparency = 1,
    Position               = UDim2.new(0, 44, 0, 0),
    Size                   = UDim2.new(1, -54, 1, 0),
    Font                   = Enum.Font.Gotham,
    PlaceholderText        = "type a command — e.g. fly, ws 80, tp Builderman",
    PlaceholderColor3      = Theme.TextMuted,
    Text                   = "",
    TextColor3             = Theme.Text,
    TextSize               = 13,
    TextXAlignment         = Enum.TextXAlignment.Left,
    ClearTextOnFocus       = false,
    Parent                 = cmdBar,
}) :: TextBox

-- ── Drag (title bar)
do
    local dragging, startMouse, startPos
    titleBar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            dragging   = true
            startMouse = input.Position
            startPos   = panel.Position
            local conn
            conn = input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false; if conn then conn:Disconnect() end
                end
            end)
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if not dragging then return end
        if input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch then
            local d = input.Position - startMouse
            panel.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + d.X,
                startPos.Y.Scale, startPos.Y.Offset + d.Y
            )
        end
    end)
end

-- ── Resize handle (bottom-right)
local resizeHandle = new("ImageButton", {
    Name             = "Resize",
    AnchorPoint      = Vector2.new(1, 1),
    Position         = UDim2.new(1, -6, 1, -6),
    Size             = UDim2.fromOffset(14, 14),
    BackgroundTransparency = 1,
    Image            = "",
    AutoButtonColor  = false,
    ZIndex           = 5,
    Parent           = panel,
}) :: ImageButton
for i = 0, 2 do
    new("Frame", {
        AnchorPoint      = Vector2.new(1, 1),
        Position         = UDim2.new(1, 0, 1, -i * 4),
        Size             = UDim2.fromOffset(2 + i * 4, 2),
        BackgroundColor3 = Theme.TextDim,
        BorderSizePixel  = 0,
        Parent           = resizeHandle,
    }, { new("UICorner", { CornerRadius = UDim.new(1, 0) }) })
end

local livePanelSize = CONFIG.PanelSize
do
    local resizing, startMouse, startSize
    resizeHandle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            resizing   = true
            startMouse = input.Position
            startSize  = panel.AbsoluteSize
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if not resizing then return end
        if input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch then
            local d = input.Position - startMouse
            local w = math.clamp(startSize.X + d.X, CONFIG.PanelMinSize.X, CONFIG.PanelMaxSize.X)
            local h = math.clamp(startSize.Y + d.Y, CONFIG.PanelMinSize.Y, CONFIG.PanelMaxSize.Y)
            panel.Size      = UDim2.fromOffset(w, h)
            livePanelSize   = Vector2.new(w, h)
        end
    end)
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            resizing = false
        end
    end)
end

-- ╔══════════════════════════════════════════════════════════════════════╗
-- ║  COMPONENTS                                                           ║
-- ╚══════════════════════════════════════════════════════════════════════╝

local function header(parent: Instance, text: string)
    local h = new("Frame", {
        BackgroundTransparency = 1,
        Size                   = UDim2.new(1, 0, 0, 24),
        Parent                 = parent,
    })
    new("Frame", {
        BackgroundColor3 = Theme.Accent,
        BorderSizePixel  = 0,
        Position         = UDim2.new(0, 0, 0, 8),
        Size             = UDim2.fromOffset(3, 12),
        Parent           = h,
    }, { new("UICorner", { CornerRadius = UDim.new(0, 2) }) })
    follow(h:FindFirstChildOfClass("Frame") :: Frame)
    new("TextLabel", {
        BackgroundTransparency = 1,
        Position               = UDim2.new(0, 12, 0, 0),
        Size                   = UDim2.new(1, -12, 1, 0),
        Font                   = Enum.Font.GothamBold,
        Text                   = text:upper(),
        TextColor3             = Theme.TextDim,
        TextSize               = 11,
        TextXAlignment         = Enum.TextXAlignment.Left,
        Parent                 = h,
    })
end

local function divider(parent: Instance)
    new("Frame", {
        BackgroundColor3       = Theme.BorderSoft,
        BackgroundTransparency = 0.6,
        BorderSizePixel        = 0,
        Size                   = UDim2.new(1, 0, 0, 1),
        Parent                 = parent,
    })
end

-- Toggle: pill track + neon glow when on
local function Toggle(parent: Instance, label: string, onChange: (boolean) -> ())
    local row = glassSurface({
        BackgroundColor3       = Theme.Bg3,
        BackgroundTransparency = 0.2,
        Size                   = UDim2.new(1, 0, 0, 40),
        Parent                 = parent,
        Radius                 = 10,
    })

    new("TextLabel", {
        BackgroundTransparency = 1,
        Position               = UDim2.new(0, 16, 0, 0),
        Size                   = UDim2.new(1, -72, 1, 0),
        Font                   = Enum.Font.GothamMedium,
        Text                   = label,
        TextColor3             = Theme.Text,
        TextSize               = 13,
        TextXAlignment         = Enum.TextXAlignment.Left,
        Parent                 = row,
    })

    local track = new("Frame", {
        AnchorPoint            = Vector2.new(1, 0.5),
        Position               = UDim2.new(1, -14, 0.5, 0),
        Size                   = UDim2.fromOffset(42, 22),
        BackgroundColor3       = Color3.fromRGB(48, 52, 66),
        BorderSizePixel        = 0,
        Parent                 = row,
    }, {
        new("UICorner", { CornerRadius = UDim.new(1, 0) }),
        new("UIStroke", { Color = Theme.BorderSoft, Transparency = 0.4 }),
    }) :: Frame

    local glowImg = new("ImageLabel", {
        Name                   = "Glow",
        BackgroundTransparency = 1,
        Image                  = Asset.SoftGlow,
        ImageColor3            = Theme.Accent,
        ImageTransparency      = 1,
        ScaleType              = Enum.ScaleType.Slice,
        SliceCenter            = Asset.SoftGlowSlice,
        AnchorPoint            = Vector2.new(0.5, 0.5),
        Position               = UDim2.fromScale(0.5, 0.5),
        Size                   = UDim2.new(1, 20, 1, 20),
        Parent                 = track,
    }) :: ImageLabel
    follow(glowImg, "ImageColor3")

    local knob = new("Frame", {
        AnchorPoint      = Vector2.new(0, 0.5),
        Position         = UDim2.new(0, 2, 0.5, 0),
        Size             = UDim2.fromOffset(18, 18),
        BackgroundColor3 = Theme.Text,
        BorderSizePixel  = 0,
        Parent           = track,
    }, {
        new("UICorner", { CornerRadius = UDim.new(1, 0) }),
        new("UIStroke", { Color = Color3.fromRGB(255, 255, 255), Transparency = 0.7 }),
    }) :: Frame

    local btn = new("TextButton", {
        BackgroundTransparency = 1, Text = "",
        Size = UDim2.fromScale(1, 1), Parent = row,
    }) :: TextButton

    local value = false
    local function apply(v: boolean, silent: boolean?)
        value = v
        tw(track, Tween.Fast, {
            BackgroundColor3 = v and liveAccent or Color3.fromRGB(48, 52, 66),
        })
        tw(knob, Tween.Fast, {
            Position = v and UDim2.new(1, -20, 0.5, 0) or UDim2.new(0, 2, 0.5, 0),
        })
        tw(glowImg, Tween.Med, { ImageTransparency = v and 0.55 or 1 })
        if v then follow(track) else accentFollowers[track] = nil end
        if not silent then onChange(v) end
    end

    btn.MouseButton1Click:Connect(function() apply(not value) end)
    return { set = apply, get = function() return value end }
end

-- Slider with animated thumb + gradient track fill
local function Slider(parent: Instance, label: string,
                      min: number, max: number, default: number, step: number?,
                      onChange: (number) -> ())
    step = step or 1
    local container = glassSurface({
        BackgroundColor3       = Theme.Bg3,
        BackgroundTransparency = 0.2,
        Size                   = UDim2.new(1, 0, 0, 58),
        Parent                 = parent,
        Radius                 = 10,
    }, {
        new("UIPadding", {
            PaddingLeft = UDim.new(0, 16), PaddingRight = UDim.new(0, 16),
            PaddingTop  = UDim.new(0, 10), PaddingBottom = UDim.new(0, 10),
        }),
    })

    new("TextLabel", {
        BackgroundTransparency = 1,
        Size                   = UDim2.new(0.6, 0, 0, 18),
        Font                   = Enum.Font.GothamMedium,
        Text                   = label,
        TextColor3             = Theme.Text,
        TextSize               = 13,
        TextXAlignment         = Enum.TextXAlignment.Left,
        Parent                 = container,
    })
    local valueLbl = new("TextLabel", {
        BackgroundTransparency = 1,
        AnchorPoint            = Vector2.new(1, 0),
        Position               = UDim2.new(1, 0, 0, 0),
        Size                   = UDim2.new(0.4, 0, 0, 18),
        Font                   = Enum.Font.GothamBold,
        Text                   = tostring(default),
        TextColor3             = Theme.Accent,
        TextSize               = 13,
        TextXAlignment         = Enum.TextXAlignment.Right,
        Parent                 = container,
    }) :: TextLabel
    follow(valueLbl, "TextColor3")

    local track = new("Frame", {
        Position         = UDim2.new(0, 0, 0, 28),
        Size             = UDim2.new(1, 0, 0, 6),
        BackgroundColor3 = Color3.fromRGB(40, 44, 58),
        BorderSizePixel  = 0,
        Parent           = container,
    }, {
        new("UICorner", { CornerRadius = UDim.new(1, 0) }),
        new("UIStroke", { Color = Theme.BorderSoft, Transparency = 0.5 }),
    }) :: Frame

    local fill = new("Frame", {
        Size             = UDim2.new((default - min) / (max - min), 0, 1, 0),
        BackgroundColor3 = Theme.Accent,
        BorderSizePixel  = 0,
        Parent           = track,
    }, {
        new("UICorner", { CornerRadius = UDim.new(1, 0) }),
        new("UIGradient", {
            Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0, Theme.AccentDeep),
                ColorSequenceKeypoint.new(1, Theme.AccentSoft),
            }),
        }),
    }) :: Frame
    follow(fill)

    local thumb = new("Frame", {
        AnchorPoint            = Vector2.new(0.5, 0.5),
        Position               = UDim2.new(fill.Size.X.Scale, 0, 0.5, 0),
        Size                   = UDim2.fromOffset(14, 14),
        BackgroundColor3       = Color3.fromRGB(255, 255, 255),
        BorderSizePixel        = 0,
        ZIndex                 = 2,
        Parent                 = track,
    }, {
        new("UICorner", { CornerRadius = UDim.new(1, 0) }),
        new("UIStroke", { Color = Theme.Accent, Thickness = 2, Transparency = 0.2 }),
    }) :: Frame
    follow(thumb:FindFirstChildOfClass("UIStroke") :: Instance, "Color")

    local dragging = false
    local function set(x: number, silent: boolean?)
        local rel = math.clamp((x - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
        local v   = min + (max - min) * rel
        v = math.floor(v / step + 0.5) * step
        v = math.clamp(v, min, max)
        local r = (v - min) / (max - min)
        tw(fill,  Tween.Snap, { Size = UDim2.new(r, 0, 1, 0) })
        tw(thumb, Tween.Snap, { Position = UDim2.new(r, 0, 0.5, 0) })
        valueLbl.Text = tostring(v)
        if not silent then onChange(v) end
    end

    track.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            tw(thumb, Tween.Fast, { Size = UDim2.fromOffset(18, 18) })
            set(input.Position.X)
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if not dragging then return end
        if input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch then
            set(input.Position.X)
        end
    end)
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            if dragging then tw(thumb, Tween.Fast, { Size = UDim2.fromOffset(14, 14) }) end
            dragging = false
        end
    end)
end

-- Button with hover lift + ripple + neon glow on hover
local function Button(parent: Instance, label: string, onClick: () -> ())
    local b = new("TextButton", {
        BackgroundColor3       = Theme.Bg3,
        BackgroundTransparency = 0.15,
        BorderSizePixel        = 0,
        Size                   = UDim2.new(1, 0, 0, 34),
        Font                   = Enum.Font.GothamMedium,
        Text                   = label,
        TextColor3             = Theme.Text,
        TextSize               = 13,
        AutoButtonColor        = false,
        ClipsDescendants       = true,
        Parent                 = parent,
    }, {
        new("UICorner", { CornerRadius = UDim.new(0, 10) }),
        new("UIStroke", { Color = Theme.BorderSoft, Transparency = 0.4 }),
    }) :: TextButton

    local glow = new("ImageLabel", {
        BackgroundTransparency = 1,
        Image                  = Asset.SoftGlow,
        ImageColor3            = Theme.Accent,
        ImageTransparency      = 1,
        ScaleType              = Enum.ScaleType.Slice,
        SliceCenter            = Asset.SoftGlowSlice,
        AnchorPoint            = Vector2.new(0.5, 0.5),
        Position               = UDim2.fromScale(0.5, 0.5),
        Size                   = UDim2.new(1, 30, 1, 30),
        ZIndex                 = 0,
        Parent                 = b,
    }) :: ImageLabel
    follow(glow, "ImageColor3")

    b.MouseEnter:Connect(function()
        tw(b,    Tween.Fast, { BackgroundColor3 = liveAccent })
        tw(glow, Tween.Fast, { ImageTransparency = 0.55 })
    end)
    b.MouseLeave:Connect(function()
        tw(b,    Tween.Fast, { BackgroundColor3 = Theme.Bg3 })
        tw(glow, Tween.Fast, { ImageTransparency = 1 })
    end)
    b.MouseButton1Down:Connect(function(x, y)
        ripple(b, x - b.AbsolutePosition.X, y - b.AbsolutePosition.Y)
    end)
    b.MouseButton1Click:Connect(function()
        if not rate("btn:" .. label, 0.1) then return end
        safe(onClick)
    end)
    return b
end

-- ╔══════════════════════════════════════════════════════════════════════╗
-- ║  TABS                                                                 ║
-- ╚══════════════════════════════════════════════════════════════════════╝
local tabs: { [string]: { button: TextButton, page: ScrollingFrame, indicator: Frame } } = {}
local currentTab: string? = nil

local function makeTab(id: string, icon: string, label: string): ScrollingFrame
    local btn = new("TextButton", {
        Name                   = "Tab_" .. id,
        BackgroundColor3       = Theme.Bg3,
        BackgroundTransparency = 1,
        BorderSizePixel        = 0,
        Size                   = UDim2.new(1, 0, 0, 34),
        Text                   = "",
        AutoButtonColor        = false,
        Parent                 = sidebar,
    }, { new("UICorner", { CornerRadius = UDim.new(0, 8) }) }) :: TextButton

    local indicator = new("Frame", {
        BackgroundColor3 = Theme.Accent,
        BorderSizePixel  = 0,
        Position         = UDim2.new(0, 0, 0.5, -8),
        Size             = UDim2.new(0, 0, 0, 16),
        Parent           = btn,
    }, { new("UICorner", { CornerRadius = UDim.new(0, 2) }) }) :: Frame
    follow(indicator)

    new("TextLabel", {
        Name                   = "Icon",
        BackgroundTransparency = 1,
        Position               = UDim2.new(0, 12, 0, 0),
        Size                   = UDim2.new(0, 22, 1, 0),
        Font                   = Enum.Font.GothamBold,
        Text                   = icon,
        TextColor3             = Theme.TextDim,
        TextSize               = 14,
        Parent                 = btn,
    })
    new("TextLabel", {
        Name                   = "Label",
        BackgroundTransparency = 1,
        Position               = UDim2.new(0, 36, 0, 0),
        Size                   = UDim2.new(1, -40, 1, 0),
        Font                   = Enum.Font.GothamMedium,
        Text                   = label,
        TextColor3             = Theme.TextDim,
        TextSize               = 13,
        TextXAlignment         = Enum.TextXAlignment.Left,
        Parent                 = btn,
    })

    local page = new("ScrollingFrame", {
        Name                   = "Page_" .. id,
        BackgroundTransparency = 1,
        BorderSizePixel        = 0,
        Size                   = UDim2.fromScale(1, 1),
        CanvasSize             = UDim2.new(),
        AutomaticCanvasSize    = Enum.AutomaticSize.Y,
        ScrollBarThickness     = 3,
        ScrollBarImageColor3   = Theme.Accent,
        ScrollingDirection     = Enum.ScrollingDirection.Y,
        Visible                = false,
        Parent                 = content,
    }, {
        new("UIPadding", {
            PaddingTop = UDim.new(0, 14), PaddingBottom = UDim.new(0, 16),
            PaddingLeft = UDim.new(0, 16), PaddingRight = UDim.new(0, 16),
        }),
        new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }),
    }) :: ScrollingFrame

    tabs[id] = { button = btn, page = page, indicator = indicator }

    btn.MouseEnter:Connect(function()
        if currentTab ~= id then tw(btn, Tween.Fast, { BackgroundTransparency = 0.4 }) end
    end)
    btn.MouseLeave:Connect(function()
        if currentTab ~= id then tw(btn, Tween.Fast, { BackgroundTransparency = 1 }) end
    end)
    return page
end

local function selectTab(id: string)
    if currentTab == id then return end
    local previous = currentTab
    currentTab = id
    for n, t in pairs(tabs) do
        local active = (n == id)
        tw(t.button, Tween.Fast, {
            BackgroundTransparency = active and 0.18 or 1,
        })
        local iconLbl  = t.button:FindFirstChild("Icon")  :: TextLabel?
        local labelLbl = t.button:FindFirstChild("Label") :: TextLabel?
        if iconLbl  then tw(iconLbl,  Tween.Fast, { TextColor3 = active and Theme.Text or Theme.TextDim }) end
        if labelLbl then tw(labelLbl, Tween.Fast, { TextColor3 = active and Theme.Text or Theme.TextDim }) end
        tw(t.indicator, Tween.Fast, { Size = UDim2.new(0, active and 3 or 0, 0, 16) })
    end
    for _, t in pairs(tabs) do
        if t.page.Visible and t.page ~= tabs[id].page then
            t.page.Visible = false
        end
    end
    local p = tabs[id].page
    p.Position = UDim2.new(0, 12, 0, 0)
    p.Visible  = true
    tw(p, Tween.Med, { Position = UDim2.new(0, 0, 0, 0) })
end

-- ╔══════════════════════════════════════════════════════════════════════╗
-- ║  TAB CONTENT                                                          ║
-- ╚══════════════════════════════════════════════════════════════════════╝

-- ── SELF
local selfPage = makeTab("self", "◉", "Self")
header(selfPage, "Mobility")
Toggle(selfPage, "Fly  (WASD + Space/Ctrl)", function(v)
    setFly(v); pushLog(("fly %s"):format(tostring(v))); notify("Fly " .. (v and "on" or "off"), v and "ok" or "info")
end)
Toggle(selfPage, "Noclip", function(v)
    setNoclip(v); pushLog(("noclip %s"):format(tostring(v))); notify("Noclip " .. (v and "on" or "off"), v and "ok" or "info")
end)
Toggle(selfPage, "Infinite Jump", function(v) setInfJump(v); pushLog("infjump " .. tostring(v)) end)
Slider(selfPage, "Fly Speed", 20, 500, State.flySpeed, 5, function(v) State.flySpeed = v end)
Slider(selfPage, "Walk Speed", 16, 500, State.walkSpeed, 2, function(v)
    State.walkSpeed = v; State.walkSpeedOn = true; applyWalkSpeed()
end)
Slider(selfPage, "Jump Power", 50, 500, State.jumpPower, 5, function(v)
    State.jumpPower = v; State.jumpPowerOn = true; applyJumpPower()
end)

header(selfPage, "Status")
Toggle(selfPage, "Invisible (local view)", function(v) setInvisible(v); pushLog("invis " .. tostring(v)) end)
Button(selfPage, "Reset Character", function() resetChar(); notify("Reset", "info") end)
Button(selfPage, "Sit",             function() sitNow() end)

-- ── PLAYERS
local playersPage = makeTab("players", "◈", "Players")

local targetCard = glassSurface({
    BackgroundColor3       = Theme.Bg3,
    BackgroundTransparency = 0.2,
    Size                   = UDim2.new(1, 0, 0, 56),
    Parent                 = playersPage,
    Radius                 = 10,
})

local targetAvatar = new("Frame", {
    AnchorPoint      = Vector2.new(0, 0.5),
    Position         = UDim2.new(0, 12, 0.5, 0),
    Size             = UDim2.fromOffset(36, 36),
    BackgroundColor3 = Theme.Bg2,
    BorderSizePixel  = 0,
    Parent           = targetCard,
}, {
    new("UICorner", { CornerRadius = UDim.new(1, 0) }),
    new("UIStroke", { Color = Theme.BorderSoft, Transparency = 0.3 }),
    new("ImageLabel", {
        Name = "Image", Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1, Image = "",
    }),
}) :: Frame

local targetName = new("TextLabel", {
    BackgroundTransparency = 1,
    Position               = UDim2.new(0, 58, 0, 8),
    Size                   = UDim2.new(1, -68, 0, 20),
    Font                   = Enum.Font.GothamBold,
    Text                   = "No target selected",
    TextColor3             = Theme.Text,
    TextSize               = 14,
    TextXAlignment         = Enum.TextXAlignment.Left,
    Parent                 = targetCard,
}) :: TextLabel
local targetSub = new("TextLabel", {
    BackgroundTransparency = 1,
    Position               = UDim2.new(0, 58, 0, 28),
    Size                   = UDim2.new(1, -68, 0, 18),
    Font                   = Enum.Font.Gotham,
    Text                   = "Pick a player from the list below",
    TextColor3             = Theme.TextDim,
    TextSize               = 12,
    TextXAlignment         = Enum.TextXAlignment.Left,
    Parent                 = targetCard,
}) :: TextLabel

-- Search box with icon
local searchBox = glassSurface({
    BackgroundColor3       = Theme.Bg3,
    BackgroundTransparency = 0.2,
    Size                   = UDim2.new(1, 0, 0, 34),
    Parent                 = playersPage,
    Radius                 = 10,
})

new("ImageLabel", {
    BackgroundTransparency = 1,
    AnchorPoint            = Vector2.new(0, 0.5),
    Position               = UDim2.new(0, 10, 0.5, 0),
    Size                   = UDim2.fromOffset(14, 14),
    Image                  = Asset.SearchIcon,
    ImageRectOffset        = Vector2.new(964, 324),
    ImageRectSize          = Vector2.new(36, 36),
    ImageColor3            = Theme.TextDim,
    Parent                 = searchBox,
})

local searchInput = new("TextBox", {
    BackgroundTransparency = 1,
    Position               = UDim2.new(0, 32, 0, 0),
    Size                   = UDim2.new(1, -42, 1, 0),
    Font                   = Enum.Font.Gotham,
    PlaceholderText        = "search players…",
    PlaceholderColor3      = Theme.TextMuted,
    Text                   = "",
    TextColor3             = Theme.Text,
    TextSize               = 13,
    TextXAlignment         = Enum.TextXAlignment.Left,
    ClearTextOnFocus       = false,
    Parent                 = searchBox,
}) :: TextBox

local listBox = glassSurface({
    BackgroundColor3       = Theme.Bg3,
    BackgroundTransparency = 0.2,
    Size                   = UDim2.new(1, 0, 0, 180),
    Parent                 = playersPage,
    Radius                 = 10,
})

local listScroll = new("ScrollingFrame", {
    BackgroundTransparency = 1,
    Size                   = UDim2.fromScale(1, 1),
    BorderSizePixel        = 0,
    CanvasSize             = UDim2.new(),
    AutomaticCanvasSize    = Enum.AutomaticSize.Y,
    ScrollBarThickness     = 3,
    ScrollBarImageColor3   = Theme.Accent,
    Parent                 = listBox,
}, {
    new("UIListLayout", { Padding = UDim.new(0, 4) }),
    new("UIPadding", {
        PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6),
        PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6),
    }),
}) :: ScrollingFrame

local function setTarget(p: Player?)
    State.target = p
    if p then
        (targetAvatar:FindFirstChild("Image") :: ImageLabel).Image = avatarFor(p.UserId)
        targetName.Text = ("%s  (@%s)"):format(p.DisplayName, p.Name)
        targetSub.Text  = ("UserId %d · ping %d ms"):format(p.UserId, math.floor(p:GetNetworkPing() * 1000))
    else
        (targetAvatar:FindFirstChild("Image") :: ImageLabel).Image = ""
        targetName.Text = "No target selected"
        targetSub.Text  = "Pick a player from the list below"
    end
end

local function makePlayerRow(p: Player): TextButton
    local row = new("TextButton", {
        BackgroundColor3       = Theme.Bg2,
        BackgroundTransparency = 0.2,
        BorderSizePixel        = 0,
        Size                   = UDim2.new(1, 0, 0, 36),
        Text                   = "",
        AutoButtonColor        = false,
        Parent                 = listScroll,
        ClipsDescendants       = true,
    }, {
        new("UICorner", { CornerRadius = UDim.new(0, 8) }),
        new("UIStroke", { Color = Theme.BorderSoft, Transparency = 0.5 }),
    }) :: TextButton

    -- Avatar
    new("Frame", {
        AnchorPoint      = Vector2.new(0, 0.5),
        Position         = UDim2.new(0, 6, 0.5, 0),
        Size             = UDim2.fromOffset(26, 26),
        BackgroundColor3 = Theme.Bg3,
        BorderSizePixel  = 0,
        Parent           = row,
    }, {
        new("UICorner", { CornerRadius = UDim.new(1, 0) }),
        new("ImageLabel", {
            BackgroundTransparency = 1,
            Size                   = UDim2.fromScale(1, 1),
            Image                  = avatarFor(p.UserId),
        }),
    })

    -- Status dot
    new("Frame", {
        AnchorPoint      = Vector2.new(1, 0.5),
        Position         = UDim2.new(1, -12, 0.5, 0),
        Size             = UDim2.fromOffset(8, 8),
        BackgroundColor3 = Theme.Ok,
        BorderSizePixel  = 0,
        Parent           = row,
    }, { new("UICorner", { CornerRadius = UDim.new(1, 0) }) })

    new("TextLabel", {
        BackgroundTransparency = 1,
        Position               = UDim2.new(0, 40, 0, 4),
        Size                   = UDim2.new(1, -60, 0, 16),
        Font                   = Enum.Font.GothamMedium,
        Text                   = p.DisplayName,
        TextColor3             = Theme.Text,
        TextSize               = 13,
        TextXAlignment         = Enum.TextXAlignment.Left,
        Parent                 = row,
    })
    new("TextLabel", {
        BackgroundTransparency = 1,
        Position               = UDim2.new(0, 40, 0, 18),
        Size                   = UDim2.new(1, -60, 0, 14),
        Font                   = Enum.Font.Gotham,
        Text                   = "@" .. p.Name,
        TextColor3             = Theme.TextDim,
        TextSize               = 11,
        TextXAlignment         = Enum.TextXAlignment.Left,
        Parent                 = row,
    })

    row.MouseEnter:Connect(function() tw(row, Tween.Fast, { BackgroundColor3 = Theme.Bg4 }) end)
    row.MouseLeave:Connect(function() tw(row, Tween.Fast, { BackgroundColor3 = Theme.Bg2 }) end)
    row.MouseButton1Down:Connect(function(x, y)
        ripple(row, x - row.AbsolutePosition.X, y - row.AbsolutePosition.Y)
    end)
    row.MouseButton1Click:Connect(function() setTarget(p) end)
    return row
end

local refreshList: () -> ()
do
    local pending = false
    refreshList = function()
        if pending then return end
        pending = true
        task.defer(function()
            pending = false
            local q = searchInput.Text:lower()
            for _, c in ipairs(listScroll:GetChildren()) do
                if c:IsA("TextButton") then c:Destroy() end
            end
            for _, p in ipairs(Players:GetPlayers()) do
                if p ~= LocalPlayer
                and (q == "" or p.Name:lower():find(q, 1, true) or p.DisplayName:lower():find(q, 1, true)) then
                    makePlayerRow(p)
                end
            end
        end)
    end
end

searchInput:GetPropertyChangedSignal("Text"):Connect(refreshList)

header(playersPage, "Target Actions")
local function require_target(fn)
    return function()
        if State.target then fn(State.target) else notify("Select a player first", "warn") end
    end
end
Button(playersPage, "Teleport to Player", require_target(function(p) teleportTo(p);    pushLog("tp " .. p.Name);     notify("→ " .. p.Name, "ok") end))
Button(playersPage, "Bring Player",       require_target(function(p) bring(p);         pushLog("bring " .. p.Name);  notify("Brought " .. p.Name .. " (client-side)", "ok") end))
Button(playersPage, "Spectate Player",    require_target(function(p) setSpectate(p);   pushLog("spec " .. p.Name);   notify("Spectating " .. p.Name, "info") end))
Button(playersPage, "Stop Spectating",                  function()  setSpectate(nil);  pushLog("unspec");             notify("Spectate cleared", "info") end)
Button(playersPage, "View Player",        require_target(function(p) viewAtPlayer(p);  pushLog("view " .. p.Name);    notify("Viewing " .. p.Name, "info") end))
Button(playersPage, "Freeze Player",      require_target(function(p) setFreeze(p, true);  pushLog("freeze " .. p.Name);   notify("Froze " .. p.Name, "ok") end))
Button(playersPage, "Unfreeze Player",    require_target(function(p) setFreeze(p, false); pushLog("unfreeze " .. p.Name); notify("Unfroze " .. p.Name, "info") end))

-- ── VEHICLE
local vehiclePage = makeTab("vehicle", "▶", "Vehicle")
header(vehiclePage, "Drive Tuning")
Slider(vehiclePage, "Speed Multiplier", 1, 10, 1, 1, function(v) State.vSpeedMult = v; applyVehicleTuning() end)
Toggle(vehiclePage, "Instant Acceleration", function(v) State.vInstant = v; applyVehicleTuning() end)
Button(vehiclePage, "Boost Impulse", function() vehicleBoost(); pushLog("vboost") end)
Toggle(vehiclePage, "Vehicle Fly  (WASD + Space/Ctrl)", function(v) setVehicleFly(v); pushLog("vfly " .. tostring(v)) end)
Button(vehiclePage, "Re-detect Vehicle", function()
    local m = getVehicle()
    if m then notify("Vehicle: " .. m.Name, "ok") else notify("No vehicle detected", "warn") end
end)

-- ── FUN
local funPage = makeTab("fun", "✦", "World")
header(funPage, "Camera & World")
Slider(funPage, "Field of View", 30, 120, State.fov, 1, function(v) State.fov = v; State.fovOn = true; applyFOV() end)
Slider(funPage, "Gravity", 0, 400, math.floor(State.gravity), 1, function(v) State.gravity = v; State.gravityOn = true; applyGravity() end)
Button(funPage, "Day",   function() setTimeOfDay(14); notify("Time → Day",   "ok") end)
Button(funPage, "Night", function() setTimeOfDay(0);  notify("Time → Night", "info") end)

header(funPage, "Visuals")
Toggle(funPage, "ESP / Highlights", function(v) setESP(v) end)
Toggle(funPage, "Tracers",          function(v) setTracers(v) end)
Toggle(funPage, "Fullbright",       function(v) setFullbright(v) end)

-- ── LOGS
local logPage = makeTab("logs", "≡", "Logs")
header(logPage, "Command History")
local logBox = glassSurface({
    BackgroundColor3       = Theme.Bg3,
    BackgroundTransparency = 0.2,
    Size                   = UDim2.new(1, 0, 0, 300),
    Parent                 = logPage,
    Radius                 = 10,
})
local logScroll = new("ScrollingFrame", {
    BackgroundTransparency = 1,
    Size                   = UDim2.fromScale(1, 1),
    BorderSizePixel        = 0,
    CanvasSize             = UDim2.new(),
    AutomaticCanvasSize    = Enum.AutomaticSize.Y,
    ScrollBarThickness     = 3,
    ScrollBarImageColor3   = Theme.Accent,
    Parent                 = logBox,
}, {
    new("UIListLayout", { Padding = UDim.new(0, 2) }),
    new("UIPadding", {
        PaddingTop = UDim.new(0, 10), PaddingBottom = UDim.new(0, 10),
        PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12),
    }),
}) :: ScrollingFrame

logChanged = Instance.new("BindableEvent")
local function refreshLogs()
    for _, c in ipairs(logScroll:GetChildren()) do
        if c:IsA("TextLabel") then c:Destroy() end
    end
    for i = #Log, 1, -1 do
        new("TextLabel", {
            BackgroundTransparency = 1,
            Size                   = UDim2.new(1, 0, 0, 16),
            Font                   = Enum.Font.Code,
            Text                   = Log[i],
            TextColor3             = Theme.TextDim,
            TextSize               = 11,
            TextXAlignment         = Enum.TextXAlignment.Left,
            Parent                 = logScroll,
        })
    end
end
logChanged.Event:Connect(function() if currentTab == "logs" then refreshLogs() end end)
Button(logPage, "Clear Logs", function() table.clear(Log); refreshLogs() end)

-- ── INFO
local infoPage = makeTab("info", "✱", "Info")
header(infoPage, "Session")
local function infoBlock(parent: Instance, text: string, height: number, font: Enum.Font?)
    glassSurface({
        BackgroundColor3       = Theme.Bg3,
        BackgroundTransparency = 0.2,
        Size                   = UDim2.new(1, 0, 0, height),
        Parent                 = parent,
        Radius                 = 10,
    }, {
        new("UIPadding", {
            PaddingTop = UDim.new(0, 12), PaddingBottom = UDim.new(0, 12),
            PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14),
        }),
        new("TextLabel", {
            BackgroundTransparency = 1,
            Size                   = UDim2.fromScale(1, 1),
            Font                   = font or Enum.Font.Gotham,
            Text                   = text,
            TextColor3             = Theme.Text,
            TextSize               = 12,
            TextXAlignment         = Enum.TextXAlignment.Left,
            TextYAlignment         = Enum.TextYAlignment.Top,
        }),
    })
end

infoBlock(infoPage, ("Owner:     %s\nWhitelist: %d entries\nRank:      %s\nKeybind:   %s\nPrefix:    %s"):format(
    CONFIG.Owner == "" and "(unset — any user)" or CONFIG.Owner,
    #CONFIG.Whitelist, rankOf(LocalPlayer.Name),
    CONFIG.ToggleKey.Name, CONFIG.CommandPrefix), 120)

header(infoPage, "Visual Options")
Toggle(infoPage, "Backdrop Blur", function(v)
    CONFIG.BackdropBlur = v
    if v then setBackdropBlur(true) else
        if panelBlur then panelBlur:Destroy(); panelBlur = nil end
    end
end)
Toggle(infoPage, "RGB Accent Cycle", function(v)
    CONFIG.RGBCycle = v
    Maids.rgb:clean()
    if v then
        Maids.rgb:give(RunService.Heartbeat:Connect(function()
            local hue = (os.clock() * CONFIG.RGBCycleSpeed) % 1
            applyAccent(Color3.fromHSV(hue, 0.55, 1))
        end))
    else
        applyAccent(Theme.Accent)
    end
end)

header(infoPage, "Commands")
infoBlock(infoPage, [[
fly                       toggle flight (WASD + Space/Ctrl, Shift = sprint)
noclip                    toggle noclip
ws / walkspeed <n>        set walkspeed
jp / jumppower <n>        set jump power
infjump                   toggle infinite jump
invis                     toggle local invisibility
reset / sit               utilities
tp <player>               teleport to player
bring <player>            bring player
spec <player> | spec off  spectate
view <player>             jump camera to player
freeze / unfreeze <player>
fov <n> / gravity <n>
day / night
esp / tracers / fb        toggle visuals
vspeed <n>                vehicle speed multiplier
vboost / vfly             vehicle commands]], 280, Enum.Font.Code)

-- Wire tab buttons
for id, t in pairs(tabs) do
    t.button.MouseButton1Click:Connect(function() selectTab(id) end)
end
selectTab("self")

-- ╔══════════════════════════════════════════════════════════════════════╗
-- ║  COMMAND BAR                                                          ║
-- ╚══════════════════════════════════════════════════════════════════════╝
local function runCommand(raw: string)
    if raw == "" then return end
    if raw:sub(1, #CONFIG.CommandPrefix) == CONFIG.CommandPrefix then
        raw = raw:sub(#CONFIG.CommandPrefix + 1)
    end
    local parts = {}
    for w in raw:gmatch("%S+") do table.insert(parts, w) end
    local cmd = (parts[1] or ""):lower()
    local function num(d) return tonumber(parts[2]) or d end
    local function p()   return findPlayer(parts[2] or "") end

    if     cmd == "fly"        then setFly(not State.fly)
    elseif cmd == "unfly"      then setFly(false)
    elseif cmd == "noclip"     then setNoclip(not State.noclip)
    elseif cmd == "clip"       then setNoclip(false)
    elseif cmd == "ws" or cmd == "walkspeed" then
        State.walkSpeed = num(16); State.walkSpeedOn = true; applyWalkSpeed()
    elseif cmd == "jp" or cmd == "jumppower" then
        State.jumpPower = num(50); State.jumpPowerOn = true; applyJumpPower()
    elseif cmd == "infjump"    then setInfJump(not State.infJump)
    elseif cmd == "invis"      then setInvisible(not State.invisible)
    elseif cmd == "vis"        then setInvisible(false)
    elseif cmd == "reset" or cmd == "re" then resetChar()
    elseif cmd == "sit"        then sitNow()
    elseif cmd == "tp"         then local t = p(); if t then teleportTo(t)        else notify("Player not found", "warn") end
    elseif cmd == "bring"      then local t = p(); if t then bring(t)             else notify("Player not found", "warn") end
    elseif cmd == "spec"       then
        if (parts[2] or ""):lower() == "off" or parts[2] == nil then setSpectate(nil)
        else local t = p(); if t then setSpectate(t) else notify("Player not found", "warn") end end
    elseif cmd == "view"       then local t = p(); if t then viewAtPlayer(t)      else notify("Player not found", "warn") end
    elseif cmd == "freeze"     then local t = p(); if t then setFreeze(t, true)   else notify("Player not found", "warn") end
    elseif cmd == "unfreeze"   then local t = p(); if t then setFreeze(t, false)  else notify("Player not found", "warn") end
    elseif cmd == "fov"        then State.fov     = num(70);    State.fovOn     = true; applyFOV()
    elseif cmd == "gravity"    then State.gravity = num(196.2); State.gravityOn = true; applyGravity()
    elseif cmd == "day"        then setTimeOfDay(14)
    elseif cmd == "night"      then setTimeOfDay(0)
    elseif cmd == "esp"        then setESP(not State.esp)
    elseif cmd == "tracers"    then setTracers(not State.tracers)
    elseif cmd == "fb" or cmd == "fullbright" then setFullbright(not State.fullbright)
    elseif cmd == "vboost"     then vehicleBoost()
    elseif cmd == "vfly"       then setVehicleFly(not State.vFly)
    elseif cmd == "vspeed"     then State.vSpeedMult = num(1); applyVehicleTuning()
    elseif cmd == "help"       then selectTab("info")
    elseif cmd == "clear"      then table.clear(Log); refreshLogs()
    else notify("Unknown command: " .. cmd, "err"); return
    end
    pushLog(raw)

    -- pulse the command bar
    local pulse = new("Frame", {
        BackgroundColor3 = liveAccent, BorderSizePixel = 0,
        BackgroundTransparency = 0.5,
        Size = UDim2.fromScale(1, 1),
        ZIndex = 0,
        Parent = cmdBar,
    }, { new("UICorner", { CornerRadius = UDim.new(0, 12) }) })
    tw(pulse, Tween.Med, { BackgroundTransparency = 1 }).Completed:Connect(function() pulse:Destroy() end)
end

cmdInput.FocusLost:Connect(function(enter)
    if enter and rate("cmd", 0.05) then
        local text = cmdInput.Text
        cmdInput.Text = ""
        safe(runCommand, text)
    end
end)

-- ╔══════════════════════════════════════════════════════════════════════╗
-- ║  OPEN / CLOSE / MINIMIZE  +  BOOT REVEAL                              ║
-- ╚══════════════════════════════════════════════════════════════════════╝
local opened       = false
local minimized    = false
local bootDone     = false

local function runBoot()
    if bootDone or not CONFIG.BootAnimation then return end
    bootDone = true

    local cover = new("Frame", {
        BackgroundColor3       = Theme.Bg,
        BackgroundTransparency = 0,
        BorderSizePixel        = 0,
        Size                   = UDim2.fromScale(1, 1),
        ZIndex                 = 100,
        Parent                 = panel,
    }, { new("UICorner", { CornerRadius = UDim.new(0, 16) }) })

    new("TextLabel", {
        BackgroundTransparency = 1,
        AnchorPoint            = Vector2.new(0.5, 1),
        Position               = UDim2.fromScale(0.5, 0.5),
        Size                   = UDim2.fromOffset(280, 28),
        Font                   = Enum.Font.GothamBold,
        Text                   = CONFIG.PanelTitle,
        TextColor3             = Theme.Text,
        TextSize               = 16,
        ZIndex                 = 101,
        Parent                 = cover,
    })

    local barBg = new("Frame", {
        AnchorPoint      = Vector2.new(0.5, 0),
        Position         = UDim2.new(0.5, 0, 0.5, 12),
        Size             = UDim2.fromOffset(220, 4),
        BackgroundColor3 = Theme.BorderSoft,
        BorderSizePixel  = 0,
        ZIndex           = 101,
        Parent           = cover,
    }, { new("UICorner", { CornerRadius = UDim.new(1, 0) }) }) :: Frame

    local bar = new("Frame", {
        Size             = UDim2.fromScale(0, 1),
        BackgroundColor3 = Theme.Accent,
        BorderSizePixel  = 0,
        ZIndex           = 102,
        Parent           = barBg,
    }, {
        new("UICorner", { CornerRadius = UDim.new(1, 0) }),
        new("UIGradient", {
            Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0, Theme.AccentDeep),
                ColorSequenceKeypoint.new(1, Theme.AccentSoft),
            }),
        }),
    }) :: Frame
    follow(bar)

    tw(bar, TweenInfo.new(0.55, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
       { Size = UDim2.fromScale(1, 1) }).Completed:Wait()
    tw(cover, Tween.Med, { BackgroundTransparency = 1 })
    task.wait(0.25)
    cover:Destroy()
end

local function setOpen(state: boolean)
    if state == opened then return end
    opened = state
    if state then
        panel.Visible                = true
        panel.Size                   = UDim2.fromOffset(0, 0)
        panel.BackgroundTransparency = 1
        haloImg.ImageTransparency    = 1
        shadowImg.ImageTransparency  = 1
        tw(panel, Tween.Pop, {
            Size                   = UDim2.fromOffset(livePanelSize.X, livePanelSize.Y),
            BackgroundTransparency = CONFIG.BackgroundAlpha,
        })
        tw(haloImg,   Tween.Slow, { ImageTransparency = 0.85 })
        tw(shadowImg, Tween.Slow, { ImageTransparency = 0.4 })
        setBackdropBlur(true)
        task.spawn(runBoot)
    else
        tw(haloImg,   Tween.Fast, { ImageTransparency = 1 })
        tw(shadowImg, Tween.Fast, { ImageTransparency = 1 })
        setBackdropBlur(false)
        local t = tw(panel, Tween.Fast, {
            Size                   = UDim2.fromOffset(0, 0),
            BackgroundTransparency = 1,
        })
        t.Completed:Connect(function() panel.Visible = false end)
    end
end

closeBtn.MouseButton1Click:Connect(function() setOpen(false) end)
minBtn.MouseButton1Click:Connect(function()
    minimized = not minimized
    sidebar.Visible = not minimized
    content.Visible = not minimized
    cmdBar.Visible  = not minimized
    resizeHandle.Visible = not minimized
    tw(panel, Tween.Fast, {
        Size = minimized
            and UDim2.fromOffset(livePanelSize.X, 50)
            or  UDim2.fromOffset(livePanelSize.X, livePanelSize.Y),
    })
end)

UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end
    if input.KeyCode == CONFIG.ToggleKey then setOpen(not opened) end
end)

-- Keep halo + shadow tracking panel every frame
RunService.RenderStepped:Connect(trackPanel)

-- ╔══════════════════════════════════════════════════════════════════════╗
-- ║  MOBILE TOGGLE BUTTON                                                 ║
-- ╚══════════════════════════════════════════════════════════════════════╝
if CONFIG.MobileButton and UserInputService.TouchEnabled and not UserInputService.MouseEnabled then
    local btn = new("TextButton", {
        Name                   = "MobileToggle",
        AnchorPoint            = Vector2.new(0, 0.5),
        Position               = UDim2.new(0, 12, 0.35, 0),
        Size                   = UDim2.fromOffset(58, 58),
        BackgroundColor3       = Theme.Accent,
        BackgroundTransparency = 0.05,
        BorderSizePixel        = 0,
        Font                   = Enum.Font.GothamBold,
        Text                   = "≡",
        TextColor3             = Color3.fromRGB(255, 255, 255),
        TextSize               = 30,
        AutoButtonColor        = false,
        Parent                 = gui,
    }, {
        new("UICorner", { CornerRadius = UDim.new(1, 0) }),
        new("UIStroke", { Color = Color3.fromRGB(255, 255, 255), Transparency = 0.7 }),
    }) :: TextButton
    follow(btn)
    neonGlow(btn, { Spread = 30, Transparency = 0.4, FollowAccent = true })

    local dragging, startMouse, startPos, moved
    btn.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch then
            dragging   = true; moved = false
            startMouse = input.Position
            startPos   = btn.Position
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if dragging and input.UserInputType == Enum.UserInputType.Touch then
            local d = input.Position - startMouse
            if d.Magnitude > 6 then moved = true end
            btn.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + d.X,
                startPos.Y.Scale, startPos.Y.Offset + d.Y
            )
        end
    end)
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch then
            if dragging and not moved then setOpen(not opened) end
            dragging = false
        end
    end)
end

-- ╔══════════════════════════════════════════════════════════════════════╗
-- ║  LIFECYCLE                                                            ║
-- ╚══════════════════════════════════════════════════════════════════════╝
local function onPlayerAdded(p: Player)
    refreshList()
    if State.esp     then attachESPTo(p) end
    if State.tracers then makeTracerFor(p) end
    p.CharacterAdded:Connect(function()
        task.wait(0.4)
        if State.esp     then attachESPTo(p) end
        if State.tracers then makeTracerFor(p) end
    end)
end
local function onPlayerRemoving(p: Player)
    refreshList()
    clearESPFor(p); clearTracerFor(p)
    frozen[p] = nil
    if State.target     == p then setTarget(nil) end
    if State.spectating == p then setSpectate(nil) end
end
Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)
for _, p in ipairs(Players:GetPlayers()) do
    if p ~= LocalPlayer then
        p.CharacterAdded:Connect(function()
            task.wait(0.4)
            if State.esp     then attachESPTo(p) end
            if State.tracers then makeTracerFor(p) end
        end)
    end
end
refreshList()

LocalPlayer.CharacterAdded:Connect(function(c)
    c:WaitForChild("HumanoidRootPart")
    c:WaitForChild("Humanoid")
    task.wait(0.1)
    if State.fly         then stopFly(); startFly() end
    if State.noclip      then setNoclip(true) end
    if State.walkSpeedOn then applyWalkSpeed() end
    if State.jumpPowerOn then applyJumpPower() end
    if State.invisible then
        -- Maids.invis loop survives respawn; nothing to do.
    end
    if State.spectating and State.spectating.Parent then setSpectate(State.spectating) end
end)
LocalPlayer.CharacterRemoving:Connect(function() Maids.fly:clean() end)

Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
    Camera = Workspace.CurrentCamera
    if State.fovOn then Camera.FieldOfView = State.fov end
end)

-- ╔══════════════════════════════════════════════════════════════════════╗
-- ║  BOOT                                                                 ║
-- ╚══════════════════════════════════════════════════════════════════════╝
applyFOV()
applyGravity()
applyAccent(Theme.Accent)
trackPanel()
notify(("Admin Panel ready — press %s"):format(CONFIG.ToggleKey.Name), "ok")
