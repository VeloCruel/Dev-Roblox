-- Interface.lua — Rayfield UI
-- Interface.new(callbacks) where callbacks = { onFlightToggle(bool), onBoostToggle(bool) }

local Rayfield = loadstring(game:HttpGet("https://sirius.menu/rayfield"))()

local Interface = {}
Interface.__index = Interface

function Interface.new(callbacks)
	local self      = setmetatable({}, Interface)
	self._lastState = nil
	self._lastSpeed = -1
	self._syncing   = false   -- guard against callback loops when we set toggles

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

	-- ── Controls tab ──────────────────────────────────────────────────────────

	local ctrlTab = self._win:CreateTab("Controls", 4483362458)
	ctrlTab:CreateSection("Toggles")

	self._flightToggle = ctrlTab:CreateToggle({
		Name         = "Enable Flight  [F]",
		CurrentValue = false,
		Flag         = "FlightEnabled",
		Callback     = function(val)
			if self._syncing then return end
			if callbacks and callbacks.onFlightToggle then
				callbacks.onFlightToggle(val)
			end
		end,
	})

	self._boostToggle = ctrlTab:CreateToggle({
		Name         = "Speed Boost  [Shift]",
		CurrentValue = false,
		Flag         = "BoostEnabled",
		Callback     = function(val)
			if self._syncing then return end
			if callbacks and callbacks.onBoostToggle then
				callbacks.onBoostToggle(val)
			end
		end,
	})

	-- ── HUD tab ───────────────────────────────────────────────────────────────

	local hudTab = self._win:CreateTab("HUD", 4483362458)
	hudTab:CreateSection("Live Stats")

	self._statusLabel = hudTab:CreateLabel("FLIGHT   OFF")
	self._speedLabel  = hudTab:CreateLabel("SPD  0 u/s")

	return self
end

-- Sync Rayfield toggle without re-firing the user callback
function Interface:_setToggle(toggle, value)
	if not toggle then return end
	self._syncing = true
	toggle:Set(value)
	self._syncing = false
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

		-- Sync toggles to reflect state changes made via F / Shift keys
		self:_setToggle(self._flightToggle, isFlying)
		self:_setToggle(self._boostToggle,  isBoosting)

		Rayfield:Notify({
			Title    = "Flight System",
			Content  = statusText,
			Duration = 2,
		})
	end

	local rounded = math.floor(speed + 0.5)
	if rounded ~= self._lastSpeed then
		self._lastSpeed = rounded
		self._speedLabel:Set(string.format("SPD  %d u/s", rounded))
	end
end

function Interface:destroy()
	self._win = nil
end

return Interface
