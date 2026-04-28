-- Animator.lua
-- Plays animations on the local character at Action4 priority.
-- Animator:LoadAnimation from a LocalScript replicates to all clients.

local Animator = {}
Animator.__index = Animator

-- Idle animation IDs from famous Roblox animation packages
Animator.PRESETS = {
	{ name = "None",        id = nil            },
	{ name = "TOY",         id = "782841498"    },
	{ name = "Robot",       id = "313382498"    },
	{ name = "Ninja",       id = "656118852"    },
	{ name = "Superhero",   id = "616072382"    },
	{ name = "Zombie",      id = "616163890"    },
	{ name = "Astronaut",   id = "891836989"    },
	{ name = "Mage",        id = "707855543"    },
	{ name = "Knight",      id = "657564596"    },
	{ name = "Pirate",      id = "750711522"    },
	{ name = "Werewolf",    id = "1083216690"   },
}

-- Returns a flat list of preset names for Rayfield dropdown
function Animator.presetNames()
	local names = {}
	for _, p in ipairs(Animator.PRESETS) do
		names[#names + 1] = p.name
	end
	return names
end

-- Extracts the numeric asset ID from any format:
--   "782841498", "rbxassetid://782841498", "http://...782841498", etc.
local function parseId(raw)
	if not raw or raw == "" then return nil end
	local n = tostring(raw):match("%d+")
	return n and ("rbxassetid://" .. n) or nil
end

function Animator.new()
	return setmetatable({ _track = nil, _anim = nil, _currentId = nil }, Animator)
end

function Animator:play(character, rawId)
	self:stop()

	local assetId = parseId(rawId)
	if not assetId then return end

	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end
	local animatorObj = humanoid:FindFirstChildOfClass("Animator")
	if not animatorObj then return end

	local anim = Instance.new("Animation")
	anim.AnimationId = assetId

	local ok, track = pcall(function()
		return animatorObj:LoadAnimation(anim)
	end)

	if not ok or not track then
		warn("[Animator] Failed to load animation:", rawId, track)
		anim:Destroy()
		return
	end

	track.Priority = Enum.AnimationPriority.Action4
	track.Looped   = true
	track:Play()

	self._track     = track
	self._anim      = anim
	self._currentId = rawId
end

function Animator:stop()
	if self._track then
		self._track:Stop()
		self._track:Destroy()
		self._track = nil
	end
	if self._anim then
		self._anim:Destroy()
		self._anim = nil
	end
	self._currentId = nil
end

-- Replays the current animation on a new character (used after respawn)
function Animator:replayOn(character)
	if self._currentId then
		self:play(character, self._currentId)
	end
end

function Animator:getCurrentId()
	return self._currentId
end

return Animator
