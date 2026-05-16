--!strict
--[[
================================================================================
  ADMIN PANEL — single-file, production rebuild
================================================================================
  • One Lua file. No external modules, no remotes to create manually, no
    folder structure to set up.  Drop this in as a LocalScript (or run via
    executor) and the entire system — ScreenGui, state, command logic,
    respawn handling — is generated for you.
  • Pure client-side. Operations that would normally need a server route
    are performed locally only; on FilteringEnabled servers, target-other
    actions (Bring / Freeze) revert on the next physics step.  This is a
    deliberate trade-off for zero-setup beginner-friendliness.

  SETUP
    1.  Edit the CONFIG block below — at minimum set `Owner` to your
        username (or leave blank to allow whoever runs the script).
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
    PanelSize         = Vector2.new(640, 440),
    Accent            = Color3.fromRGB(110, 138, 255),
    BackgroundAlpha   = 0.08,
}

-- ── SERVICES ──────────────────────────────────────────────────────────────
local Players          = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService       = game:GetService("RunService")
local TweenService     = game:GetService("TweenService")
local Lighting         = game:GetService("Lighting")
local Workspace        = game:GetService("Workspace")
local CoreGui          = game:GetService("CoreGui")
local GuiService       = game:GetService("GuiService")

local LocalPlayer = Players.LocalPlayer
local Camera      = Workspace.CurrentCamera

-- ── AUTHORIZATION ─────────────────────────────────────────────────────────
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
-- ║  THEME                                                                ║
-- ╚══════════════════════════════════════════════════════════════════════╝
local Theme = {
    Bg          = Color3.fromRGB(16, 18, 24),
    Bg2         = Color3.fromRGB(22, 24, 32),
    Bg3         = Color3.fromRGB(28, 30, 38),
    Border      = Color3.fromRGB(40, 44, 56),
    Text        = Color3.fromRGB(232, 234, 240),
    TextDim     = Color3.fromRGB(150, 154, 168),
    TextMuted   = Color3.fromRGB(108, 112, 126),
    Accent      = CONFIG.Accent,
    AccentSoft  = Color3.fromRGB(140, 162, 255),
    Ok          = Color3.fromRGB(76, 196, 130),
    Warn        = Color3.fromRGB(232, 178, 70),
    Err         = Color3.fromRGB(232, 92, 92),
}

local TWEEN_FAST = TweenInfo.new(0.18, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
local TWEEN_MED  = TweenInfo.new(0.28, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
local TWEEN_POP  = TweenInfo.new(0.35, Enum.EasingStyle.Back,  Enum.EasingDirection.Out)

-- ╔══════════════════════════════════════════════════════════════════════╗
-- ║  UTILITIES                                                            ║
-- ╚══════════════════════════════════════════════════════════════════════╝

-- Instance factory.  Sets Parent last so children/properties replicate as
-- a single batch instead of one-by-one.
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

local function tween(o: Instance, info: TweenInfo, goal: { [string]: any }): Tween
    local t = TweenService:Create(o, info, goal)
    t:Play()
    return t
end

local function safe(fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then warn("[AdminPanel] " .. tostring(err)) end
end

-- ── Maid: tracks connections / instances / cleanup funcs for safe teardown.
local Maid = {}
Maid.__index = Maid

function Maid.new()
    return setmetatable({ _items = {} }, Maid)
end

function Maid:give(item)
    table.insert(self._items, item)
    return item
end

function Maid:clean()
    for i = #self._items, 1, -1 do
        local item = self._items[i]
        self._items[i] = nil
        if typeof(item) == "RBXScriptConnection" then
            item:Disconnect()
        elseif typeof(item) == "Instance" then
            item:Destroy()
        elseif type(item) == "function" then
            pcall(item)
        end
    end
end

-- ── Rate limiter (token-bucket style, per key).
local Rate = {}
local rateState: { [string]: number } = {}
function Rate.allow(key: string, gap: number): boolean
    local now = os.clock()
    if (rateState[key] or 0) + gap > now then return false end
    rateState[key] = now
    return true
end

-- ── Character helpers
local function char()         return LocalPlayer.Character end
local function humanoid()     local c = char(); return c and c:FindFirstChildOfClass("Humanoid") end
local function hrp()          local c = char(); return c and c:FindFirstChild("HumanoidRootPart") end

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
    -- exact match first
    for _, p in ipairs(Players:GetPlayers()) do
        if p.Name:lower() == query or p.DisplayName:lower() == query then return p end
    end
    -- prefix match
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

-- ╔══════════════════════════════════════════════════════════════════════╗
-- ║  STATE                                                                ║
-- ╚══════════════════════════════════════════════════════════════════════╝
local State = {
    -- mobility
    fly         = false,
    flySpeed    = 70,
    noclip      = false,
    walkSpeed   = 16,
    walkSpeedOn = false,
    jumpPower   = 50,
    jumpPowerOn = false,
    infJump     = false,

    -- status
    invisible   = false,
    godMode     = false,
    spectating  = nil :: Player?,
    target      = nil :: Player?,

    -- vehicle
    vSpeedMult  = 1,
    vInstant    = false,
    vFly        = false,

    -- world
    fov         = 70,
    fovOn       = false,
    gravity     = workspace.Gravity,
    gravityOn   = false,
    esp         = false,
    tracers     = false,
    fullbright  = false,
}

-- Per-feature maids — keeping connection lifetime tied to feature toggle.
local Maids = {
    fly         = Maid.new(),
    noclip      = Maid.new(),
    infJump     = Maid.new(),
    god         = Maid.new(),
    vfly        = Maid.new(),
    tracers     = Maid.new(),
    fullbright  = Maid.new(),
}

-- Active log buffer
local Log: { string } = {}
local LogCap          = 200
local logChanged: BindableEvent

-- ╔══════════════════════════════════════════════════════════════════════╗
-- ║  NOTIFICATIONS                                                        ║
-- ╚══════════════════════════════════════════════════════════════════════╝
local notifLayer: Frame
local function notify(text: string, kind: string?)
    kind = kind or "info"
    local color = ({
        info = Theme.Accent, ok = Theme.Ok, warn = Theme.Warn, err = Theme.Err,
    })[kind] or Theme.Accent

    local card = new("Frame", {
        BackgroundColor3       = Theme.Bg2,
        BackgroundTransparency = 0.05,
        Size                   = UDim2.new(1, 0, 0, 0),
        AutomaticSize          = Enum.AutomaticSize.Y,
        Position               = UDim2.new(1.2, 0, 0, 0),
        Parent                 = notifLayer,
    }, {
        new("UICorner", { CornerRadius = UDim.new(0, 8) }),
        new("UIStroke", { Color = Theme.Border, Transparency = 0.5 }),
        new("Frame", {
            BackgroundColor3 = color, BorderSizePixel = 0,
            Position = UDim2.new(0, 6, 0, 6),
            Size     = UDim2.new(0, 3, 1, -12),
        }, { new("UICorner", { CornerRadius = UDim.new(0, 2) }) }),
        new("TextLabel", {
            BackgroundTransparency = 1,
            Position               = UDim2.new(0, 18, 0, 8),
            Size                   = UDim2.new(1, -26, 0, 0),
            AutomaticSize          = Enum.AutomaticSize.Y,
            Font                   = Enum.Font.Gotham,
            Text                   = text,
            TextColor3             = Theme.Text,
            TextSize               = 13,
            TextWrapped            = true,
            TextXAlignment         = Enum.TextXAlignment.Left,
        }),
        new("UIPadding", {
            PaddingTop = UDim.new(0, 0), PaddingBottom = UDim.new(0, 8),
        }),
    })

    tween(card, TWEEN_POP, { Position = UDim2.new(0, 0, 0, 0) })

    task.delay(3.5, function()
        if not card.Parent then return end
        local t = tween(card, TWEEN_FAST, {
            Position               = UDim2.new(1.2, 0, 0, 0),
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
-- ║  FEATURES                                                             ║
-- ╚══════════════════════════════════════════════════════════════════════╝

-- ── Mobility: Fly  (LinearVelocity + AlignOrientation, modern API)
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
        Parent         = root,
    }) :: LinearVelocity
    local ao  = new("AlignOrientation", {
        Name             = "AdminFlyAO",
        Attachment0      = att,
        Mode             = Enum.OrientationAlignmentMode.OneAttachment,
        MaxTorque        = math.huge,
        Responsiveness   = 200,
        AlignType        = Enum.AlignType.AllAxes,
        Parent           = root,
    }) :: AlignOrientation

    Maids.fly:give(att); Maids.fly:give(lv); Maids.fly:give(ao)
    hum.PlatformStand = true
    Maids.fly:give(function()
        local h = humanoid(); if h then h.PlatformStand = false end
    end)

    Maids.fly:give(RunService.RenderStepped:Connect(function()
        local cam = Workspace.CurrentCamera
        local dir = Vector3.zero
        if UserInputService:IsKeyDown(Enum.KeyCode.W)            then dir += cam.CFrame.LookVector  end
        if UserInputService:IsKeyDown(Enum.KeyCode.S)            then dir -= cam.CFrame.LookVector  end
        if UserInputService:IsKeyDown(Enum.KeyCode.A)            then dir -= cam.CFrame.RightVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.D)            then dir += cam.CFrame.RightVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.Space)        then dir += Vector3.yAxis           end
        if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)  then dir -= Vector3.yAxis           end
        lv.VectorVelocity = (dir.Magnitude > 0 and dir.Unit or Vector3.zero) * State.flySpeed
        ao.CFrame         = cam.CFrame
    end))
end

local function stopFly() Maids.fly:clean() end

local function setFly(on: boolean)
    if State.fly == on then return end
    State.fly = on
    if on then startFly() else stopFly() end
end

-- ── Mobility: Noclip
local function setNoclip(on: boolean)
    if State.noclip == on then return end
    State.noclip = on
    Maids.noclip:clean()
    if not on then return end

    Maids.noclip:give(RunService.Stepped:Connect(function()
        local c = char()
        if not c then return end
        for _, d in ipairs(c:GetDescendants()) do
            if d:IsA("BasePart") and d.CanCollide then d.CanCollide = false end
        end
    end))
end

-- ── Mobility: WalkSpeed / JumpPower / InfJump
local function applyWalkSpeed()
    local h = humanoid()
    if h then h.WalkSpeed = State.walkSpeedOn and State.walkSpeed or 16 end
end

local function applyJumpPower()
    local h = humanoid()
    if not h then return end
    h.UseJumpPower = true
    h.JumpPower    = State.jumpPowerOn and State.jumpPower or 50
end

local function setInfJump(on: boolean)
    if State.infJump == on then return end
    State.infJump = on
    Maids.infJump:clean()
    if not on then return end
    Maids.infJump:give(UserInputService.JumpRequest:Connect(function()
        local h = humanoid()
        if h then h:ChangeState(Enum.HumanoidStateType.Jumping) end
    end))
end

-- ── Status: invisible / god / heal / reset / sit
local function setInvisible(on: boolean)
    State.invisible = on
    local c = char()
    if not c then return end
    for _, d in ipairs(c:GetDescendants()) do
        if d:IsA("BasePart") then d.LocalTransparencyModifier = on and 1 or 0
        elseif d:IsA("Decal") then d.Transparency             = on and 1 or 0 end
    end
end

local function setGodMode(on: boolean)
    if State.godMode == on then return end
    State.godMode = on
    Maids.god:clean()
    local h = humanoid()
    if not h then return end
    if on then
        local maxHP = math.huge
        h.MaxHealth = maxHP
        h.Health    = maxHP
        Maids.god:give(h.HealthChanged:Connect(function(hp)
            if h.Parent and hp < h.MaxHealth then h.Health = h.MaxHealth end
        end))
    else
        h.MaxHealth = 100
        h.Health    = 100
    end
end

local function heal()
    local h = humanoid(); if h then h.Health = h.MaxHealth end
end

local function resetChar()
    local h = humanoid(); if h then h.Health = 0 end
end

local function sit()
    local h = humanoid(); if h then h.Sit = true end
end

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
        frozen[p]    = part.Anchored
        part.Anchored = true
    else
        part.Anchored = frozen[p] or false
        frozen[p]     = nil
    end
end

local function setSpectate(p: Player?)
    State.spectating = p
    if p and p.Character then
        local h = p.Character:FindFirstChildOfClass("Humanoid")
        if h then Camera.CameraSubject = h end
    else
        local h = humanoid()
        if h then Camera.CameraSubject = h end
    end
end

local function viewAtPlayer(p: Player)
    local part = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
    if part then
        Camera.CameraType = Enum.CameraType.Scriptable
        Camera.CFrame = CFrame.new(part.Position + Vector3.new(0, 4, 8), part.Position)
        task.delay(2, function() Camera.CameraType = Enum.CameraType.Custom end)
    end
end

-- ── Vehicle
local function getVehicle(): (Model?, VehicleSeat?)
    local c = char(); if not c then return nil, nil end
    local h = c:FindFirstChildOfClass("Humanoid"); if not h then return nil, nil end
    local seat = h.SeatPart
    if not (seat and seat:IsA("VehicleSeat")) then return nil, nil end
    local model = seat:FindFirstAncestorOfClass("Model")
    return model, seat
end

local function applyVehicleTuning()
    local _, seat = getVehicle()
    if not seat then return end
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
    if not m or not s then
        notify("No vehicle detected", "warn"); State.vFly = false; return
    end
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
local function applyFOV()
    if State.fovOn then Camera.FieldOfView = State.fov end
end

local function applyGravity()
    if State.gravityOn then Workspace.Gravity = State.gravity end
end

local function setTimeOfDay(hours: number)
    Lighting.ClockTime = hours
end

-- ── ESP / Tracers
local Highlights:  { [Player]: Highlight } = {}
local TracerLines: { [Player]: Frame }     = {}
local tracerLayer: Frame

local function clearESPFor(p: Player)
    local h = Highlights[p]; if h then h:Destroy() end; Highlights[p] = nil
end

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

local function clearTracerFor(p: Player)
    local l = TracerLines[p]; if l then l:Destroy() end; TracerLines[p] = nil
end

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
        local vp   = Camera.ViewportSize
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
            Ambient        = Lighting.Ambient,
            OutdoorAmbient = Lighting.OutdoorAmbient,
            Brightness     = Lighting.Brightness,
            FogEnd         = Lighting.FogEnd,
            GlobalShadows  = Lighting.GlobalShadows,
            ClockTime      = Lighting.ClockTime,
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
-- ║  ROOT GUI                                                             ║
-- ╚══════════════════════════════════════════════════════════════════════╝
local function resolveGuiParent(): Instance
    -- Prefer protected guis on executors, fall back to CoreGui then PlayerGui.
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
-- Wipe any previous instance so re-running won't stack panels.
local existing = guiParent:FindFirstChild("AdminPanel")
if existing then existing:Destroy() end

local gui = new("ScreenGui", {
    Name           = "AdminPanel",
    ResetOnSpawn   = false,
    IgnoreGuiInset = true,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    DisplayOrder   = 9999,
    Parent         = guiParent,
}) :: ScreenGui

-- Notification layer (top-right)
notifLayer = new("Frame", {
    Name                   = "Notifications",
    AnchorPoint            = Vector2.new(1, 0),
    Position               = UDim2.new(1, -16, 0, 16),
    Size                   = UDim2.new(0, 280, 1, -32),
    BackgroundTransparency = 1,
    Parent                 = gui,
}, {
    new("UIListLayout", {
        Padding             = UDim.new(0, 8),
        HorizontalAlignment = Enum.HorizontalAlignment.Right,
        SortOrder           = Enum.SortOrder.LayoutOrder,
    }),
}) :: Frame

-- Tracer layer
tracerLayer = new("Frame", {
    Name                   = "Tracers",
    Size                   = UDim2.fromScale(1, 1),
    BackgroundTransparency = 1,
    Parent                 = gui,
}) :: Frame

-- ── Main panel
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
    Parent                 = gui,
}, {
    new("UICorner", { CornerRadius = UDim.new(0, 14) }),
    new("UIStroke", { Color = Theme.Border, Transparency = 0.3, Thickness = 1 }),
    new("UIGradient", {
        Rotation = 90,
        Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Color3.fromRGB(28, 31, 40)),
            ColorSequenceKeypoint.new(1, Color3.fromRGB(14, 16, 22)),
        }),
    }),
}) :: Frame

-- ── Title bar
local titleBar = new("Frame", {
    Name                   = "TitleBar",
    BackgroundTransparency = 1,
    Size                   = UDim2.new(1, 0, 0, 44),
    Parent                 = panel,
}) :: Frame

new("Frame", {                                               -- accent dot
    BackgroundColor3 = Theme.Accent,
    Position         = UDim2.new(0, 16, 0.5, -4),
    Size             = UDim2.fromOffset(8, 8),
    BorderSizePixel  = 0,
    Parent           = titleBar,
}, { new("UICorner", { CornerRadius = UDim.new(1, 0) }) })

new("TextLabel", {
    BackgroundTransparency = 1,
    Position               = UDim2.new(0, 32, 0, 0),
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
    Position               = UDim2.new(0, 32, 0, 24),
    Size                   = UDim2.new(0.5, 0, 0, 14),
    Font                   = Enum.Font.Gotham,
    Text                   = ("%s · %s"):format(LocalPlayer.Name, rankOf(LocalPlayer.Name)),
    TextColor3             = Theme.TextDim,
    TextSize               = 11,
    TextXAlignment         = Enum.TextXAlignment.Left,
    Parent                 = titleBar,
})

local function titleButton(label: string, glyph: string, offX: number, hover: Color3): TextButton
    local b = new("TextButton", {
        Name                   = label,
        AnchorPoint            = Vector2.new(1, 0.5),
        Position               = UDim2.new(1, offX, 0.5, 0),
        Size                   = UDim2.fromOffset(28, 28),
        BackgroundColor3       = Theme.Bg3,
        BackgroundTransparency = 0.2,
        BorderSizePixel        = 0,
        Font                   = Enum.Font.GothamBold,
        Text                   = glyph,
        TextColor3             = Theme.Text,
        TextSize               = 14,
        AutoButtonColor        = false,
        Parent                 = titleBar,
    }, {
        new("UICorner", { CornerRadius = UDim.new(0, 6) }),
        new("UIStroke", { Color = Theme.Border, Transparency = 0.5 }),
    }) :: TextButton
    b.MouseEnter:Connect(function() tween(b, TWEEN_FAST, { BackgroundColor3 = hover }) end)
    b.MouseLeave:Connect(function() tween(b, TWEEN_FAST, { BackgroundColor3 = Theme.Bg3 }) end)
    return b
end

local minBtn   = titleButton("Minimize", "–", -50, Theme.Bg3)
local closeBtn = titleButton("Close",    "×", -14, Theme.Err)

-- ── Sidebar
local sidebar = new("Frame", {
    Name                   = "Sidebar",
    BackgroundColor3       = Theme.Bg2,
    BackgroundTransparency = 0.1,
    BorderSizePixel        = 0,
    Position               = UDim2.new(0, 10, 0, 52),
    Size                   = UDim2.new(0, 140, 1, -104),
    Parent                 = panel,
}, {
    new("UICorner", { CornerRadius = UDim.new(0, 10) }),
    new("UIPadding", {
        PaddingTop    = UDim.new(0, 10), PaddingBottom = UDim.new(0, 10),
        PaddingLeft   = UDim.new(0, 8),  PaddingRight  = UDim.new(0, 8),
    }),
    new("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }),
}) :: Frame

-- ── Content
local content = new("Frame", {
    Name                   = "Content",
    BackgroundColor3       = Theme.Bg2,
    BackgroundTransparency = 0.18,
    BorderSizePixel        = 0,
    Position               = UDim2.new(0, 158, 0, 52),
    Size                   = UDim2.new(1, -168, 1, -104),
    ClipsDescendants       = true,
    Parent                 = panel,
}, { new("UICorner", { CornerRadius = UDim.new(0, 10) }) }) :: Frame

-- ── Command bar
local cmdBar = new("Frame", {
    Name                   = "Cmd",
    BackgroundColor3       = Theme.Bg2,
    BackgroundTransparency = 0.1,
    BorderSizePixel        = 0,
    Position               = UDim2.new(0, 10, 1, -42),
    Size                   = UDim2.new(1, -20, 0, 32),
    Parent                 = panel,
}, {
    new("UICorner", { CornerRadius = UDim.new(0, 10) }),
    new("UIStroke", { Color = Theme.Border, Transparency = 0.5 }),
}) :: Frame
new("TextLabel", {
    BackgroundTransparency = 1,
    Position               = UDim2.new(0, 12, 0, 0),
    Size                   = UDim2.new(0, 14, 1, 0),
    Font                   = Enum.Font.GothamBold,
    Text                   = CONFIG.CommandPrefix,
    TextColor3             = Theme.Accent,
    TextSize               = 14,
    Parent                 = cmdBar,
})
local cmdInput = new("TextBox", {
    BackgroundTransparency = 1,
    Position               = UDim2.new(0, 30, 0, 0),
    Size                   = UDim2.new(1, -40, 1, 0),
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

-- ── Drag handling (mouse + touch)
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
                    dragging = false
                    if conn then conn:Disconnect() end
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

-- ╔══════════════════════════════════════════════════════════════════════╗
-- ║  COMPONENTS                                                           ║
-- ╚══════════════════════════════════════════════════════════════════════╝

local function header(parent: Instance, text: string)
    new("TextLabel", {
        BackgroundTransparency = 1,
        Size                   = UDim2.new(1, 0, 0, 22),
        Font                   = Enum.Font.GothamBold,
        Text                   = text:upper(),
        TextColor3             = Theme.TextDim,
        TextSize               = 11,
        TextXAlignment         = Enum.TextXAlignment.Left,
        Parent                 = parent,
    })
end

local function makeToggle(parent: Instance, label: string, onChange: (boolean) -> ())
    local container = new("Frame", {
        BackgroundColor3       = Theme.Bg3,
        BackgroundTransparency = 0.15,
        BorderSizePixel        = 0,
        Size                   = UDim2.new(1, 0, 0, 36),
        Parent                 = parent,
    }, { new("UICorner", { CornerRadius = UDim.new(0, 8) }) }) :: Frame

    new("TextLabel", {
        BackgroundTransparency = 1,
        Position               = UDim2.new(0, 14, 0, 0),
        Size                   = UDim2.new(1, -64, 1, 0),
        Font                   = Enum.Font.GothamMedium,
        Text                   = label,
        TextColor3             = Theme.Text,
        TextSize               = 13,
        TextXAlignment         = Enum.TextXAlignment.Left,
        Parent                 = container,
    })

    local track = new("Frame", {
        AnchorPoint            = Vector2.new(1, 0.5),
        Position               = UDim2.new(1, -12, 0.5, 0),
        Size                   = UDim2.fromOffset(38, 20),
        BackgroundColor3       = Color3.fromRGB(48, 52, 64),
        BorderSizePixel        = 0,
        Parent                 = container,
    }, { new("UICorner", { CornerRadius = UDim.new(1, 0) }) }) :: Frame

    local knob = new("Frame", {
        AnchorPoint            = Vector2.new(0, 0.5),
        Position               = UDim2.new(0, 2, 0.5, 0),
        Size                   = UDim2.fromOffset(16, 16),
        BackgroundColor3       = Theme.Text,
        BorderSizePixel        = 0,
        Parent                 = track,
    }, { new("UICorner", { CornerRadius = UDim.new(1, 0) }) }) :: Frame

    local btn = new("TextButton", {
        BackgroundTransparency = 1, Text = "",
        Size = UDim2.fromScale(1, 1), Parent = container,
    }) :: TextButton

    local value = false
    local function apply(v: boolean, silent: boolean?)
        value = v
        tween(track, TWEEN_FAST, {
            BackgroundColor3 = v and Theme.Accent or Color3.fromRGB(48, 52, 64),
        })
        tween(knob, TWEEN_FAST, {
            Position = v and UDim2.new(1, -18, 0.5, 0) or UDim2.new(0, 2, 0.5, 0),
        })
        if not silent then onChange(v) end
    end

    btn.MouseButton1Click:Connect(function() apply(not value) end)
    return { set = apply, get = function() return value end }
end

local function makeSlider(parent: Instance, label: string,
                          min: number, max: number, default: number,
                          step: number?, onChange: (number) -> ())
    step = step or 1
    local container = new("Frame", {
        BackgroundColor3       = Theme.Bg3,
        BackgroundTransparency = 0.15,
        BorderSizePixel        = 0,
        Size                   = UDim2.new(1, 0, 0, 54),
        Parent                 = parent,
    }, {
        new("UICorner",  { CornerRadius = UDim.new(0, 8) }),
        new("UIPadding", {
            PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14),
            PaddingTop  = UDim.new(0, 8),  PaddingBottom = UDim.new(0, 10),
        }),
    }) :: Frame

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

    local track = new("Frame", {
        Position         = UDim2.new(0, 0, 0, 26),
        Size             = UDim2.new(1, 0, 0, 6),
        BackgroundColor3 = Color3.fromRGB(40, 44, 56),
        BorderSizePixel  = 0,
        Parent           = container,
    }, { new("UICorner", { CornerRadius = UDim.new(1, 0) }) }) :: Frame

    local fill = new("Frame", {
        Size             = UDim2.new((default - min) / (max - min), 0, 1, 0),
        BackgroundColor3 = Theme.Accent,
        BorderSizePixel  = 0,
        Parent           = track,
    }, { new("UICorner", { CornerRadius = UDim.new(1, 0) }) }) :: Frame

    local dragging = false
    local function updateFromInput(x: number)
        local rel = math.clamp((x - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
        local v   = min + (max - min) * rel
        v = math.floor(v / step + 0.5) * step
        v = math.clamp(v, min, max)
        fill.Size     = UDim2.new((v - min) / (max - min), 0, 1, 0)
        valueLbl.Text = tostring(v)
        onChange(v)
    end

    track.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            updateFromInput(input.Position.X)
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if dragging
        and (input.UserInputType == Enum.UserInputType.MouseMovement
          or input.UserInputType == Enum.UserInputType.Touch) then
            updateFromInput(input.Position.X)
        end
    end)
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)
    return {
        set = function(v: number)
            v = math.clamp(v, min, max)
            fill.Size     = UDim2.new((v - min) / (max - min), 0, 1, 0)
            valueLbl.Text = tostring(v)
        end,
    }
end

local function makeButton(parent: Instance, label: string, onClick: () -> ())
    local b = new("TextButton", {
        BackgroundColor3       = Theme.Bg3,
        BackgroundTransparency = 0.1,
        BorderSizePixel        = 0,
        Size                   = UDim2.new(1, 0, 0, 32),
        Font                   = Enum.Font.GothamMedium,
        Text                   = label,
        TextColor3             = Theme.Text,
        TextSize               = 13,
        AutoButtonColor        = false,
        Parent                 = parent,
    }, {
        new("UICorner", { CornerRadius = UDim.new(0, 8) }),
        new("UIStroke", { Color = Theme.Border, Transparency = 0.5 }),
    }) :: TextButton

    b.MouseEnter:Connect(function() tween(b, TWEEN_FAST, { BackgroundColor3 = Theme.Accent }) end)
    b.MouseLeave:Connect(function() tween(b, TWEEN_FAST, { BackgroundColor3 = Theme.Bg3   }) end)
    b.MouseButton1Click:Connect(function()
        if not Rate.allow("btn:" .. label, 0.1) then return end
        tween(b, TWEEN_FAST, { BackgroundColor3 = Theme.AccentSoft })
        task.delay(0.08, function()
            tween(b, TWEEN_FAST, { BackgroundColor3 = Theme.Accent })
        end)
        safe(onClick)
    end)
    return b
end

-- ╔══════════════════════════════════════════════════════════════════════╗
-- ║  TABS                                                                 ║
-- ╚══════════════════════════════════════════════════════════════════════╝
local tabs: { [string]: { button: TextButton, page: ScrollingFrame, strip: Frame } } = {}
local currentTab: string? = nil

local function createTab(id: string, label: string): ScrollingFrame
    local btn = new("TextButton", {
        Name                   = "Tab_" .. id,
        BackgroundColor3       = Theme.Bg3,
        BackgroundTransparency = 1,
        BorderSizePixel        = 0,
        Size                   = UDim2.new(1, 0, 0, 32),
        Font                   = Enum.Font.GothamMedium,
        Text                   = label,
        TextColor3             = Theme.TextDim,
        TextSize               = 13,
        AutoButtonColor        = false,
        Parent                 = sidebar,
    }, { new("UICorner", { CornerRadius = UDim.new(0, 7) }) }) :: TextButton

    local strip = new("Frame", {
        BackgroundColor3 = Theme.Accent,
        BorderSizePixel  = 0,
        Position         = UDim2.new(0, 0, 0.5, -8),
        Size             = UDim2.new(0, 0, 0, 16),
        Parent           = btn,
    }, { new("UICorner", { CornerRadius = UDim.new(0, 2) }) }) :: Frame

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
            PaddingTop = UDim.new(0, 12), PaddingBottom = UDim.new(0, 14),
            PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14),
        }),
        new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
    }) :: ScrollingFrame

    tabs[id] = { button = btn, page = page, strip = strip }

    btn.MouseEnter:Connect(function()
        if currentTab ~= id then tween(btn, TWEEN_FAST, { BackgroundTransparency = 0.4 }) end
    end)
    btn.MouseLeave:Connect(function()
        if currentTab ~= id then tween(btn, TWEEN_FAST, { BackgroundTransparency = 1 }) end
    end)
    return page
end

local function selectTab(id: string)
    if currentTab == id then return end
    for n, t in pairs(tabs) do
        local active = (n == id)
        t.page.Visible = active
        tween(t.button, TWEEN_FAST, {
            BackgroundTransparency = active and 0.2 or 1,
            TextColor3             = active and Theme.Text or Theme.TextDim,
        })
        tween(t.strip, TWEEN_FAST, { Size = UDim2.new(0, active and 3 or 0, 0, 16) })
    end
    currentTab = id
end

-- ╔══════════════════════════════════════════════════════════════════════╗
-- ║  TAB CONTENT                                                          ║
-- ╚══════════════════════════════════════════════════════════════════════╝

-- ── SELF ─────────────────────────────────────────────────────────────────
local selfPage = createTab("self", "🧍  Self")
header(selfPage, "Mobility")
makeToggle(selfPage, "Fly  (WASD + Space/Ctrl)", function(v)
    setFly(v); pushLog(("fly %s"):format(tostring(v))); notify("Fly " .. (v and "on" or "off"), v and "ok" or "info")
end)
makeToggle(selfPage, "Noclip", function(v)
    setNoclip(v); pushLog(("noclip %s"):format(tostring(v))); notify("Noclip " .. (v and "on" or "off"), v and "ok" or "info")
end)
makeToggle(selfPage, "Infinite Jump", function(v)
    setInfJump(v); pushLog(("infjump %s"):format(tostring(v)))
end)
makeSlider(selfPage, "Fly Speed", 20, 500, State.flySpeed, 5, function(v) State.flySpeed = v end)
makeSlider(selfPage, "Walk Speed", 16, 500, State.walkSpeed, 2, function(v)
    State.walkSpeed = v; State.walkSpeedOn = true; applyWalkSpeed()
end)
makeSlider(selfPage, "Jump Power", 50, 500, State.jumpPower, 5, function(v)
    State.jumpPower = v; State.jumpPowerOn = true; applyJumpPower()
end)

header(selfPage, "Status")
makeToggle(selfPage, "Invisible", function(v) setInvisible(v); pushLog("invis " .. tostring(v)) end)
makeToggle(selfPage, "God Mode",  function(v) setGodMode(v);  pushLog("god "   .. tostring(v)) end)
makeButton(selfPage, "Heal",            function() heal();      notify("Healed", "ok") end)
makeButton(selfPage, "Reset Character", function() resetChar(); notify("Reset",  "info") end)
makeButton(selfPage, "Sit",             function() sit() end)

-- ── PLAYERS ──────────────────────────────────────────────────────────────
local playersPage = createTab("players", "👥  Players")

local targetLbl = new("TextLabel", {
    BackgroundColor3       = Theme.Bg3,
    BackgroundTransparency = 0.15,
    BorderSizePixel        = 0,
    Size                   = UDim2.new(1, 0, 0, 30),
    Font                   = Enum.Font.GothamMedium,
    Text                   = "  Target: (none)",
    TextColor3             = Theme.Text,
    TextSize               = 13,
    TextXAlignment         = Enum.TextXAlignment.Left,
    Parent                 = playersPage,
}, { new("UICorner", { CornerRadius = UDim.new(0, 8) }) }) :: TextLabel

local searchBox = new("TextBox", {
    BackgroundColor3       = Theme.Bg3,
    BackgroundTransparency = 0.15,
    BorderSizePixel        = 0,
    Size                   = UDim2.new(1, 0, 0, 30),
    Font                   = Enum.Font.Gotham,
    PlaceholderText        = "🔍   search players…",
    PlaceholderColor3      = Theme.TextMuted,
    Text                   = "",
    TextColor3             = Theme.Text,
    TextSize               = 13,
    ClearTextOnFocus       = false,
    Parent                 = playersPage,
}, {
    new("UICorner",  { CornerRadius = UDim.new(0, 8) }),
    new("UIPadding", { PaddingLeft = UDim.new(0, 12) }),
}) :: TextBox

local listBox = new("Frame", {
    BackgroundColor3       = Theme.Bg3,
    BackgroundTransparency = 0.15,
    BorderSizePixel        = 0,
    Size                   = UDim2.new(1, 0, 0, 150),
    Parent                 = playersPage,
}, { new("UICorner", { CornerRadius = UDim.new(0, 8) }) }) :: Frame

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
    new("UIListLayout", { Padding = UDim.new(0, 2) }),
    new("UIPadding",    {
        PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 4),
        PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 4),
    }),
}) :: ScrollingFrame

local function setTarget(p: Player?)
    State.target = p
    targetLbl.Text = p
        and ("  Target: %s  (%s)"):format(p.Name, p.DisplayName)
        or  "  Target: (none)"
end

local refreshList: () -> ()
do
    local refreshing = false
    refreshList = function()
        if refreshing then return end
        refreshing = true
        task.defer(function()
            refreshing = false
            local q = searchBox.Text:lower()
            for _, c in ipairs(listScroll:GetChildren()) do
                if c:IsA("TextButton") then c:Destroy() end
            end
            for _, p in ipairs(Players:GetPlayers()) do
                if p ~= LocalPlayer
                and (q == "" or p.Name:lower():find(q, 1, true) or p.DisplayName:lower():find(q, 1, true)) then
                    local entry = new("TextButton", {
                        BackgroundColor3       = Theme.Bg2,
                        BackgroundTransparency = 0.15,
                        BorderSizePixel        = 0,
                        Size                   = UDim2.new(1, 0, 0, 26),
                        Font                   = Enum.Font.GothamMedium,
                        Text                   = ("  %s   (%s)"):format(p.Name, p.DisplayName),
                        TextColor3             = Theme.Text,
                        TextSize               = 12,
                        TextXAlignment         = Enum.TextXAlignment.Left,
                        AutoButtonColor        = false,
                        Parent                 = listScroll,
                    }, { new("UICorner", { CornerRadius = UDim.new(0, 6) }) }) :: TextButton
                    entry.MouseEnter:Connect(function() tween(entry, TWEEN_FAST, { BackgroundColor3 = Theme.Accent }) end)
                    entry.MouseLeave:Connect(function() tween(entry, TWEEN_FAST, { BackgroundColor3 = Theme.Bg2   }) end)
                    entry.MouseButton1Click:Connect(function() setTarget(p) end)
                end
            end
        end)
    end
end

searchBox:GetPropertyChangedSignal("Text"):Connect(refreshList)

header(playersPage, "Target Actions")
local function require_target(fn)
    return function()
        if State.target then fn(State.target) else notify("Select a player first", "warn") end
    end
end
makeButton(playersPage, "Teleport to Player", require_target(function(p) teleportTo(p); pushLog("tp " .. p.Name);  notify("→ " .. p.Name, "ok") end))
makeButton(playersPage, "Bring Player",       require_target(function(p) bring(p);       pushLog("bring " .. p.Name); notify("Brought " .. p.Name .. " (client-side)", "ok") end))
makeButton(playersPage, "Spectate Player",    require_target(function(p) setSpectate(p); pushLog("spec " .. p.Name);  notify("Spectating " .. p.Name, "info") end))
makeButton(playersPage, "Stop Spectating",                  function()  setSpectate(nil); pushLog("unspec");           notify("Spectate cleared", "info") end)
makeButton(playersPage, "View Player",        require_target(function(p) viewAtPlayer(p); pushLog("view " .. p.Name);  notify("Viewing " .. p.Name, "info") end))
makeButton(playersPage, "Freeze Player",      require_target(function(p) setFreeze(p, true);  pushLog("freeze " .. p.Name);   notify("Froze " .. p.Name, "ok") end))
makeButton(playersPage, "Unfreeze Player",    require_target(function(p) setFreeze(p, false); pushLog("unfreeze " .. p.Name); notify("Unfroze " .. p.Name, "info") end))

-- ── VEHICLE ──────────────────────────────────────────────────────────────
local vehiclePage = createTab("vehicle", "🚗  Vehicle")
header(vehiclePage, "Drive Tuning")
makeSlider(vehiclePage, "Speed Multiplier", 1, 10, 1, 1, function(v) State.vSpeedMult = v; applyVehicleTuning() end)
makeToggle(vehiclePage, "Instant Acceleration", function(v) State.vInstant = v; applyVehicleTuning() end)
makeButton(vehiclePage, "Boost Impulse", function() vehicleBoost(); pushLog("vboost") end)
makeToggle(vehiclePage, "Vehicle Fly  (WASD + Space/Ctrl)", function(v)
    setVehicleFly(v); pushLog("vfly " .. tostring(v))
end)
makeButton(vehiclePage, "Re-detect Vehicle", function()
    local m = getVehicle()
    if m then notify("Vehicle: " .. m.Name, "ok") else notify("No vehicle detected", "warn") end
end)

-- ── FUN ──────────────────────────────────────────────────────────────────
local funPage = createTab("fun", "✨  Fun")
header(funPage, "Camera & World")
makeSlider(funPage, "Field of View", 30, 120, State.fov, 1, function(v)
    State.fov = v; State.fovOn = true; applyFOV()
end)
makeSlider(funPage, "Gravity", 0, 400, math.floor(State.gravity), 1, function(v)
    State.gravity = v; State.gravityOn = true; applyGravity()
end)
makeButton(funPage, "Day",   function() setTimeOfDay(14); notify("Time → Day",   "ok") end)
makeButton(funPage, "Night", function() setTimeOfDay(0);  notify("Time → Night", "info") end)

header(funPage, "Visuals")
makeToggle(funPage, "ESP / Highlights", function(v) setESP(v) end)
makeToggle(funPage, "Tracers",          function(v) setTracers(v) end)
makeToggle(funPage, "Fullbright",       function(v) setFullbright(v) end)

-- ── LOGS ─────────────────────────────────────────────────────────────────
local logPage = createTab("logs", "📜  Logs")
header(logPage, "Command History")
local logBox = new("Frame", {
    BackgroundColor3       = Theme.Bg3,
    BackgroundTransparency = 0.15,
    BorderSizePixel        = 0,
    Size                   = UDim2.new(1, 0, 0, 280),
    Parent                 = logPage,
}, { new("UICorner", { CornerRadius = UDim.new(0, 8) }) }) :: Frame
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
    new("UIPadding",    {
        PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8),
        PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10),
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
logChanged.Event:Connect(function()
    if currentTab == "logs" then refreshLogs() end
end)
makeButton(logPage, "Clear Logs", function() table.clear(Log); refreshLogs() end)

-- ── INFO ─────────────────────────────────────────────────────────────────
local infoPage = createTab("info", "⚙️  Info")
header(infoPage, "Session")

local function infoBlock(parent: Instance, text: string, height: number, font: Enum.Font?)
    new("TextLabel", {
        BackgroundColor3       = Theme.Bg3,
        BackgroundTransparency = 0.15,
        BorderSizePixel        = 0,
        Size                   = UDim2.new(1, 0, 0, height),
        Font                   = font or Enum.Font.Gotham,
        Text                   = text,
        TextColor3             = Theme.Text,
        TextSize               = 12,
        TextXAlignment         = Enum.TextXAlignment.Left,
        TextYAlignment         = Enum.TextYAlignment.Top,
        Parent                 = parent,
    }, {
        new("UICorner",  { CornerRadius = UDim.new(0, 8) }),
        new("UIPadding", {
            PaddingTop = UDim.new(0, 10), PaddingBottom = UDim.new(0, 10),
            PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12),
        }),
    })
end

infoBlock(infoPage, ("Owner:     %s\nWhitelist: %d entries\nRank:      %s\nKeybind:   %s\nPrefix:    %s"):format(
    CONFIG.Owner == "" and "(unset — any user)" or CONFIG.Owner,
    #CONFIG.Whitelist, rankOf(LocalPlayer.Name),
    CONFIG.ToggleKey.Name, CONFIG.CommandPrefix), 110)

header(infoPage, "Commands")
infoBlock(infoPage, [[
fly                       toggle flight
noclip                    toggle noclip
ws / walkspeed <n>        set walkspeed
jp / jumppower <n>        set jump power
infjump                   toggle infinite jump
invis / god               toggle status
heal / reset / sit        utilities
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

-- ── Wire up tab buttons (after every page is created)
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
    elseif cmd == "god"        then setGodMode(not State.godMode)
    elseif cmd == "ungod"      then setGodMode(false)
    elseif cmd == "heal"       then heal()
    elseif cmd == "reset" or cmd == "re" then resetChar()
    elseif cmd == "sit"        then sit()
    elseif cmd == "tp"         then local t = p(); if t then teleportTo(t)     else notify("Player not found", "warn") end
    elseif cmd == "bring"      then local t = p(); if t then bring(t)          else notify("Player not found", "warn") end
    elseif cmd == "spec"       then
        if (parts[2] or ""):lower() == "off" or parts[2] == nil then setSpectate(nil)
        else local t = p(); if t then setSpectate(t) else notify("Player not found", "warn") end end
    elseif cmd == "view"       then local t = p(); if t then viewAtPlayer(t)   else notify("Player not found", "warn") end
    elseif cmd == "freeze"     then local t = p(); if t then setFreeze(t, true)  else notify("Player not found", "warn") end
    elseif cmd == "unfreeze"   then local t = p(); if t then setFreeze(t, false) else notify("Player not found", "warn") end
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
end

cmdInput.FocusLost:Connect(function(enter)
    if enter and Rate.allow("cmd", 0.05) then
        local text = cmdInput.Text
        cmdInput.Text = ""
        safe(runCommand, text)
    end
end)

-- ╔══════════════════════════════════════════════════════════════════════╗
-- ║  OPEN / CLOSE / MINIMIZE                                              ║
-- ╚══════════════════════════════════════════════════════════════════════╝
local opened    = false
local minimized = false
local function setOpen(state: boolean)
    if state == opened then return end
    opened = state
    if state then
        panel.Visible              = true
        panel.Size                 = UDim2.fromOffset(0, 0)
        panel.BackgroundTransparency = 1
        tween(panel, TWEEN_POP, {
            Size                   = UDim2.fromOffset(CONFIG.PanelSize.X, CONFIG.PanelSize.Y),
            BackgroundTransparency = CONFIG.BackgroundAlpha,
        })
    else
        local t = tween(panel, TWEEN_FAST, {
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
    tween(panel, TWEEN_FAST, {
        Size = minimized
            and UDim2.fromOffset(CONFIG.PanelSize.X, 44)
            or  UDim2.fromOffset(CONFIG.PanelSize.X, CONFIG.PanelSize.Y),
    })
end)

UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end
    if input.KeyCode == CONFIG.ToggleKey then setOpen(not opened) end
end)

-- ╔══════════════════════════════════════════════════════════════════════╗
-- ║  MOBILE TOGGLE BUTTON                                                 ║
-- ╚══════════════════════════════════════════════════════════════════════╝
if CONFIG.MobileButton and UserInputService.TouchEnabled and not UserInputService.MouseEnabled then
    local btn = new("TextButton", {
        Name                   = "MobileToggle",
        AnchorPoint            = Vector2.new(0, 0.5),
        Position               = UDim2.new(0, 10, 0.35, 0),
        Size                   = UDim2.fromOffset(56, 56),
        BackgroundColor3       = Theme.Accent,
        BackgroundTransparency = 0.1,
        BorderSizePixel        = 0,
        Font                   = Enum.Font.GothamBold,
        Text                   = "≡",
        TextColor3             = Color3.fromRGB(255, 255, 255),
        TextSize               = 28,
        AutoButtonColor        = false,
        Parent                 = gui,
    }, {
        new("UICorner", { CornerRadius = UDim.new(1, 0) }),
        new("UIStroke", { Color = Color3.fromRGB(255, 255, 255), Transparency = 0.6 }),
    }) :: TextButton

    local dragging, startMouse, startPos
    btn.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch then
            dragging   = true
            startMouse = input.Position
            startPos   = btn.Position
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if dragging and input.UserInputType == Enum.UserInputType.Touch then
            local d = input.Position - startMouse
            btn.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + d.X,
                startPos.Y.Scale, startPos.Y.Offset + d.Y
            )
        end
    end)
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch then
            if dragging and (input.Position - startMouse).Magnitude < 6 then
                setOpen(not opened)
            end
            dragging = false
        end
    end)
end

-- ╔══════════════════════════════════════════════════════════════════════╗
-- ║  LIFECYCLE — players & respawn                                        ║
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
    if State.noclip      then setNoclip(true) end           -- safe: no-op if already on
    if State.walkSpeedOn then applyWalkSpeed() end
    if State.jumpPowerOn then applyJumpPower() end
    if State.invisible   then setInvisible(true) end
    if State.godMode     then Maids.god:clean(); State.godMode = false; setGodMode(true) end
    if State.spectating and State.spectating.Parent then setSpectate(State.spectating) end
end)

LocalPlayer.CharacterRemoving:Connect(function()
    Maids.fly:clean()
    -- noclip's Stepped loop handles missing character itself, safe to leave running
end)

Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
    Camera = Workspace.CurrentCamera
    if State.fovOn then Camera.FieldOfView = State.fov end
end)

-- ╔══════════════════════════════════════════════════════════════════════╗
-- ║  BOOT                                                                 ║
-- ╚══════════════════════════════════════════════════════════════════════╝
applyFOV()
applyGravity()
notify(("Admin Panel ready — press %s"):format(CONFIG.ToggleKey.Name), "ok")
