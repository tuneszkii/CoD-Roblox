-- BulletFX: client visuals for real (ballistic) bullets.
-- Every bullet follows the exact analytic path the server simulates (Ballistics.Pos), so nothing is replicated per frame: a shot only
-- needs (origin, velocity per pellet, gravity, drag, time of fire). Each frame the tracer is moved along that path and a short ray
-- is cast over the distance it covered (same Hitbox raycast the server uses), so the tracer ends on the wall / body it really hits.
--
--   BulletFX.Spawn{ Origin, Vels = {Vector3}, G, K, T0, Range, Style, Ignore, Muzzle?, OnImpact?, Pen? }
--   Pen = the weapon's penetration Power (Penetration.PowerOf): the tracer then flies through the same walls / bodies the server bullet does,
--   and OnImpact fires for every bullet hole (wall entry, wall exit, final stop).
--   BulletFX.Clear()
local RunService = game:GetService("RunService")

local FPS = script.Parent
local Config = require(FPS.Config)
local Hitbox = require(FPS.Hitbox)
local Ballistics = require(FPS.Ballistics)
local Penetration = require(FPS.Penetration)
local TracerFX = require(FPS.TracerFX)

local BulletFX = {}

local MIN_VISIBLE = 6      -- studs from the muzzle before a streak shows (same rule as the hitscan tracer)
local MUZZLE_BLEND = 0.07  -- seconds over which your own tracer slides from the gun barrel onto the true (camera) path
local MAX_STREAK = 120     -- longest streak, studs
local MAX_ACTIVE = 160     -- visual bullets alive at once; the oldest are dropped first

local active = {}
local conn
local hooks = { Impact = function(b, pos, normal) if b.OnImpact then b.OnImpact(pos, normal) end end }

local function finish(b)
	if b.H then
		TracerFX.Finish(b.H)
		b.H = nil
	end
end

-- returns true when the bullet is done
local function step(b, now)
	local t = now - b.T0
	if t < 0 then return false end
	if t > b.Life then
		finish(b)
		return true
	end

	local pos = Ballistics.Pos(b.Origin, b.Vel, b.G, b.K, t)
	local seg = pos - b.Prev
	local segLen = seg.Magnitude
	if segLen < 0.01 then return false end
	local dir = seg / segLen
	b.Len = math.min(segLen * 1.05, MAX_STREAK)

	-- same walls / bodies the server bullet goes through (b.Pen carries the Power it has left); the streak ends where the bullet really stops
	local head, stopped = Penetration.Trace(b.Prev, seg, b.Ignore, b.Pen, hooks, b)

	-- the streak is drawn once the bullet is a few studs out; yours slides from the barrel onto the true path
	if (head - b.Origin).Magnitude >= MIN_VISIBLE then
		if not b.H then b.H = TracerFX.Begin(b.Style, b.Len) end
		local shown = head
		if b.Off then shown = head + b.Off * math.clamp(1 - t / MUZZLE_BLEND, 0, 1) end
		TracerFX.Place(b.H, shown, dir, b.Len)
	end

	if stopped then
		finish(b)
		return true
	end
	b.Prev = pos
	if (pos - b.Origin).Magnitude > b.Range then
		finish(b)
		return true
	end
	return false
end

local function onFrame()
	local now = workspace:GetServerTimeNow()
	for i = #active, 1, -1 do
		if step(active[i], now) then
			active[i] = active[#active]
			active[#active] = nil
		end
	end
	if #active == 0 and conn then
		conn:Disconnect()
		conn = nil
	end
end

function BulletFX.Spawn(o)
	local limit = Config.Ballistics.TracerMax
	for i, v in o.Vels do
		if i > limit then break end
		if #active >= MAX_ACTIVE then
			local old = table.remove(active, 1)
			finish(old)
		end
		table.insert(active, {
			Origin = o.Origin, Prev = o.Origin, Vel = v, G = o.G, K = o.K, T0 = o.T0, Range = o.Range,
			Life = Config.Ballistics.MaxLifetime, Style = o.Style, Ignore = table.clone(o.Ignore), OnImpact = o.OnImpact,
			Pen = Penetration.New(o.Pen or 0), -- own ignore list + state per pellet: Trace adds the bodies / walls it passes to them
			Off = o.Muzzle and (o.Muzzle - o.Origin) or nil, Len = 0,
		})
	end
	if not conn and #active > 0 then conn = RunService.RenderStepped:Connect(onFrame) end
end

function BulletFX.Clear()
	for _, b in active do
		if b.H then TracerFX.Destroy(b.H) end
	end
	table.clear(active)
	if conn then
		conn:Disconnect()
		conn = nil
	end
end

return BulletFX
