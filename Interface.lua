-- Interface.lua — Rayfield UI
-- Interface.new(callbacks)
--   callbacks.onFlightToggle(bool)
--   callbacks.onBoostToggle(bool)
--   callbacks.onAnimPreset(presetName)
--   callbacks.onAnimCustom(rawId)
--   callbacks.onAnimReset()

local Rayfield = loadstring(game:HttpGet("https://sirius.menu/rayfield"))()

local Interface = {}
Interface.__index = Interface

function Interface.new(callbacks)
	local self      = setmetatable({}, Interface)
	self._lastState = nil
	self._lastSpeed = -1
	self._syncing   = false
	self._customId  = ""

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
	ctrlTab:CreateSection("Flight Toggles")

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

	-- ── Animations tab ────────────────────────────────────────────────────────

	local animTab = self._win:CreateTab("Animations", 4483362458)

	animTab:CreateSection("Presets")

	local presetNames = callbacks and callbacks.presetNames or { "None" }

	animTab:CreateDropdown({
		Name            = "Select Animation",
		Options         = presetNames,
		CurrentOption   = { "None" },
		MultipleOptions = false,
		Flag            = "AnimPreset",
		Callback        = function(option)
			if callbacks and callbacks.onAnimPreset then
				callbacks.onAnimPreset(option)
			end
		end,
	})

	animTab:CreateButton({
		Name     = "Reset / Stop Animation",
		Callback = function()
			if callbacks and callbacks.onAnimReset then
				callbacks.onAnimReset()
			end
		end,
	})

	animTab:CreateSection("Custom Animation")

	animTab:CreateInput({
		Name                    = "Animation ID",
		CurrentValue            = "",
		PlaceholderText         = "e.g. 782841498",
		RemoveTextAfterFocusLost = false,
		Flag                    = "CustomAnimID",
		Callback                = function(text)
			self._customId = text  -- store; apply on button press
		end,
	})

	animTab:CreateButton({
		Name     = "Apply Custom Animation",
		Callback = function()
			if self._customId and self._customId ~= "" then
				if callbacks and callbacks.onAnimCustom then
					callbacks.onAnimCustom(self._customId)
				end
			end
		end,
	})

	-- ── HUD tab ───────────────────────────────────────────────────────────────

	local hudTab = self._win:CreateTab("HUD", 4483362458)
	hudTab:CreateSection("Live Stats")

	self._statusLabel = hudTab:CreateLabel("FLIGHT   OFF")
	self._speedLabel  = hudTab:CreateLabel("SPD  0 u/s")
	self._animLabel   = hudTab:CreateLabel("ANIM  None")

	return self
end

-- Sync a Rayfield toggle without re-firing the callback
function Interface:_setToggle(toggle, value)
	if not toggle then return end
	self._syncing = true
	pcall(function() toggle:Set(value) end)
	self._syncing = false
end

function Interface:update(isFlying, speed, isBoosting, animName)
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

	if animName then
		self._animLabel:Set("ANIM  " .. tostring(animName))
	end
end

function Interface:destroy()
	self._win = nil
end

return Interface
