-- Ballistics: analytic bullet flight shared by the server (hit detection) and the clients (tracers).
--
-- Model: constant gravity + linear air drag.        dv/dt = g - k * v
--   v(t) = vT + (v0 - vT) * e^(-k t)                 vT = g / k = terminal velocity (straight down)
--   p(t) = p0 + vT * t + (v0 - vT) * (1 - e^(-k t)) / k
--
-- So a bullet's speed bleeds off with air time (speed ~ e^(-k t)) and it drops under gravity, exactly like CoD's bullet velocity / drop.
-- With k = 0 it is a plain parabola. Because the path is a closed-form function of time, the server and every client evaluate the SAME
-- trajectory from just (origin, muzzle velocity, time of fire): no per-frame bullet replication is needed.
--
-- Tuning lives in Config.Ballistics (class defaults) + optional per-weapon overrides, see Ballistics.For.
local Config = require(script.Parent.Config)

local Ballistics = {}

local function grav(g) return Vector3.new(0, -g, 0) end

-- Position after t seconds in flight.
function Ballistics.Pos(origin, vel, g, k, t)
	if k < 1e-4 then return origin + vel * t + grav(g) * (0.5 * t * t) end
	local vT = grav(g) / k
	return origin + vT * t + (vel - vT) * ((1 - math.exp(-k * t)) / k)
end

-- Velocity vector after t seconds in flight (its magnitude is the current bullet speed).
function Ballistics.Vel(vel, g, k, t)
	if k < 1e-4 then return vel + grav(g) * t end
	local vT = grav(g) / k
	return vT + (vel - vT) * math.exp(-k * t)
end

-- Damage falloff table lookup: list = { {dist, damage}, ... }, linear between entries.
function Ballistics.Falloff(list, d)
	if d <= list[1][1] then return list[1][2] end
	for i = 2, #list do
		local a, b = list[i - 1], list[i]
		if d <= b[1] then return a[2] + (b[2] - a[2]) * (d - a[1]) / (b[1] - a[1]) end
	end
	return list[#list][2]
end

-- Resolved ballistic parameters for a weapon config, or nil when that weapon is hitscan.
--   returns { Speed = muzzle velocity (studs/s), Gravity = studs/s^2, Drag = 1/s, Lifetime = seconds }
-- A weapon is hitscan when: Config.Ballistics.Enabled is false, the weapon sets `Hitscan = true`, its class is marked Hitscan,
-- it has its own `Projectile` entry (launchers: those keep using EquipmentService.Launch) or it has no class entry (melee).
-- Per-weapon overrides: `Ballistics = { Speed = ..., Gravity = ..., Drag = ... }` on the weapon. Attachments scale the speed through `VelMult`.
local cache = setmetatable({}, { __mode = "k" }) -- cfg tables are immutable once built (Armory.Build caches them), so this is safe

function Ballistics.For(cfg)
	local G = Config.Ballistics
	if not G or not G.Enabled or cfg.Projectile or cfg.Hitscan then return nil end
	local hit = cache[cfg]
	if hit ~= nil then return hit or nil end
	local base = G.Classes[cfg.Class]
	if not base or base.Hitscan then
		cache[cfg] = false
		return nil
	end
	local o = cfg.Ballistics
	local p = {
		Speed = ((o and o.Speed) or base.Speed) * (cfg.VelMult or 1),
		Gravity = (o and o.Gravity) or base.Gravity,
		Drag = (o and o.Drag) or base.Drag,
		Lifetime = G.MaxLifetime,
	}
	cache[cfg] = p
	return p
end

return Ballistics
