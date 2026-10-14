local Config = require(script.Parent.Config)
local P = {}

-- returns level, xpIntoLevel, xpNeededForNextLevel (needed = 0 at max level)
function P.LevelFromXP(xp)
	local C = Config.Progression
	local level, rem = 1, math.max(0, xp)
	while level < C.MaxLevel do
		local need = C.BaseXP + C.PerLevel * (level - 1)
		if rem < need then return level, rem, need end
		rem -= need
		level += 1
	end
	return C.MaxLevel, 0, 0
end

-- total XP a player needs to have earned to be at `level` (level 1 = 0). Used for unlock requirements and buy-forward prices.
function P.XPForLevel(level)
	local C = Config.Progression
	level = math.clamp(math.floor(level), 1, C.MaxLevel)
	local n = level - 1
	return C.BaseXP * n + C.PerLevel * n * (n - 1) // 2
end

return P
