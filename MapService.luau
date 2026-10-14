-- MapService: loads the voted map into Workspace and answers "where should this player spawn".
-- Your own map: put a Model named like the map id (see Modes.Maps) in ServerStorage > Maps, with a Folder "Spawns" containing parts
-- (any BasePart, make it transparent / non-colliding) that have a string Attribute  Team = "Alpha" | "Bravo" | "Any".  Facing = the part's LookVector.
-- With no model there, an arena is built from code so the game is playable immediately.
-- Objective modes (Domination / Hardpoint): add a Folder "Objectives" to the model with parts that have these Attributes:
--     Kind = "Flag",  Label = "A" | "B" | "C"     (Domination flag, zone radius = Radius attribute, else half of the part's X size, else 9)
--     Kind = "Hill",  Order = 1, 2, 3 ...        (Hardpoint hill, played in Order, radius like above, else 15)
--   The part's bottom face is the ground point of the zone. With no Objectives folder, positions are derived from the team spawns.
local ServerStorage = game:GetService("ServerStorage")
local RS = game:GetService("ReplicatedStorage")
local Modes = require(RS:WaitForChild("FPS"):WaitForChild("Modes"))

local Maps = {}
local ORIGIN = Vector3.new(0, 400, 0) -- generated arenas live high up so they never clash with whatever else is in the place
local current

local function block(parent, name, size, cf, color, material)
	local p = Instance.new("Part")
	p.Name, p.Anchored, p.Size, p.CFrame = name, true, size, cf
	p.Color, p.Material = color, material or Enum.Material.Concrete
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function spawnPart(folder, team, pos, lookAt)
	local p = Instance.new("Part")
	p.Name, p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.Transparency = "Spawn", true, false, false, false, 1
	p.Size = Vector3.new(4, 1, 4)
	p.CFrame = CFrame.lookAt(pos, Vector3.new(lookAt.X, pos.Y, lookAt.Z))
	p:SetAttribute("Team", team)
	p.Parent = folder
end

-- objective positions of a generated arena, as x / z offsets from ORIGIN. Alpha spawns at -z, Bravo at +z.
local function layout(def)
	local W, L = def.Size[1], def.Size[2]
	local hr = math.clamp(math.min(W, L) * 0.14, 12, 18)
	return {
		Flags = {
			{ Id = "A", X = -W * 0.22, Z = -L * 0.27, R = 9 },
			{ Id = "B", X = 0, Z = 0, R = 9 },
			{ Id = "C", X = W * 0.22, Z = L * 0.27, R = 9 },
		},
		Hills = { -- played in this order: centre, Alpha side, Bravo side, then the two far flanks
			{ X = 0, Z = 0, R = hr },
			{ X = -W * 0.24, Z = -L * 0.2, R = hr },
			{ X = W * 0.24, Z = L * 0.2, R = hr },
			{ X = W * 0.24, Z = -L * 0.2, R = hr },
			{ X = -W * 0.24, Z = L * 0.2, R = hr },
		},
	}
end

local function generate(def)
	local model = Instance.new("Model")
	model.Name = def.Id
	local W, L = def.Size[1], def.Size[2]
	local rng = Random.new(def.Seed)
	block(model, "Floor", Vector3.new(W, 2, L), CFrame.new(ORIGIN - Vector3.new(0, 1, 0)), def.Floor, Enum.Material.Slate)
	local H, T = 26, 2
	block(model, "WallN", Vector3.new(W + T * 2, H, T), CFrame.new(ORIGIN + Vector3.new(0, H / 2, -L / 2 - T / 2)), def.Wall, Enum.Material.Concrete)
	block(model, "WallS", Vector3.new(W + T * 2, H, T), CFrame.new(ORIGIN + Vector3.new(0, H / 2, L / 2 + T / 2)), def.Wall, Enum.Material.Concrete)
	block(model, "WallW", Vector3.new(T, H, L), CFrame.new(ORIGIN + Vector3.new(-W / 2 - T / 2, H / 2, 0)), def.Wall, Enum.Material.Concrete)
	block(model, "WallE", Vector3.new(T, H, L), CFrame.new(ORIGIN + Vector3.new(W / 2 + T / 2, H / 2, 0)), def.Wall, Enum.Material.Concrete)

	for _, nm in { "Floor", "WallN", "WallS", "WallW", "WallE" } do model[nm]:SetAttribute("NoPen", true) end -- the arena shell is bullet proof (Config.Penetration)

	-- cover: random boxes kept out of the spawn zones at both ends
	local zone = 34
	local lay = layout(def)
	for i = 1, def.Cover do
		local sx, sy, sz = rng:NextNumber(5, 16), rng:NextNumber(4, 10), rng:NextNumber(4, 12)
		if rng:NextNumber() < 0.2 then sx, sy, sz = rng:NextNumber(3, 5), rng:NextNumber(12, 18), rng:NextNumber(3, 5) end -- pillars
		local x = rng:NextNumber(-W / 2 + 10, W / 2 - 10)
		local z = rng:NextNumber(-L / 2 + zone, L / 2 - zone)
		local yaw = math.rad(rng:NextInteger(0, 3) * 90 + rng:NextInteger(-10, 10))
		local keep = true
		for _, f in lay.Flags do -- keep the flag poles out of the crates (hills may contain cover)
			if math.sqrt((x - f.X) ^ 2 + (z - f.Z) ^ 2) < f.R * 0.6 + math.max(sx, sz) * 0.75 + 2 then keep = false end
		end
		if keep then
			block(model, "Cover" .. i, Vector3.new(sx, sy, sz), CFrame.new(ORIGIN + Vector3.new(x, sy / 2, z)) * CFrame.Angles(0, yaw, 0),
				def.CoverColor, Enum.Material.Metal)
		end
	end

	-- ladder test: a raised platform with a ladder (a Part tagged "Ladder", see Config.Movement.Ladder) on its south face, in the arena's far corner
	do
		local ph = 9
		local px, pz = W / 2 - 14, -L / 2 + zone + 8
		local plat = block(model, "LadderPlatform", Vector3.new(12, 1, 12), CFrame.new(ORIGIN + Vector3.new(px, ph - 0.5, pz)), def.CoverColor, Enum.Material.Metal)
		block(model, "LadderPlatformBase", Vector3.new(12, ph - 1, 12), CFrame.new(ORIGIN + Vector3.new(px, (ph - 1) / 2, pz)), def.Wall, Enum.Material.Concrete)
		plat.Name = "LadderPlatform"
		local lad = block(model, "Ladder", Vector3.new(3, ph, 0.4), CFrame.new(ORIGIN + Vector3.new(px, ph / 2, pz + 6.2)), Color3.fromRGB(190, 150, 60), Enum.Material.Metal)
		lad.CanCollide = false
		lad:SetAttribute("NoPen", true)
		lad:AddTag("Ladder")
	end

	local spawns = Instance.new("Folder")
	spawns.Name = "Spawns"
	spawns.Parent = model
	local center = ORIGIN
	for i = 1, 6 do
		local x = -W / 2 + 10 + (W - 20) * (i - 1) / 5
		spawnPart(spawns, "Alpha", ORIGIN + Vector3.new(x, 3, -L / 2 + 12), center)
		spawnPart(spawns, "Bravo", ORIGIN + Vector3.new(x, 3, L / 2 - 12), center)
	end
	for i = 1, 12 do -- free-for-all: scattered all over the arena
		local x, z = rng:NextNumber(-W / 2 + 10, W / 2 - 10), rng:NextNumber(-L / 2 + 10, L / 2 - 10)
		spawnPart(spawns, "Any", ORIGIN + Vector3.new(x, 3, z), center)
	end

	-- thin partition walls (wood / brick, about 1 stud): something to shoot through (Config.Penetration). They use their own Random, so the
	-- cover + spawn layout of a seed never changes, and are kept clear of spawn points, flags, hills and cover.
	local prng = Random.new(def.Seed + 101)
	local placed, tries = 0, 0
	while placed < 6 and tries < 80 do
		tries += 1
		local len, th, hgt = prng:NextNumber(12, 22), prng:NextNumber(0.8, 1.2), 9
		local x, z = prng:NextNumber(-W / 2 + 14, W / 2 - 14), prng:NextNumber(-L / 2 + zone, L / 2 - zone)
		local cf = CFrame.new(ORIGIN + Vector3.new(x, hgt / 2, z)) * CFrame.Angles(0, math.rad(prng:NextInteger(0, 1) * 90 + prng:NextInteger(-8, 8)), 0)
		local ok = true
		for _, f in lay.Flags do
			if math.sqrt((x - f.X) ^ 2 + (z - f.Z) ^ 2) < f.R + len / 2 + 2 then ok = false end
		end
		for _, h in lay.Hills do
			if math.sqrt((x - h.X) ^ 2 + (z - h.Z) ^ 2) < h.R + len / 2 + 2 then ok = false end
		end
		for _, o in model:GetChildren() do -- cover boxes + earlier partitions
			if o:IsA("BasePart") and (o.Name:find("^Cover") or o.Name:find("^Partition"))
				and (o.Position - cf.Position).Magnitude < o.Size.Magnitude / 2 + len / 2 + 1.5 then ok = false end
		end
		for _, sp in spawns:GetChildren() do
			local lp = cf:PointToObjectSpace(sp.Position)
			if math.abs(lp.X) < len / 2 + 3 and math.abs(lp.Z) < th / 2 + 3 then ok = false end
		end
		if ok then
			placed += 1
			block(model, "Partition" .. placed, Vector3.new(len, hgt, th), cf, def.Wall,
				prng:NextNumber() < 0.5 and Enum.Material.WoodPlanks or Enum.Material.Brick)
		end
	end
	return model
end

-- ---------------------------------------------------------------- objectives
local function ground(model, pos)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { model }
	local hit = workspace:Raycast(pos + Vector3.new(0, 10, 0), Vector3.new(0, -60, 0), params)
	return hit and Vector3.new(pos.X, hit.Position.Y, pos.Z) or pos
end

local function zoneRadius(part, default)
	local r = part:GetAttribute("Radius")
	if type(r) == "number" and r > 1 then return r end
	return math.max(default, 0)
end

-- no Objectives folder: spread flags and hills between the Alpha and Bravo spawn areas
local function derive(model, lists, fallbackCenter)
	local function centroid(list)
		if #list == 0 then return nil end
		local sum = Vector3.zero
		for _, cf in list do sum += cf.Position end
		return sum / #list
	end
	local a, b = centroid(lists.Alpha), centroid(lists.Bravo)
	if not a or not b or (a - b).Magnitude < 20 then
		local cf, size = model:GetBoundingBox()
		local half = Vector3.new(0, 0, size.Z * 0.35)
		a, b = fallbackCenter - half, fallbackCenter + half
	end
	local dir = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
	local along = dir.Magnitude > 0.1 and dir.Unit or Vector3.new(0, 0, 1)
	local side = Vector3.new(-along.Z, 0, along.X)
	local spread = dir.Magnitude * 0.22
	local function at(t, s) return ground(model, a + dir * t + side * (s * spread)) end
	return {
		Flags = {
			{ Id = "A", Pos = at(0.3, -1), Radius = 9 },
			{ Id = "B", Pos = at(0.5, 0), Radius = 9 },
			{ Id = "C", Pos = at(0.7, 1), Radius = 9 },
		},
		Hills = {
			{ Pos = at(0.5, 0), Radius = 15 }, { Pos = at(0.3, 1), Radius = 15 }, { Pos = at(0.7, -1), Radius = 15 },
			{ Pos = at(0.3, -1), Radius = 15 }, { Pos = at(0.7, 1), Radius = 15 },
		},
	}
end

local function readObjectives(model, def, generated, lists, center)
	if generated then
		local lay = layout(def)
		local out = { Flags = {}, Hills = {} }
		for _, f in lay.Flags do table.insert(out.Flags, { Id = f.Id, Pos = ORIGIN + Vector3.new(f.X, 0, f.Z), Radius = f.R }) end
		for _, h in lay.Hills do table.insert(out.Hills, { Pos = ORIGIN + Vector3.new(h.X, 0, h.Z), Radius = h.R }) end
		return out
	end
	local folder = model:FindFirstChild("Objectives")
	local out = { Flags = {}, Hills = {} }
	if folder then
		local hills = {}
		for _, p in folder:GetChildren() do
			if p:IsA("BasePart") then
				local pos = p.Position - Vector3.new(0, p.Size.Y / 2, 0)
				local kind = p:GetAttribute("Kind")
				if kind == "Flag" then
					local label = tostring(p:GetAttribute("Label") or string.char(64 + #out.Flags + 1))
					table.insert(out.Flags, { Id = label, Pos = pos, Radius = zoneRadius(p, p.Size.X / 2 > 1 and p.Size.X / 2 or 9) })
				elseif kind == "Hill" then
					table.insert(hills, { Order = tonumber(p:GetAttribute("Order")) or #hills + 1, Pos = pos, Radius = zoneRadius(p, p.Size.X / 2 > 1 and p.Size.X / 2 or 15) })
				end
			end
		end
		table.sort(out.Flags, function(x, y) return x.Id < y.Id end)
		table.sort(hills, function(x, y) return x.Order < y.Order end)
		out.Hills = hills
	end
	local fallback = derive(model, lists, center)
	if #out.Flags == 0 then out.Flags = fallback.Flags end
	if #out.Hills == 0 then out.Hills = fallback.Hills end
	return out
end

function Maps.Load(id)
	Maps.Unload()
	local def = Modes.GetMap(id)
	local source = ServerStorage:FindFirstChild("Maps") and ServerStorage.Maps:FindFirstChild(id)
	local generated = source == nil
	local model = source and source:Clone() or generate(def)
	model.Parent = workspace
	local lists = { Alpha = {}, Bravo = {}, Any = {} }
	local spawns = model:FindFirstChild("Spawns")
	local sum, n = Vector3.zero, 0
	if spawns then
		for _, p in spawns:GetChildren() do
			if p:IsA("BasePart") then
				local team = p:GetAttribute("Team")
				table.insert(lists[lists[team] and team or "Any"], p.CFrame)
				sum += p.Position
				n += 1
			end
		end
	end
	if n == 0 then warn("[MapService] map '" .. id .. "' has no Spawns folder with parts; using the origin") table.insert(lists.Any, CFrame.new(ORIGIN + Vector3.new(0, 5, 0))) end
	local center = n > 0 and sum / n or ORIGIN
	current = { Model = model, Spawns = lists, Center = center }
	current.Objectives = readObjectives(model, def, generated, lists, center)
	return current
end

function Maps.Unload()
	if current and current.Model then current.Model:Destroy() end
	current = nil
end

-- { Flags = { { Id, Pos, Radius } ... }, Hills = { { Pos, Radius } ... } } of the loaded map
function Maps.Objectives()
	return current and current.Objectives or { Flags = {}, Hills = {} }
end

-- where the map is and how big it is (for the match intro flyover): { Center = Vector3, Size = Vector3 }
function Maps.Info()
	if not current then return { Center = ORIGIN, Size = Vector3.new(120, 30, 160) } end
	local cf, size = current.Model:GetBoundingBox()
	return { Center = cf.Position, Size = size }
end

-- team = "Alpha" | "Bravo" | nil (free for all). enemies = list of Vector3 positions. Picks the spawn farthest from any enemy.
function Maps.PickSpawn(team, enemies)
	if not current then return CFrame.new(ORIGIN + Vector3.new(0, 5, 0)) end
	local list = (team and #current.Spawns[team] > 0) and current.Spawns[team] or current.Spawns.Any
	if #list == 0 then list = current.Spawns.Alpha end
	if #list == 0 then list = current.Spawns.Bravo end
	local best, bestScore = list[1], -1
	for _, cf in list do
		local nearest = math.huge
		for _, pos in enemies do nearest = math.min(nearest, (pos - cf.Position).Magnitude) end
		local score = nearest + math.random() * 8 -- a little noise so the same spawn isn't always chosen
		if score > bestScore then best, bestScore = cf, score end
	end
	return best + Vector3.new(0, 3, 0)
end

-- candidate spawns for SpawnService: Primary = this team's spawns (or the free-for-all ones), Fallback = every other spawn of the map
function Maps.SpawnLists(team)
	if not current then return { CFrame.new(ORIGIN + Vector3.new(0, 5, 0)) }, {} end
	local S = current.Spawns
	local primary = (team and #S[team] > 0) and S[team] or S.Any
	if #primary == 0 then primary = #S.Alpha > 0 and S.Alpha or S.Bravo end
	local fallback = {}
	for _, key in { "Alpha", "Bravo", "Any" } do
		if S[key] ~= primary then
			for _, cf in S[key] do table.insert(fallback, cf) end
		end
	end
	return primary, fallback
end

return Maps
