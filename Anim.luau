-- Shared animation data for first-person viewmodel AND third-person rigs.
--  * Gun-space keyframes (reload / bolt / pump / shells): hand positions relative to the weapon's Body.
--  * Chest-space tracks (equipment / plates / melee swings): CFrames in units of arm reach, origin at the chest.
local Anim = {}
local rad = math.rad

local function sm(a, b, x)
	if b <= a then return 1 end
	local t = math.clamp((x - a) / (b - a), 0, 1)
	return t * t * (3 - 2 * t)
end
Anim.Sm = sm

-- ------------------------------------------------------------------ gun-space keys
-- key = { t, leftPos|nil, rightPos|nil, state }  (nil hand = stays on its grip). state: seated | carry | hidden
function Anim.SampleKeys(keys, f, gl, gr)
	local n = #keys
	local first = keys[1]
	if f <= first[1] then return first[2] or gl, first[3] or gr, first[4] end
	for i = 1, n - 1 do
		local a, b = keys[i], keys[i + 1]
		if f <= b[1] then
			local x = sm(a[1], b[1], f)
			return (a[2] or gl):Lerp(b[2] or gl, x), (a[3] or gr):Lerp(b[3] or gr, x), a[4]
		end
	end
	local last = keys[n]
	return last[2] or gl, last[3] or gr, last[4]
end

function Anim.SampleScalar(keys, f)
	for i = 1, #keys - 1 do
		local a, b = keys[i], keys[i + 1]
		if f <= b[1] then return a[2] + (b[2] - a[2]) * sm(a[1], b[1], f) end
	end
	return keys[#keys][2]
end

-- Fraction of the reload at which ammo is counted in
Anim.InsertFrac = { Mag = { Tactical = 0.8, Empty = 0.55 }, Cylinder = { Tactical = 0.62, Empty = 0.62 }, Rocket = { Tactical = 0.78, Empty = 0.78 } }

function Anim.InsertAt(style, empty)
	local s = Anim.InsertFrac[style] or Anim.InsertFrac.Mag
	return empty and s.Empty or s.Tactical
end

local function sorted(keys)
	table.sort(keys, function(a, b) return a[1] < b[1] end)
	return keys
end

-- Timed reload for Mag / Cylinder / Rocket styles. Returns { Keys, Pose }
function Anim.Reload(G, style, empty)
	local grip = G.LeftGripRel and G.LeftGripRel.Position or G.RightGripRel.Position
	local V = Vector3.new
	if style == "Rocket" then
		local M = G.MagRel and G.MagRel.Position or (grip + V(0, 0, -1.2))
		local pouch = G.RightGripRel.Position + V(-0.45, -0.9, 0.9)
		return { Keys = {
			{ 0, grip, nil, "hidden" }, { 0.2, pouch, nil, "hidden" }, { 0.35, pouch, nil, "carry" },
			{ 0.6, M + V(0, 0.3, -0.9), nil, "carry" }, { 0.8, M, nil, "seated" }, { 0.9, M, nil, "seated" }, { 1, grip, nil, "seated" },
		}, Pose = { { 0, 0 }, { 0.2, 1 }, { 0.85, 1 }, { 1, 0 } } }
	end
	local M
	if style == "Cylinder" then
		M = G.RightGripRel.Position + V(-0.28, 0.42, -0.5)
	else
		M = G.MagRel and G.MagRel.Position or (grip + V(0, -0.4, 0.8))
	end
	local mk = style == "Mag" and "carry" or "seated" -- only real magazines travel with the hand
	local s = empty and 0.68 or 1
	local keys = {
		{ 0, grip, nil, "seated" },
		{ 0.14 * s, M, nil, mk },
		{ 0.30 * s, M + V(0, -0.8, 0.1), nil, mk },
		{ 0.38 * s, M + V(0, -1.5, 0.5), nil, style == "Mag" and "hidden" or "seated" },
		{ 0.52 * s, M + V(0, -1.6, 0.6), nil, mk },
		{ 0.70 * s, M + V(0, -0.8, 0.1), nil, mk },
		{ 0.80 * s, M + V(0, -0.05, 0), nil, "seated" },
		{ 0.86 * s, M + V(0, -0.3, 0), nil, "seated" },
		{ 0.93 * s, grip, nil, "seated" },
	}
	if empty then
		local C = G.EjectRel.Position + V(0, 0.12, 0)
		table.insert(keys, { 0.72, C, nil, "seated" })
		table.insert(keys, { 0.82, C + V(0, 0, 0.5), nil, "seated" })
		table.insert(keys, { 0.90, C, nil, "seated" })
	end
	table.insert(keys, { 1.0, grip, nil, "seated" })
	local pose = empty and { { 0, 0 }, { 0.1, 1 }, { 0.56, 1 }, { 0.66, 0 }, { 1, 0 } } or { { 0, 0 }, { 0.14, 1 }, { 0.86, 1 }, { 1, 0 } }
	return { Keys = sorted(keys), Pose = pose }
end

-- Cycling action between shots: "Bolt" (right hand works the bolt) or "Pump" (left hand slides the forend)
function Anim.Cycle(G, kind)
	local V = Vector3.new
	if kind == "Bolt" then
		local B = G.Movers and G.Movers.Bolt and G.Movers.Bolt.Rel.Position or (G.RightGripRel.Position + V(0.15, 0.4, -0.1))
		local up = V(0.12, 0.28, 0)
		return { Keys = {
			{ 0, nil, nil, "seated" }, { 0.15, nil, B, "carry" }, { 0.3, nil, B + up, "carry" }, { 0.55, nil, B + up + V(0, 0, 0.8), "carry" },
			{ 0.78, nil, B + up, "carry" }, { 0.88, nil, B, "seated" }, { 1, nil, nil, "seated" },
		}, Pose = { { 0, 0 }, { 1, 0 } } }
	end
	local grip = G.LeftGripRel and G.LeftGripRel.Position or G.RightGripRel.Position
	return { Keys = {
		{ 0, nil, nil, "seated" }, { 0.12, grip, nil, "seated" }, { 0.4, grip + V(0, 0, 0.7), nil, "seated" },
		{ 0.75, grip, nil, "seated" }, { 1, nil, nil, "seated" },
	}, Pose = { { 0, 0 }, { 1, 0 } } }
end

-- Tube-fed shotgun reload (start / one shell / end)
function Anim.Shell(G, stage)
	local grip = G.LeftGripRel and G.LeftGripRel.Position or G.RightGripRel.Position
	local port = G.RightGripRel.Position + Vector3.new(0, 0.15, -0.4)
	if stage == "Start" then
		return { Keys = { { 0, grip, nil, "seated" }, { 0.5, port, nil, "seated" }, { 1, port, nil, "seated" } }, Pose = { { 0, 0 }, { 1, 1 } } }
	elseif stage == "Load" then
		return { Keys = { { 0, port, nil, "seated" }, { 0.35, port + Vector3.new(0, -1.1, 0.3), nil, "seated" },
			{ 0.7, port + Vector3.new(0, -0.1, 0), nil, "seated" }, { 1, port, nil, "seated" } }, Pose = { { 0, 1 }, { 1, 1 } } }
	end
	return { Keys = { { 0, port, nil, "seated" }, { 1, grip, nil, "seated" } }, Pose = { { 0, 1 }, { 1, 0 } } }
end

-- ------------------------------------------------------------------ chest-space tracks
local function C(x, y, z, rx, ry, rz)
	return CFrame.new(x, y, z) * CFrame.Angles(rad(rx or 0), rad(ry or 0), rad(rz or 0))
end
local ID = CFrame.identity
local Rlow, Llow = C(0.22, -0.38, -0.36), C(-0.22, -0.40, -0.34)
local Rhold, Lhold = C(0.26, 0.02, -0.44), C(-0.30, -0.34, -0.26)

-- key: t, R, L, Drop (gun lowered 0..1), W (hand override weight 0..1), G (extra gun offset)
local function K(t, R, L, Drop, W, G) return { t = t, R = R or Rlow, L = L or Llow, Drop = Drop or 0, W = W or 0, G = G or ID } end

Anim.Tracks = {
	Pull = { K(0, Rlow, Llow, 0, 0), K(0.35, C(0.22, 0, -0.50), C(-0.05, -0.02, -0.46), 1, 1),
		K(0.65, C(0.24, 0.02, -0.48), C(-0.32, -0.06, -0.30), 1, 1), K(1, Rhold, Lhold, 1, 1) },
	Hold = { K(0, Rhold, Lhold, 1, 1), K(1, Rhold, Lhold, 1, 1) },
	Throw = { K(0, Rhold, Lhold, 1, 1), K(0.30, C(0.40, 0.14, -0.14, -30), Lhold, 1, 1), K(0.55, C(0.18, 0.10, -0.85, 20), Lhold, 1, 1),
		K(0.75, C(0.14, -0.10, -0.70), Llow, 0.6, 0.6), K(1, Rlow, Llow, 0, 0) },
	Use = { K(0, Rlow, Llow, 0, 0), K(0.25, C(0.2, 0, -0.48), Llow, 1, 1), K(0.5, C(0.16, -0.30, -0.28), Llow, 1, 1),
		K(0.7, C(0.16, -0.30, -0.28), Llow, 1, 1), K(0.9, C(0.2, -0.05, -0.45), Llow, 0.5, 0.5), K(1, Rlow, Llow, 0, 0) },
	Sensor = { K(0, Rlow, Llow, 0, 0), K(0.3, C(0.2, 0.03, -0.5), Llow, 1, 1), K(0.75, C(0.14, 0.08, -0.55, 15), Llow, 1, 1), K(1, Rlow, Llow, 0, 0) },
	Plant = { K(0, Rlow, Llow, 0, 0), K(0.3, C(0.16, -0.55, -0.5), C(-0.16, -0.55, -0.5), 1, 1),
		K(0.7, C(0.16, -0.55, -0.5), C(-0.16, -0.55, -0.5), 1, 1), K(1, Rlow, Llow, 0, 0) },
	Plate = { K(0, Rlow, Llow, 0, 0), K(0.1, C(0.15, 0, -0.5), C(-0.15, 0, -0.5), 1, 1), K(0.2, C(0.12, -0.12, -0.40), C(-0.12, -0.12, -0.40), 1, 1),
		K(0.32, C(0.12, -0.2, -0.36), C(-0.12, -0.2, -0.36), 1, 1), K(0.44, C(0.12, -0.12, -0.40), C(-0.12, -0.12, -0.40), 1, 1),
		K(0.56, C(0.12, -0.2, -0.36), C(-0.12, -0.2, -0.36), 1, 1), K(0.68, C(0.12, -0.12, -0.40), C(-0.12, -0.12, -0.40), 1, 1),
		K(0.8, C(0.12, -0.2, -0.36), C(-0.12, -0.2, -0.36), 1, 1), K(0.92, C(0.15, -0.1, -0.45), C(-0.15, -0.1, -0.45), 0.6, 0.6), K(1, Rlow, Llow, 0, 0) },
	Bash = { K(0, nil, nil, 0, 0, ID), K(0.3, nil, nil, 0, 0, C(0.08, 0.12, 0.30, 12, -18)), K(0.55, nil, nil, 0, 0, C(-0.04, -0.04, -0.34, -8, 12)),
		K(1, nil, nil, 0, 0, ID) },
	SwingR = { K(0, nil, nil, 0, 0, ID), K(0.28, nil, nil, 0, 0, C(-0.30, 0.10, 0.14, 8, 35, -40)),
		K(0.55, nil, nil, 0, 0, C(0.34, -0.14, -0.28, -8, -55, 50)), K(1, nil, nil, 0, 0, ID) },
	SwingL = { K(0, nil, nil, 0, 0, ID), K(0.28, nil, nil, 0, 0, C(0.34, 0.10, 0.14, 8, -35, 40)),
		K(0.55, nil, nil, 0, 0, C(-0.34, -0.14, -0.28, -8, 55, -50)), K(1, nil, nil, 0, 0, ID) },
	Lunge = { K(0, nil, nil, 0, 0, ID), K(0.35, nil, nil, 0, 0, C(0.10, 0.02, 0.30)), K(0.6, nil, nil, 0, 0, C(0, 0, -0.55)),
		K(1, nil, nil, 0, 0, ID) },
	Smash = { K(0, nil, nil, 0, 0, ID), K(0.45, nil, nil, 0, 0, C(0.1, 0.45, 0.1, 60)), K(0.65, nil, nil, 0, 0, C(0, -0.25, -0.45, -50)),
		K(1, nil, nil, 0, 0, ID) },
}
Anim.LeftRest = Llow -- resting left hand for one-handed weapons

-- Sample a chest-space track at normalized time f. Returns R, L, G, Drop, W (positions still in reach units)
function Anim.SampleTrack(name, f)
	local keys = Anim.Tracks[name]
	if not keys then return Rlow, Llow, ID, 0, 0 end
	local n = #keys
	if f <= keys[1].t then local k = keys[1]; return k.R, k.L, k.G, k.Drop, k.W end
	for i = 1, n - 1 do
		local a, b = keys[i], keys[i + 1]
		if f <= b.t then
			local x = sm(a.t, b.t, f)
			return a.R:Lerp(b.R, x), a.L:Lerp(b.L, x), a.G:Lerp(b.G, x), a.Drop + (b.Drop - a.Drop) * x, a.W + (b.W - a.W) * x
		end
	end
	local k = keys[n]
	return k.R, k.L, k.G, k.Drop, k.W
end

function Anim.Scale(cf, k)
	return CFrame.new(cf.Position * k) * cf.Rotation
end

return Anim
