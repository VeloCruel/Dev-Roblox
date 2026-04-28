-- Animator.lua
-- Working animation changer approach:
--   1. Disable the character's Animate LocalScript so it cannot override us.
--   2. Kill every active track with zero fade.
--   3. Load and play our animation — Animator replicates it to all clients.
--   4. On stop, re-enable Animate so normal movement animations resume.

local Animator = {}
Animator.__index = Animator

Animator.PRESETS = {
	{ name = "None",       id = nil           },
	{ name = "TOY",        id = "782841498"   },
	{ name = "Robot",      id = "313382498"   },
	{ name = "Ninja",      id = "656118852"   },
	{ name = "Superhero",  id = "616072382"   },
	{ name = "Zombie",     id = "616163890"   },
	{ name = "Astronaut",  id = "891836989"   },
	{ name = "Mage",       id = "707855543"   },
	{ name = "Knight",     id = "657564596"   },
	{ name = "Pirate",     id = "750711522"   },
	{ name = "Werewolf",   id = "1083216690"  },
}

function Animator.presetNames()
	local t = {}
	for _, p in ipairs(Animator.PRESETS) do t[#t + 1] = p.name end
	return t
end

local function parseId(raw)
	if not raw or raw == "" then return nil end
	local n = tostring(raw):match("%d+")
	return n and ("rbxassetid://" .. n) or nil
end

function Animator.new()
	return setmetatable({
		_track      = nil,
		_anim       = nil,
		_currentId  = nil,
		_animScript = nil,   -- reference to character's Animate LocalScript
	}, Animator)
end

function Animator:play(character, rawId)
	self:stop()

	local assetId = parseId(rawId)
	if not assetId then
		warn("[Animator] Invalid animation ID:", tostring(rawId))
		return
	end

	local humanoid    = character:FindFirstChildOfClass("Humanoid")
	local animatorObj = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if not animatorObj then
		warn("[Animator] Animator not found on character")
		return
	end

	-- Step 1: disable the Animate LocalScript so it can't fight us
	local animScript = character:FindFirstChild("Animate")
	if animScript then
		animScript.Disabled  = true
		self._animScript = animScript
	end

	-- Step 2: kill every currently-playing track immediately
	for _, t in ipairs(animatorObj:GetPlayingAnimationTracks()) do
		t:Stop(0)
	end

	-- Step 3: load and play our animation
	local anim = Instance.new("Animation")
	anim.AnimationId = assetId

	local track = animatorObj:LoadAnimation(anim)
	track.Priority = Enum.AnimationPriority.Action4
	track.Looped   = true
	track:Play(0)

	self._track     = track
	self._anim      = anim
	self._currentId = rawId
end

function Animator:stop()
	if self._track then
		self._track:Stop(0)
		self._track:Destroy()
		self._track = nil
	end
	if self._anim then
		self._anim:Destroy()
		self._anim = nil
	end

	-- Re-enable Animate so normal walk/idle animations come back
	if self._animScript then
		self._animScript.Disabled = false
		self._animScript = nil
	end

	self._currentId = nil
end

-- Call after respawn with the new character instance
function Animator:replayOn(character)
	if self._currentId then
		local id        = self._currentId
		self._currentId = nil
		self._animScript = nil
		self:play(character, id)
	end
end

function Animator:getCurrentId()
	return self._currentId
end

return Animator
