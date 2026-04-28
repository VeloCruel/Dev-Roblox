-- Interface.lua (ModuleScript)
-- Builds and updates a minimalist flight HUD in the corner of the screen.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local PALETTE = {
	bg       = Color3.fromRGB(8,  12, 22),
	on       = Color3.fromRGB(90, 210, 255),
	boost    = Color3.fromRGB(255, 195, 50),
	off      = Color3.fromRGB(160, 160, 175),
	text     = Color3.fromRGB(225, 235, 255),
	subtext  = Color3.fromRGB(140, 155, 180),
}

local TWEEN_INFO = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local Interface = {}
Interface.__index = Interface

-- ── Internal builders ─────────────────────────────────────────────────────────

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

function Interface:_build()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	local sg = Instance.new("ScreenGui")
	sg.Name           = "FlightHUD"
	sg.ResetOnSpawn   = false
	sg.IgnoreGuiInset = true
	sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	sg.Parent         = playerGui

	-- Outer panel
	local panel = Instance.new("Frame")
	panel.Name                  = "Panel"
	panel.Size                  = UDim2.new(0, 170, 0, 64)
	panel.Position              = UDim2.new(1, -188, 0, 18)
	panel.BackgroundColor3      = PALETTE.bg
	panel.BackgroundTransparency = 0.28
	panel.BorderSizePixel       = 0
	panel.Parent                = sg

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 9)
	corner.Parent = panel

	-- Left accent bar (colour-coded)
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

	-- Status row
	local statusLbl = makeLabel(
		panel, "Status",
		UDim2.new(1, -24, 0, 26),
		UDim2.new(0, 22, 0, 6),
		13, Enum.Font.GothamBold,
		PALETTE.text
	)
	statusLbl.Text = "FLIGHT   OFF"

	-- Speed row
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
	self._lastState = nil   -- track to avoid redundant tweens
end

-- ── Public API ────────────────────────────────────────────────────────────────

function Interface.new()
	local self = setmetatable({}, Interface)
	self:_build()
	return self
end

function Interface:update(isFlying, speed, isBoosting)
	if not self._sg then return end

	-- Only tween colour when state changes
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
		TweenService:Create(self._statusLbl, TWEEN_INFO, { TextColor3       = isFlying and accentColor or PALETTE.text }):Play()

		self._statusLbl.Text = statusText
	end

	self._speedLbl.Text = string.format("SPD  %d u/s", math.floor(speed + 0.5))
end

function Interface:destroy()
	if self._sg then
		self._sg:Destroy()
		self._sg = nil
	end
end

return Interface
