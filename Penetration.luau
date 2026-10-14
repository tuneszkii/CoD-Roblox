-- Penetration: bullets punch through thin walls (wallbangs) and through bodies (collateral).
--
-- Shared on purpose: the server resolves damage with it (BulletService for ballistic bullets, FPSServer for hitscan) and the clients
-- draw tracers + bullet holes with the SAME maths (BulletFX, WeaponController), so a wallbang is drawn exactly where it happens.
--
-- Model (all numbers live in Config.Penetration):
--   * A bullet carries Power, measured in "studs of concrete" it can still punch through (class default, scaled by the weapon's
--     `PenPower` / the attachment mod `PenMult`, see Penetration.PowerOf).
--   * WALL: when a bullet hits a solid part, the thickness along its flight direction is measured (a ray cast back from the far side
--     of the part finds the exit face). The wall costs  thickness * resistance(material).  Not enough Power left (or thicker than the
--     bullet could ever cross, or a NoPen part) -> the bullet stops. Otherwise it exits on the other side, loses that Power, and its
--     damage is multiplied by  max(MinWallMult, 1 - cost / startPower)  for everything it hits afterwards.
--   * BODY: a bullet that hits a character keeps flying (up to MaxBodies) for BodyCost Power and BodyDamage x damage per body.
--     Corpses cost nothing. Because every body the bullet touches gets its own damage roll from the same trigger pull (same shot id),
--     killing two players with one bullet already pays out the Collateral medal.
--   * Mappers: a part Attribute  NoPen = true  (on the part or any ancestor) makes it bullet proof,  PenResist = number  overrides the
--     material resistance (0 = free pass, e.g. a window with no glass).
--
-- Penetration.Trace is one straight segment; the caller keeps the state (Penetration.New) + the ignore list between segments, so a
-- bullet that flies over many frames carries its remaining Power and damage multiplier with it. The bullet path itself (Ballistics.luau)
-- is NOT bent or slowed by what it passes through: the loss is all in damage and Power, which keeps the client tracers in sync.
local Config = require(script.Parent.Config)
local Hitbox = require(script.Parent.Hitbox)

local P = Config.Penetration
local EPS = 0.02 -- studs: start the next ray this far past an exit face so it cannot re-hit the surface it just left

local Penetration = {}

-- Starting Power of a weapon's bullets (0 = this weapon never penetrates).
function Penetration.PowerOf(cfg)
	if not P.Enabled or cfg.NoPen then return 0 end
	return (cfg.PenPower or P.Classes[cfg.Class] or 0) * (cfg.PenMult or 1)
end

-- Fresh state for ONE bullet (one pellet = one state).
--   Power = what is left, Max = what it started with, Bodies / Walls = crossed so far, Mult = damage multiplier from the walls / bodies crossed
function Penetration.New(power)
	return { Power = power, Max = power, Bodies = 0, Walls = 0, Mult = 1 }
end

-- ---------------------------------------------------------------- surfaces
local function resistOf(part)
	local r = part:GetAttribute("PenResist")
	if type(r) == "number" then return math.max(r, 0) end
	if part.Transparency >= 1 and not part.CanCollide then return 0 end -- invisible helper geometry offers no resistance
	return P.Materials[part.Material] or P.Default
end

local function blocked(part)
	local inst = part
	while inst and inst ~= workspace do
		if inst:GetAttribute("NoPen") == true then return true end
		inst = inst.Parent
	end
	return false
end

-- Can the bullet get through the part it just hit? Returns exitPos (just past the far face), exitNormal, cost  - or nil when it is stopped.
local function crossWall(st, res, dir)
	if st.Walls >= P.MaxWalls or st.Power <= 0 then return nil end
	local part = res.Instance
	if not part:IsA("BasePart") or part == workspace.Terrain or blocked(part) then return nil end
	if not P.Floors and math.abs(res.Normal.Y) > P.FloorNormal then return nil end -- floors / ceilings / tops of crates stay solid

	local resist = resistOf(part)
	if resist <= 0 then return res.Position + dir * EPS, res.Normal, 0 end

	-- thickness: cast from beyond the furthest point this bullet could reach back towards the hit, against this one part only.
	-- A ray that starts outside a part hits its far (exit) face first; if the far point is still inside the part the ray finds nothing,
	-- which means "thicker than this bullet can punch".
	local span = math.min(st.Power / resist, P.MaxThickness) + EPS
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Include
	rp.FilterDescendantsInstances = { part }
	local back = workspace:Raycast(res.Position + dir * span, -dir * span, rp)
	if not back then return nil end
	local cost = math.max((back.Position - res.Position):Dot(dir), 0) * resist
	if cost > st.Power then return nil end
	return back.Position + dir * EPS, back.Normal, cost
end

-- The bullet hit a living body: does it keep going? (also spends the Power / damage for the body)
local function crossBody(st)
	st.Bodies += 1
	if st.Bodies >= P.MaxBodies or st.Power < P.BodyCost then return false end
	st.Power -= P.BodyCost
	st.Mult *= P.BodyDamage
	return true
end

-- ---------------------------------------------------------------- trace
-- Flies one straight segment (origin, vec = direction * length) through the world and the pose-aware bodies.
--   ignore  = { instances }  the shooter's character etc. This table is MUTATED: bodies / walls the bullet has passed are added, so use a
--             separate table per bullet and keep it for the bullet's whole flight.
--   st      = Penetration.New(power)
--   hooks   = optional { Body = function(ud, res, st), Impact = function(ud, pos, normal) }
--             Body   : a living body was struck (apply damage here: use st.Mult, st.Walls). Called BEFORE the body's own cost is applied.
--             Impact : a bullet hole belongs here (wall entry, wall exit, final stop). Visuals only.
-- Returns  endPos, stopped   (stopped = the bullet ended on something; false = it flew the whole segment)
function Penetration.Trace(origin, vec, ignore, st, hooks, ud)
	local len = vec.Magnitude
	if len < 1e-3 then return origin, false end
	st = st or Penetration.New(0)
	local dir = vec / len
	local pos, left = origin, len
	local Body, Impact = hooks and hooks.Body, hooks and hooks.Impact

	for _ = 1, P.MaxHits do
		local res = Hitbox.Raycast(pos, dir * left, ignore)
		if not res then break end
		local hitPos = res.Position
		local model = res.Instance:FindFirstAncestorOfClass("Model")
		local hum = model and model:FindFirstChildOfClass("Humanoid")

		if hum then
			table.insert(ignore, model) -- a body is only ever hit once per bullet
			if hum.Health > 0 then
				if Body then Body(ud, res, st) end
				if not crossBody(st) then
					if Impact then Impact(ud, hitPos, res.Normal) end
					return hitPos, true
				end
			end -- (a corpse is just walked through)
			left -= (hitPos - pos):Dot(dir)
			pos = hitPos
		else
			local exitPos, exitNormal, cost = crossWall(st, res, dir)
			if not exitPos then
				if Impact then Impact(ud, hitPos, res.Normal) end
				return hitPos, true
			end
			table.insert(ignore, res.Instance) -- through this part for good (also stops concave parts counting twice)
			if cost > 0 then
				st.Power -= cost
				st.Walls += 1
				st.Mult *= math.max(P.MinWallMult, 1 - cost / st.Max)
				if Impact then
					Impact(ud, hitPos, res.Normal)
					Impact(ud, exitPos, exitNormal)
				end
			end
			left -= (exitPos - pos):Dot(dir)
			pos = exitPos
		end
		if left <= 0.01 then return pos, false end -- the segment ended inside / right behind what it just crossed
	end
	return origin + dir * len, false
end

return Penetration
