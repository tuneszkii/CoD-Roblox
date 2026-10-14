-- StreakService: kill streak rewards.
-- A class carries three streaks (Armory.Streaks). Consecutive kills without dying earn them: each one becomes READY when your kill count reaches its
-- cost and stays until you use it or die (unused streaks are lost on death, and a new life starts the count again).
-- The client asks to use one with StreakUse(slot, origin, direction); target streaks (airstrike, mortar, chemical) need the aim ray to hit something.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local FPS = RS:WaitForChild("FPS")
local Config = require(FPS:WaitForChild("Config"))
local Armory = require(FPS:WaitForChild("Armory"))
local Hitbox = require(FPS:WaitForChild("Hitbox"))
local Damage = require(script.Parent:WaitForChild("DamageService"))
local Equipment = require(script.Parent:WaitForChild("EquipmentService"))
local RadarService = require(script.Parent:WaitForChild("RadarService"))

local St = {}
local ctx
local Active = {} -- [player] = { Slots = {id, id, id}, Ready = {[slot] = true}, Used = {[slot] = true}, Kills = n }

local TARGETED = { Airstrike = true, Mortar = true, ChemStrike = true }
local MAX_TARGET = 400

-- ---------------------------------------------------------------- state sync
function St.Sync(plr)
	local a = Active[plr]
	if not a then return { Kills = 0, Slots = {} } end
	local slots = {}
	for i = 1, 3 do
		local id = a.Slots[i]
		local def = id and id ~= "" and Armory.Streaks[id]
		if def then
			slots[i] = { Id = id, Kills = def.Kills, State = a.Used[i] and "Used" or (a.Ready[i] and "Ready" or "Locked") }
		else
			slots[i] = { Id = "", Kills = 0, State = "Empty" }
		end
	end
	return { Kills = a.Kills, Slots = slots }
end

local function push(plr)
	ctx.Remotes.StreakSync:FireClient(plr, St.Sync(plr))
end

-- called when a character spawns with a loadout
function St.OnSpawn(plr, loadout)
	Active[plr] = { Slots = loadout.Streaks or {}, Ready = {}, Used = {}, Kills = 0 }
	RadarService.ClearUAV(plr)
	push(plr)
end

local function onKill(plr)
	local a = Active[plr]
	if not a then return end
	a.Kills += 1
	for i = 1, 3 do
		local id = a.Slots[i]
		local def = id and id ~= "" and Armory.Streaks[id]
		if def and not a.Ready[i] and not a.Used[i] and a.Kills >= def.Kills then
			a.Ready[i] = true
			ctx.Remotes.StreakFX:FireClient(plr, "Ready", id, i)
		end
	end
	push(plr)
end

local function onReset(plr)
	local a = Active[plr]
	if not a then return end
	a.Kills, a.Ready = 0, {}
	push(plr)
end

-- ---------------------------------------------------------------- helpers
local function groundAt(pos, ignore)
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.FilterDescendantsInstances = ignore
	local res = workspace:Raycast(pos + Vector3.new(0, 90, 0), Vector3.new(0, -220, 0), rp)
	return res and res.Position or pos
end

local function characters()
	local list = {}
	for _, p in Players:GetPlayers() do
		if p.Character then table.insert(list, p.Character) end
	end
	return list
end

-- one falling shell: a glowing bomb drops onto `pos`, then explodes
local function shell(plr, pos, def, delay)
	task.delay(delay, function()
		if not plr.Parent then return end
		local ground = groundAt(pos, characters())
		local bomb = Instance.new("Part")
		bomb.Shape, bomb.Size, bomb.Material, bomb.Color = Enum.PartType.Ball, Vector3.new(1.4, 1.4, 1.4), Enum.Material.Neon, Color3.fromRGB(255, 120, 50)
		bomb.Anchored, bomb.CanCollide, bomb.CanQuery, bomb.CanTouch = true, false, false, false
		bomb.Position = ground + Vector3.new(0, 90, 0)
		bomb.Parent = workspace
		local trail = Instance.new("Trail")
		local a0, a1 = Instance.new("Attachment"), Instance.new("Attachment")
		a0.Position, a1.Position = Vector3.new(0, 0.6, 0), Vector3.new(0, -0.6, 0)
		a0.Parent, a1.Parent = bomb, bomb
		trail.Attachment0, trail.Attachment1, trail.Lifetime, trail.Color = a0, a1, 0.35, ColorSequence.new(Color3.fromRGB(255, 190, 90))
		trail.Parent = bomb
		local tw = TweenService:Create(bomb, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = ground })
		tw:Play()
		tw.Completed:Wait()
		bomb:Destroy()
		if plr.Parent then Equipment.Explode(ground + Vector3.new(0, 0.5, 0), def.Radius, def.Damage[1], def.Damage[2], plr, "Explosive") end
	end)
end

-- a pulsing marker where the strike will land
local function marker(pos, radius, seconds)
	local m = Instance.new("Part")
	m.Shape, m.Size, m.Material, m.Color, m.Transparency = Enum.PartType.Cylinder, Vector3.new(0.3, radius * 2, radius * 2), Enum.Material.Neon, Color3.fromRGB(255, 90, 60), 0.6
	m.Anchored, m.CanCollide, m.CanQuery, m.CanTouch = true, false, false, false
	m.CFrame = CFrame.new(pos + Vector3.new(0, 0.25, 0)) * CFrame.Angles(0, 0, math.rad(90))
	m.Parent = workspace
	TweenService:Create(m, TweenInfo.new(seconds, Enum.EasingStyle.Sine), { Transparency = 1 }):Play()
	Debris:AddItem(m, seconds)
end

-- ---------------------------------------------------------------- the streaks
local Run = {}

function Run.UAV(plr, def)
	RadarService.StartUAV(plr, def.Duration) -- server-side only: the minimap sweeps are sent by RadarService
end

function Run.Resupply(plr)
	local s = ctx.State[plr]
	if not s then return end
	for name, inv in s.Inv do
		local cfg = s.Cfgs and s.Cfgs[name] or Config.Weapons[name]
		if cfg and cfg.MagSize > 0 then
			inv.Ammo, inv.Reserve = cfg.MagSize, cfg.Reserve
		end
	end
	for _, slot in { s.Lethal, s.Tactical } do
		local d = Config.Equipment[slot.Name]
		if d then slot.Count = d.Count end
	end
	ctx.SyncAmmo(plr)
	ctx.SyncEquip(plr)
end

function Run.ArmorCache(plr)
	local s = ctx.State[plr]
	local hum = plr.Character and plr.Character:FindFirstChildOfClass("Humanoid")
	if not s or not hum then return end
	hum.Health = hum.MaxHealth
	s.Armor = Config.Armor.PlateArmor * Config.Armor.MaxEquipped
	s.Plates = Config.Armor.MaxCarried
	Damage.SyncArmor(plr)
end

function Run.Airstrike(plr, def, target, dir)
	local fwd = Vector3.new(dir.X, 0, dir.Z)
	if fwd.Magnitude < 0.1 then fwd = Vector3.new(0, 0, -1) end
	fwd = fwd.Unit
	marker(target, def.Radius * 0.6, def.Delay)
	for i = 0, def.Count - 1 do
		local p = target + fwd * (i - (def.Count - 1) / 2) * def.Spacing
		shell(plr, p, def, def.Delay + i * def.Interval)
	end
end

function Run.Mortar(plr, def, target)
	marker(target, def.Spread, def.Delay)
	for i = 1, def.Count do
		local ang, rad = math.random() * math.pi * 2, math.sqrt(math.random()) * def.Spread
		local p = target + Vector3.new(math.cos(ang) * rad, 0, math.sin(ang) * rad)
		shell(plr, p, def, def.Delay + (i - 1) / def.Count * def.Duration + math.random() * 0.3)
	end
end

function Run.ChemStrike(plr, def, target)
	marker(target, def.Spread, def.Delay)
	for i = 1, def.Count do
		local ang = (i / def.Count) * math.pi * 2
		local p = target + Vector3.new(math.cos(ang) * def.Spread * 0.6, 0, math.sin(ang) * def.Spread * 0.6)
		task.delay(def.Delay + i * 0.35, function()
			if not plr.Parent then return end
			local g = groundAt(p, characters())
			Equipment.Zone(g, def.Radius, def.Duration, "Gas", def.Dps, plr)
			ctx.Remotes.EquipFX:FireAllClients("Gas", g, def.Radius, def.Duration)
		end)
	end
end

-- ---------------------------------------------------------------- using one
local function use(plr, slot, origin, dir)
	local a, s = Active[plr], ctx.State[plr]
	if not a or not s or not s.Ready or s.Down or type(slot) ~= "number" or slot % 1 ~= 0 or slot < 1 or slot > 3 then return end
	if not a.Ready[slot] or a.Used[slot] or ctx.MatchFrozen then return end
	local id = a.Slots[slot]
	local def = id and Armory.Streaks[id]
	local char = plr.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local head = char and (char:FindFirstChild("Head") or char:FindFirstChild("HumanoidRootPart"))
	if not def or not hum or hum.Health <= 0 or not head or s.Plating or s.Cook then return end

	local target
	if TARGETED[id] then
		if typeof(origin) ~= "Vector3" or typeof(dir) ~= "Vector3" or dir.Magnitude < 0.5 or dir.Magnitude > 1.5 or (origin - head.Position).Magnitude > 12 then return end
		local res = Hitbox.Raycast(origin, dir.Unit * MAX_TARGET, { char })
		if not res then
			ctx.Remotes.StreakFX:FireClient(plr, "NoTarget", id, slot)
			return
		end
		target = res.Position
	end

	a.Ready[slot], a.Used[slot] = nil, true
	push(plr)
	ctx.Remotes.StreakFX:FireAllClients("Call", id, plr)
	Run[id](plr, def, target, dir)
end

function St.Init(c)
	ctx = c
	ctx.Remotes.StreakUse.OnServerEvent:Connect(use)
	ctx.Score.OnStreak = function(plr) onKill(plr) end
	ctx.Score.OnStreakReset = onReset
	Players.PlayerRemoving:Connect(function(plr) Active[plr] = nil end)
end

return St
