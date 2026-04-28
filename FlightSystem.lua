--[[
    FlightSystem.lua — Single-file executor bundle
    Inlines Controller + Interface + Main into one self-contained script.
    Run directly in any Roblox executor (no ModuleScript tree required).

    Controls:
        F            — toggle flight on / off
        W A S D      — move (camera-relative)
        Space        — ascend
        LeftCtrl     — descend
        Shift (hold) — speed boost
]]

-- ── Shared services (deduplicated) ───────────────────────────────────────────

local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local TweenService     = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace        = game:GetService("Workspace")

-- ── MODULE: Controller ────────────────────────────────────────────────────────

local Controller = (function()

    local NORMAL_SPEED   = 50
    local BOOST_SPEED    = 120
    local VERTICAL_SPEED = 30
    local ACCELERATION   = 8

    local M = {}
    M.__index = M

    function M.new()
        return setmetatable({
            active      = false,
            boosting    = false,
            speed       = 0,
            _inputVec   = Vector3.zero,
            _vertInput  = 0,
            _connection = nil,
            _lv         = nil,
            _ao         = nil,
            _attach     = nil,
        }, M)
    end

    function M:_attach_create(rootPart)
        local a = Instance.new("Attachment")
        a.Name   = "FlightAttachment"
        a.Parent = rootPart
        self._attach = a

        local lv = Instance.new("LinearVelocity")
        lv.Name                   = "FlightLV"
        lv.Attachment0            = a
        lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
        lv.RelativeTo             = Enum.ActuatorRelativeTo.World
        lv.MaxForce               = math.huge
        lv.VectorVelocity         = Vector3.zero
        lv.Parent                 = rootPart
        self._lv = lv

        local ao = Instance.new("AlignOrientation")
        ao.Name               = "FlightAO"
        ao.Attachment0        = a
        ao.Mode               = Enum.OrientationAlignmentMode.OneAttachment
        ao.MaxTorque          = math.huge
        ao.MaxAngularVelocity = math.huge
        ao.Responsiveness     = 50
        ao.CFrame             = rootPart.CFrame
        ao.Parent             = rootPart
        self._ao = ao
    end

    function M:_attach_destroy()
        if self._lv     then self._lv:Destroy();     self._lv     = nil end
        if self._ao     then self._ao:Destroy();     self._ao     = nil end
        if self._attach then self._attach:Destroy(); self._attach = nil end
    end

    local function camRelativeVelocity(inputVec, camera, speed)
        local look  = camera.CFrame.LookVector
        local right = camera.CFrame.RightVector
        local fwd   = Vector3.new(look.X,  0, look.Z).Unit
        local rgt   = Vector3.new(right.X, 0, right.Z).Unit
        return (fwd * -inputVec.Z + rgt * inputVec.X) * speed
    end

    function M:enable(character)
        if self.active then return end

        local root     = character:FindFirstChild("HumanoidRootPart")
        local humanoid = character:FindFirstChildOfClass("Humanoid")
        if not root or not humanoid then return end

        humanoid.PlatformStand         = true
        root.AssemblyLinearVelocity    = Vector3.zero
        root.AssemblyAngularVelocity   = Vector3.zero

        self:_attach_create(root)
        self.active = true

        local camera         = Workspace.CurrentCamera
        local smoothVelocity = Vector3.zero

        self._connection = RunService.Heartbeat:Connect(function(dt)
            if not self.active then return end
            if not character.Parent then self:disable(character); return end

            local targetSpeed = self.boosting and BOOST_SPEED or NORMAL_SPEED
            local horizontal  = camRelativeVelocity(self._inputVec, camera, targetSpeed)
            local vertical    = Vector3.new(0, self._vertInput * VERTICAL_SPEED, 0)
            local target      = horizontal + vertical

            local t = 1 - math.exp(-ACCELERATION * dt)
            smoothVelocity          = smoothVelocity:Lerp(target, t)
            self._lv.VectorVelocity = smoothVelocity

            if horizontal.Magnitude > 0.5 then
                self._ao.CFrame = CFrame.lookAt(root.Position, root.Position + horizontal.Unit)
            end

            self.speed = smoothVelocity.Magnitude
        end)
    end

    function M:disable(character)
        if not self.active then return end
        self.active = false
        self.speed  = 0

        if self._connection then
            self._connection:Disconnect()
            self._connection = nil
        end

        self:_attach_destroy()

        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        if humanoid then humanoid.PlatformStand = false end
    end

    function M:setInput(inputVec, vertInput)
        self._inputVec  = inputVec
        self._vertInput = vertInput
    end

    function M:setBoosting(state) self.boosting = state end
    function M:isActive()         return self.active    end
    function M:getSpeed()         return self.speed     end

    return M
end)()

-- ── MODULE: Interface ─────────────────────────────────────────────────────────

local Interface = (function()

    local PALETTE = {
        bg      = Color3.fromRGB(8,   12,  22),
        on      = Color3.fromRGB(90,  210, 255),
        boost   = Color3.fromRGB(255, 195, 50),
        off     = Color3.fromRGB(160, 160, 175),
        text    = Color3.fromRGB(225, 235, 255),
        subtext = Color3.fromRGB(140, 155, 180),
    }

    local TWEEN_INFO = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

    local function makeLabel(parent, name, size, pos, textSize, font, color, transparency)
        local lbl = Instance.new("TextLabel")
        lbl.Name               = name
        lbl.Size               = size
        lbl.Position           = pos
        lbl.BackgroundTransparency = 1
        lbl.TextColor3         = color
        lbl.TextTransparency   = transparency or 0
        lbl.TextSize           = textSize
        lbl.Font               = font
        lbl.TextXAlignment     = Enum.TextXAlignment.Left
        lbl.RichText           = false
        lbl.Parent             = parent
        return lbl
    end

    local M = {}
    M.__index = M

    function M:_build()
        local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

        -- Remove any stale HUD from a previous execution
        local old = playerGui:FindFirstChild("FlightHUD")
        if old then old:Destroy() end

        local sg = Instance.new("ScreenGui")
        sg.Name           = "FlightHUD"
        sg.ResetOnSpawn   = false
        sg.IgnoreGuiInset = true
        sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
        sg.Parent         = playerGui

        local panel = Instance.new("Frame")
        panel.Name                   = "Panel"
        panel.Size                   = UDim2.new(0, 170, 0, 64)
        panel.Position               = UDim2.new(1, -188, 0, 18)
        panel.BackgroundColor3       = PALETTE.bg
        panel.BackgroundTransparency = 0.28
        panel.BorderSizePixel        = 0
        panel.Parent                 = sg

        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 9)
        corner.Parent = panel

        local bar = Instance.new("Frame")
        bar.Name             = "AccentBar"
        bar.Size             = UDim2.new(0, 3, 1, -16)
        bar.Position         = UDim2.new(0, 10, 0, 8)
        bar.BackgroundColor3 = PALETTE.off
        bar.BorderSizePixel  = 0
        bar.Parent           = panel

        local barCorner = Instance.new("UICorner")
        barCorner.CornerRadius = UDim.new(1, 0)
        barCorner.Parent = bar

        local statusLbl = makeLabel(
            panel, "Status",
            UDim2.new(1, -24, 0, 26),
            UDim2.new(0, 22, 0, 6),
            13, Enum.Font.GothamBold,
            PALETTE.text
        )
        statusLbl.Text = "FLIGHT   OFF"

        local speedLbl = makeLabel(
            panel, "Speed",
            UDim2.new(1, -24, 0, 20),
            UDim2.new(0, 22, 0, 33),
            11, Enum.Font.Gotham,
            PALETTE.subtext, 0
        )
        speedLbl.Text = "SPD  0 u/s"

        self._sg        = sg
        self._bar       = bar
        self._statusLbl = statusLbl
        self._speedLbl  = speedLbl
        self._lastState = nil
    end

    function M.new()
        local self = setmetatable({}, M)
        self:_build()
        return self
    end

    function M:update(isFlying, speed, isBoosting)
        if not self._sg then return end

        local stateKey = tostring(isFlying) .. tostring(isBoosting)
        if stateKey ~= self._lastState then
            self._lastState = stateKey

            local accentColor, statusText
            if isFlying then
                accentColor = isBoosting and PALETTE.boost or PALETTE.on
                statusText  = isBoosting and "FLIGHT   BOOST" or "FLIGHT   ON"
            else
                accentColor = PALETTE.off
                statusText  = "FLIGHT   OFF"
            end

            TweenService:Create(self._bar,       TWEEN_INFO, { BackgroundColor3 = accentColor }):Play()
            TweenService:Create(self._statusLbl, TWEEN_INFO, { TextColor3 = isFlying and accentColor or PALETTE.text }):Play()
            self._statusLbl.Text = statusText
        end

        self._speedLbl.Text = string.format("SPD  %d u/s", math.floor(speed + 0.5))
    end

    function M:destroy()
        if self._sg then self._sg:Destroy(); self._sg = nil end
    end

    return M
end)()

-- ── MAIN: input wiring ────────────────────────────────────────────────────────

local player     = Players.LocalPlayer
local controller = Controller.new()
local interface  = Interface.new()

-- Toggle: F
UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end
    if input.KeyCode ~= Enum.KeyCode.F then return end

    local character = player.Character
    if not character then return end

    if controller:isActive() then
        controller:disable(character)
    else
        controller:enable(character)
    end
end)

-- Boost: Shift hold
UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end
    if input.KeyCode == Enum.KeyCode.LeftShift
    or input.KeyCode == Enum.KeyCode.RightShift then
        controller:setBoosting(true)
    end
end)

UserInputService.InputEnded:Connect(function(input)
    if input.KeyCode == Enum.KeyCode.LeftShift
    or input.KeyCode == Enum.KeyCode.RightShift then
        controller:setBoosting(false)
    end
end)

-- Per-frame input sampling
RunService.Heartbeat:Connect(function()
    if not controller:isActive() then
        interface:update(false, 0, false)
        return
    end

    local inputVec = Vector3.new(
        (UserInputService:IsKeyDown(Enum.KeyCode.D) and 1 or 0)
        - (UserInputService:IsKeyDown(Enum.KeyCode.A) and 1 or 0),
        0,
        (UserInputService:IsKeyDown(Enum.KeyCode.S) and 1 or 0)
        - (UserInputService:IsKeyDown(Enum.KeyCode.W) and 1 or 0)
    )

    local vertInput =
        (UserInputService:IsKeyDown(Enum.KeyCode.Space)       and 1 or 0)
        - (UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) and 1 or 0)

    controller:setInput(inputVec, vertInput)
    interface:update(true, controller:getSpeed(), controller.boosting)
end)

-- Cleanup on respawn
player.CharacterRemoving:Connect(function(character)
    controller:disable(character)
end)
