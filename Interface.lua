-- Interface.lua — Rayfield UI integration

local Rayfield = loadstring(game:HttpGet("https://sirius.menu/rayfield"))()

local Interface = {}
Interface.__index = Interface

function Interface.new()
	local self = setmetatable({}, Interface)
	self._lastState = nil
	self._lastSpeed = -1

	self._win = Rayfield:CreateWindow({
		Name                   = "Flight System",
		LoadingTitle           = "Flight System",
		LoadingSubtitle        = "by VeloCruel",
		Theme                  = "Default",
		DisableRayfieldPrompts = true,
		DisableBuildWarnings   = true,
		ConfigurationSaving    = { Enabled = false },
		KeySystem              = false,
	})

	local tab = self._win:CreateTab("HUD", 4483362458)
	tab:CreateSection("Flight Status")

	self._statusLabel = tab:CreateLabel("FLIGHT   OFF")
	self._speedLabel  = tab:CreateLabel("SPD  0 u/s")

	return self
end

function Interface:update(isFlying, speed, isBoosting)
	local stateKey = tostring(isFlying) .. tostring(isBoosting)

	if stateKey ~= self._lastState then
		self._lastState = stateKey

		local statusText
		if isFlying then
			statusText = isBoosting and "FLIGHT   BOOST" or "FLIGHT   ON"
		else
			statusText = "FLIGHT   OFF"
		end

		self._statusLabel:Set(statusText)

		Rayfield:Notify({
			Title    = "Flight System",
			Content  = statusText,
			Duration = 2,
		})
	end

	-- Only write to the label when the rounded value actually changes
	local rounded = math.floor(speed + 0.5)
	if rounded ~= self._lastSpeed then
		self._lastSpeed = rounded
		self._speedLabel:Set(string.format("SPD  %d u/s", rounded))
	end
end

function Interface:destroy()
	self._win         = nil
	self._statusLabel = nil
	self._speedLabel  = nil
end

return Interface
