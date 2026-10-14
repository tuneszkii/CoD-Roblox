-- Server authority: loadouts, ammo, reload timing, fire-rate limit, hitscan / ballistic bullets / projectiles, melee, damage, third-person state replication.
-- NOTE: aim direction is client-supplied (sanity-checked). Add stricter validation for competitive use.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local FPS = RS:WaitForChild("FPS")
local Config = require(FPS:WaitForChild("Config"))
local Damage = require(script.Parent:WaitForChild("DamageService"))
local Equipment = require(script.Parent:WaitForChild("EquipmentService"))
local Data = require(script.Parent:WaitForChild("DataService"))
local Score = require(script.Parent:WaitForChild("ScoreService"))
local Hitbox = require(FPS:WaitForChild("Hitbox"))
local Ballistics = require(FPS:WaitForChild("Ballistics"))
local Penetration = require(FPS:WaitForChild("Penetration"))
local Bullets = require(script.Parent:WaitForChild("BulletService"))
local Match = require(script.Parent:WaitForChild("MatchService"))
local ArmoryService = require(script.Parent:WaitForChild("ArmoryService"))
local CosmeticsService = require(script.Parent:WaitForChild("CosmeticsService"))
local Streaks = require(script.Parent:WaitForChild("StreakService"))
local RadarService = require(script.Parent:WaitForChild("RadarService"))
local SpawnService = require(script.Parent:WaitForChild("SpawnService"))
local Achievements = require(script.Parent:WaitForChild("AchievementService"))
local Armory = require(FPS:WaitForChild("Armory"))
local SettingsSchema = require(FPS:WaitForChild("Settings"))
local PV = Config.PerkValues

local Remotes = Instance.new("Folder")
Remotes.Name = "Remotes"
local function newRemote(n, class)
	local r = Instance.new(class or "RemoteEvent")
	r.Name, r.Parent = n, Remotes
	return r
end
for _, n in {
	"Fire", "Reload", "Equip", "Melee", "EquipBegin", "EquipThrow", "EquipUse", "EquipPlace", "Detonate", "PlateStart", "PlateCancel",
	"StateSync", "Respawn", "Interact", "SaveSettings", "Vote", "Deploy", "StreakUse", "Emote", -- client -> server
	"HitConfirm", "FireFX", "AmmoSync", "ArmorSync", "DamageFX", "Suppress", "ExplosionFX", "EquipFX", "EquipSync", "SensorPing",
	"ProjectileSpawn", "ProjectileEnd", "XPSync", "ScoreEvent", "DownSync", "MatchEvent", "ArmoryEvent", "StreakSync", "StreakFX", "RadarSync", "AchievementEvent", -- server -> client
} do newRemote(n) end
local GetState = newRemote("GetState", "RemoteFunction")
newRemote("GetSettings", "RemoteFunction")
for _, n in { "GetArmory", "ArmoryBuy", "ArmorySave", "ArmorySelect", "GetCosmetics", "CosmeticsBuy", "CosmeticsEquip", "GetStats", "GetAchievements", "GetMastery" } do newRemote(n, "RemoteFunction") end
Remotes.Parent = FPS

local State = {}
local ctx = { Remotes = Remotes, State = State, Data = Data, Score = Score, Achievements = Achievements }

-- ---------------------------------------------------------------- loadouts
-- The loadout (weapons + attachments, equipment, perks, streaks) comes from the player's selected Armory class every time they spawn,
-- already validated (ArmoryService.Loadout). s.Cfgs holds each weapon's real config with its attachments applied.
local function fresh(plr, L)
	local perks = {}
	for _, n in L.Perks do perks[n] = true end
	local cfgs = {}
	for _, name in { L.Primary, L.Secondary } do cfgs[name] = Armory.Build(name, L.Attach[name]) end
	local s = {
		Weapon = nil, Inv = {}, Next = 0, Reloading = false, Token = 0, Ready = false,
		Loadout = L, Perks = perks, Cfgs = cfgs,
		Lethal = { Name = L.Lethal, Count = Config.Equipment[L.Lethal].Count },
		Tactical = { Name = L.Tactical, Count = Config.Equipment[L.Tactical].Count },
		Armor = Config.Armor.StartArmor, Plates = Config.Armor.StartCarried,
		LastDamage = -1000, MeleeNext = 0,
	}
	State[plr] = s
	return s
end

local function cfgOf(s, name) return s.Cfgs[name] or Config.Weapons[name] end

function ctx.SyncAmmo(plr)
	local s = State[plr]
	local inv = s and s.Weapon and s.Inv[s.Weapon]
	if inv then Remotes.AmmoSync:FireClient(plr, inv.Ammo, inv.Reserve) end
end

function ctx.SyncEquip(plr)
	local s = State[plr]
	if s then Remotes.EquipSync:FireClient(plr, s.Lethal.Count, s.Tactical.Count, Equipment.C4Count(plr)) end
end

Achievements.Init(ctx)  -- achievements + weapon mastery (before the profiles load: loading reports the player level)
Data.Init(ctx)
Score.Init(ctx)
Damage.Init(ctx)
Equipment.Init(ctx)
Bullets.Init(ctx)       -- real bullets: travel time, drop, air drag (Config.Ballistics)
ArmoryService.Init(ctx) -- unlocks, buy forward, classes, weapon XP
CosmeticsService.Init(ctx) -- operators, cards, emblems, titles, emotes, tracers
RadarService.Init(ctx)  -- minimap: UAV sweeps + gunfire pings (the server decides what enemy info a client gets)
Streaks.Init(ctx)       -- kill streak rewards
Match.Init(ctx) -- voting -> match -> results loop; players only spawn when the match puts them in
Hitbox.Start() -- pose-aware hitboxes (crouch / slide / downed / aim pitch) for every R6 player

-- ---------------------------------------------------------------- players / characters
local function setupCharacter(plr, char)
	Data.Wait(plr, 10) -- saved classes + progress
	if not plr.Parent or plr.Character ~= char then return end
	local s = fresh(plr, ArmoryService.Loadout(plr))
	local hum = char:WaitForChild("Humanoid", 10)
	if not hum or State[plr] ~= s then return end
	hum.MaxHealth, hum.Health = Config.Health.Max, Config.Health.Max
	hum.Died:Once(function() Score.OnDeath(plr) end)
	-- the default animation + health scripts fight the procedural third-person rig / custom regen
	local sc = char:FindFirstChild("Health") or char:WaitForChild("Health", 3)
	if sc then sc:Destroy() end
	if hum.RigType == Enum.HumanoidRigType.R6 then -- the procedural third-person rig replaces the default R6 animations
		local anim = char:FindFirstChild("Animate") or char:WaitForChild("Animate", 3)
		if anim then anim:Destroy() end
	end
	char:SetAttribute("Perks", table.concat(s.Loadout.Perks, ","))
	CosmeticsService.OnSpawn(plr, char) -- operator recolor + Operator attribute
	Streaks.OnSpawn(plr, s.Loadout)
	char:SetAttribute("Plates", math.ceil(s.Armor / Config.Armor.PlateArmor))
	s.Ready = true
	Remotes.EquipSync:FireClient(plr, s.Lethal.Count, s.Tactical.Count, Equipment.C4Count(plr))
end

local function onPlayer(plr)
	plr.CharacterAdded:Connect(function(char) task.spawn(setupCharacter, plr, char) end)
	if plr.Character then task.spawn(setupCharacter, plr, plr.Character) end
end
Players.PlayerAdded:Connect(onPlayer)
for _, p in Players:GetPlayers() do onPlayer(p) end
Players.PlayerRemoving:Connect(function(p)
	Equipment.Cleanup(p)
	State[p] = nil
end)

GetState.OnServerInvoke = function(plr)
	local s = State[plr]
	if not s or not s.Ready then return nil end
	return {
		Slots = { Primary = s.Loadout.Primary, Secondary = s.Loadout.Secondary }, Attach = s.Loadout.Attach, Streaks = Streaks.Sync(plr),
		Lethal = { Name = s.Lethal.Name, Count = s.Lethal.Count },
		Tactical = { Name = s.Tactical.Name, Count = s.Tactical.Count },
		Armor = s.Armor, Plates = s.Plates, Perks = s.Loadout.Perks, Profile = Data.Summary(plr),
	}
end

Remotes.Interact.OnServerEvent:Connect(function(plr, action, target)
	if action == "Start" then Damage.StartInteract(plr, target)
	elseif action == "Cancel" then Damage.CancelInteract(plr) end
end)

-- player options: saved with the profile, validated against the shared schema (clamped, unknown keys dropped)
Remotes.GetSettings.OnServerInvoke = function(plr)
	if not Data.Wait(plr, 15) then return false end
	return Data.GetSettings(plr) or false
end
-- stats page data: K/D, win/loss, accuracy, headshots, best gun, per-weapon stats, match history (see DataService.Stats)
local lastStatsGet = {}
Remotes.GetStats.OnServerInvoke = function(plr)
	local now = os.clock()
	if now - (lastStatsGet[plr] or -10) < 0.5 then return nil end
	lastStatsGet[plr] = now
	if not Data.Wait(plr, 15) then return nil end
	return Data.Stats(plr)
end
Players.PlayerRemoving:Connect(function(plr) lastStatsGet[plr] = nil end)
local lastSettingsSave = {}
Remotes.SaveSettings.OnServerEvent:Connect(function(plr, blob)
	local now = os.clock()
	if now - (lastSettingsSave[plr] or 0) < 0.5 or typeof(blob) ~= "table" then return end
	lastSettingsSave[plr] = now
	Data.SetSettings(plr, SettingsSchema.Sanitize(blob))
end)
Players.PlayerRemoving:Connect(function(plr) lastSettingsSave[plr] = nil end)

Remotes.Respawn.OnServerEvent:Connect(function(plr)
	local s = State[plr]
	if not s or os.clock() - (s.LastRespawn or 0) < 2 then return end
	s.LastRespawn = os.clock()
	Match.RequestRespawn(plr) -- only allowed right after spawning (so the new loadout applies) and never in round modes
end)

RunService.Heartbeat:Connect(function(dt) Damage.Regen(dt) end)

-- ---------------------------------------------------------------- weapons
local falloff = Ballistics.Falloff

Remotes.Equip.OnServerEvent:Connect(function(plr, name)
	local s = State[plr]
	local L = s and s.Loadout
	if not s or type(name) ~= "string" or (name ~= L.Primary and name ~= L.Secondary) then return end
	local cfg = cfgOf(s, name)
	if s.Down and not Config.Down.AllowedClasses[cfg.Class] then return end
	s.Weapon = name
	if plr.Character then plr.Character:SetAttribute("WeaponAtt", table.concat(L.Attach[name] or {}, ",")) end -- third-person gun shows the attachments
	s.Inv[name] = s.Inv[name] or { Ammo = cfg.MagSize, Reserve = cfg.Reserve }
	s.Reloading = false
	s.Token += 1
	Equipment.CancelActions(s)
	s.Next = os.clock() + cfg.EquipTime * 0.8
	Remotes.AmmoSync:FireClient(plr, s.Inv[name].Ammo, s.Inv[name].Reserve)
end)

Remotes.Reload.OnServerEvent:Connect(function(plr, arg)
	local s = State[plr]
	if not s or not s.Weapon then return end
	local cfg, inv = cfgOf(s, s.Weapon), s.Inv[s.Weapon]
	if arg == "Cancel" then
		if s.Reloading then
			s.Token += 1
			s.Reloading = false
			ctx.SyncAmmo(plr)
		end
		return
	end
	if cfg.MagSize <= 0 or s.Reloading or inv.Ammo >= cfg.MagSize or inv.Reserve <= 0 then return end
	local perk = Config.Has(s.Perks, "FastHands") and PV.FastHands or 1
	s.Reloading = true
	s.Token += 1
	local token = s.Token
	if cfg.ReloadStyle == "Shell" then
		task.spawn(function()
			task.wait(cfg.ReloadStart * perk * 0.9)
			while State[plr] == s and s.Token == token and inv.Ammo < cfg.MagSize and inv.Reserve > 0 do
				task.wait(cfg.ShellTime * perk * 0.9)
				if State[plr] ~= s or s.Token ~= token then return end
				inv.Ammo += 1
				inv.Reserve -= 1
			end
			if State[plr] == s and s.Token == token then
				s.Reloading = false
				ctx.SyncAmmo(plr)
			end
		end)
	else
		local t = (inv.Ammo == 0 and cfg.ReloadEmptyTime or cfg.ReloadTime) * perk
		task.delay(t * 0.8, function() -- fills slightly before the client finishes the animation
			if State[plr] ~= s or s.Token ~= token then return end
			local take = math.min(cfg.MagSize - inv.Ammo, inv.Reserve)
			inv.Ammo += take
			inv.Reserve -= take
			s.Reloading = false
			ctx.SyncAmmo(plr)
		end)
	end
end)

-- Instant ray (hitscan weapons): damage, accuracy stats and the hit marker are resolved right now.
-- Returns where each ray ended, for the tracers. Ballistic weapons go through BulletService instead.
local function fireHitscan(plr, name, cfg, char, origin, dirs)
	local anyHit, anyHead, killed, ends = false, false, false, {}
	local shot = Score.NewShotId(plr)
	local power = Penetration.PowerOf(cfg)

	-- Penetration.Trace calls this for every living body the ray goes through (damage drops with each wall / body it already crossed)
	local hooks = {
		Body = function(_, res, st)
			local model = res.Instance:FindFirstAncestorOfClass("Model")
			local vh = model and model:FindFirstChildOfClass("Humanoid")
			if not (vh and vh.Health > 0) then return end
			local mult, nm = 1, res.Instance.Name
			if nm == "Head" then mult = cfg.HeadMult
			elseif nm:find("Leg") or nm:find("Foot") then mult = 0.9 end
			local dist = (res.Position - origin).Magnitude -- (res.Distance is only from the last surface the ray came through)
			local dead = Damage.Apply(vh, falloff(cfg.Damage, dist) * mult * st.Mult, plr, "Bullet", origin,
				{ Head = nm == "Head", Dist = dist, Shot = shot, Wallbang = st.Walls > 0, ArmorPierce = cfg.ArmorPierce })
			if not dead and cfg.Burn then Damage.Burn(vh, plr, cfg.Burn, origin) end
			local victim = Players:GetPlayerFromCharacter(model)
			if not (victim and Damage.IsFriendly(plr, victim)) then
				anyHit, anyHead = true, anyHead or nm == "Head"
				if dead then killed = true end
			end
		end,
	}

	for i, d in dirs do
		if i > (cfg.Pellets or 1) then break end
		if typeof(d) == "Vector3" and d.Magnitude > 0.5 and d.Magnitude < 1.5 then
			-- walls + the pose-aware bodies of every player; the ray can punch through some of them. Own ignore list per ray (Trace adds to it).
			local stop = Penetration.Trace(origin, d.Unit * cfg.Range, { char }, Penetration.New(power), hooks)
			table.insert(ends, stop)
		end
	end

	Data.RecordShot(plr, name, anyHit, anyHead) -- accuracy / headshot stats (lifetime, per weapon and per match)
	if anyHit then Remotes.HitConfirm:FireClient(plr, anyHead, killed) end
	return ends
end

Remotes.Fire.OnServerEvent:Connect(function(plr, name, origin, dirs)
	local s = State[plr]
	if not s or s.Weapon ~= name or typeof(origin) ~= "Vector3" or type(dirs) ~= "table" then return end
	local cfg, inv = cfgOf(s, name), s.Inv[name]
	if cfg.Class == "Melee" or s.Cook or s.Plating then return end
	if s.Down and not Config.Down.AllowedClasses[cfg.Class] then return end
	local char = plr.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local head = char and (char:FindFirstChild("Head") or char:FindFirstChild("HumanoidRootPart"))
	if not hum or hum.Health <= 0 or not head then return end
	if s.Reloading and cfg.ReloadStyle == "Shell" and inv.Ammo > 0 then -- firing interrupts a shell reload
		s.Reloading = false
		s.Token += 1
	end
	if s.Reloading or inv.Ammo <= 0 then
		ctx.SyncAmmo(plr)
		return
	end

	local now, interval = os.clock(), 60 / cfg.RPM
	if now + 0.05 < s.Next then return end
	s.Next = math.max(s.Next, now - interval) + interval * 0.9
	if (origin - head.Position).Magnitude > 12 then return end

	inv.Ammo -= 1
	Match.BreakProtection(plr) -- firing ends spawn protection

	if cfg.Projectile then
		local d = dirs[1]
		if typeof(d) ~= "Vector3" or d.Magnitude < 0.5 or d.Magnitude > 1.5 then return end
		local pj = cfg.Projectile
		Equipment.Launch(plr, pj.Kind, origin, d, pj.Speed, pj.Gravity, function(pos, normal)
			Equipment.Explode(pos + normal * 0.3, pj.Radius, pj.Damage[1], pj.Damage[2], plr, "Explosive")
		end)
		return
	end

	local ends, ball = {}, nil
	local bal = Ballistics.For(cfg)
	if bal then
		-- real bullets: BulletService flies them and resolves hits / stats when they land. The other clients only need the path.
		local vels, t0 = Bullets.Fire(plr, name, cfg, bal, origin, dirs, Score.NewShotId(plr))
		ball = { Vels = vels, G = bal.Gravity, K = bal.Drag, T0 = t0, Range = cfg.Range, Pen = Penetration.PowerOf(cfg) }
	else
		ends = fireHitscan(plr, name, cfg, char, origin, dirs)
	end
	for _, other in Players:GetPlayers() do
		if other ~= plr then
			-- a suppressed shot is only seen / heard close by
			local oroot = cfg.Suppressed and other.Character and other.Character:FindFirstChild("HumanoidRootPart")
			if not cfg.Suppressed or (oroot and (oroot.Position - origin).Magnitude <= 45) then
				Remotes.FireFX:FireClient(other, plr, origin, ends, name, ball)
			end
		end
	end
	if not cfg.Suppressed then
		RadarService.Ping(plr)
		SpawnService.NoteFire(plr, head.Position, plr.Team and plr.Team.Name or nil) -- the spawn scorer avoids recent gunfire
	end -- minimap ping for the other team (server position, not the client origin)
end)

-- ---------------------------------------------------------------- melee
Remotes.Melee.OnServerEvent:Connect(function(plr, kind, origin, dir)
	local s = State[plr]
	if not s or not s.Weapon or type(kind) ~= "string" or typeof(origin) ~= "Vector3" or typeof(dir) ~= "Vector3" then return end
	if dir.Magnitude < 0.5 or dir.Magnitude > 1.5 or s.Cook or s.Plating or s.Down then return end
	Match.BreakProtection(plr) -- meleeing ends spawn protection
	local cfg = cfgOf(s, s.Weapon)
	local atk, back
	if kind == "Quick" then
		atk, back = Config.QuickMelee, Config.QuickMelee.Back
	elseif cfg.Class == "Melee" and (kind == "Light" or kind == "Heavy") then
		atk, back = cfg.Melee[kind], cfg.Melee.Back
	else
		return
	end
	local char = plr.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local head = char and (char:FindFirstChild("Head") or char:FindFirstChild("HumanoidRootPart"))
	if not hum or hum.Health <= 0 or not head or (origin - head.Position).Magnitude > 12 then return end
	local now = os.clock()
	if now < s.MeleeNext - 0.1 then return end
	s.MeleeNext = now + (atk.Time or atk.Cooldown) * 0.7

	dir = dir.Unit
	local res = Hitbox.Spherecast(origin, atk.Radius, dir * atk.Range, { char })
	if not res then return end
	local model = res.Instance:FindFirstAncestorOfClass("Model")
	local vh = model and model:FindFirstChildOfClass("Humanoid")
	local vroot = model and model:FindFirstChild("HumanoidRootPart")
	if not vh or vh.Health <= 0 then return end
	local dmg, behind = atk.Damage, false
	if vroot and vroot.CFrame.LookVector:Dot(dir) > 0.35 then dmg, behind = back, true end -- attacking from behind
	local killed = Damage.Apply(vh, dmg, plr, "Melee", origin, { Backstab = behind, Dist = res.Distance })
	local victim = Players:GetPlayerFromCharacter(model)
	if not killed and victim and kind == "Heavy" and not behind then -- heavy swings shove the target back
		Remotes.ExplosionFX:FireClient(victim, origin, 0.55)
	end
	if not (victim and Damage.IsFriendly(plr, victim)) then Remotes.HitConfirm:FireClient(plr, res.Instance.Name == "Head", killed) end
end)

-- ---------------------------------------------------------------- third-person state replication
local STANCES = { Downed = true, Idle = true, Walk = true, Crouch = true, Prone = true, Sprint = true, TacSprint = true, Slide = true, Air = true, Dive = true,
	Mantle = true, Vault = true }
local ACTIONS = {
	[""] = true, Reload = true, ReloadEmpty = true, ShellStart = true, ShellLoad = true, ShellEnd = true, Bolt = true, Pump = true,
	Bash = true, SwingR = true, SwingL = true, Lunge = true, Smash = true, Pull = true, Hold = true, Throw = true, Use = true,
	Sensor = true, Plant = true, Plate = true,
}

local PEEK_STANCES = { Idle = true, Walk = true, Crouch = true } -- you cannot lean while sprinting, sliding, airborne or downed

-- Mantle / vault: the client says where the ledge is and how long the climb takes; everything else about the pose is derived from that
-- (ClimbPose.luau). Returns the stance to believe: the claimed climb if the data is sane and not too soon after the last one, else "Air".
local function acceptClimb(s, char, stance, climb)
	local root = char:FindFirstChild("HumanoidRootPart")
	if not root or type(climb) ~= "table" then return "Air" end
	local ledge, depth, el, cd = climb.Ledge, climb.Depth, climb.Elapsed, climb.Dur
	if typeof(ledge) ~= "CFrame" or type(depth) ~= "number" or type(el) ~= "number" or type(cd) ~= "number" then return "Air" end
	local p, look = ledge.Position, ledge.LookVector
	if p ~= p or look ~= look or depth ~= depth or el ~= el or cd ~= cd then return "Air" end -- NaN
	if (p - root.Position).Magnitude > Config.Hitbox.ClimbMaxDist then return "Air" end -- the ledge has to be where the player is
	cd = math.clamp(cd, 0.1, 1.5)
	el = math.clamp(el, 0, cd)
	local now = workspace:GetServerTimeNow()
	-- the same climb keeps its start; a new ledge or kind is a new climb, and those are rate limited
	if s.ClimbStance ~= stance or not s.ClimbLip or (s.ClimbLip - p).Magnitude > 0.5 then
		if now - (s.ClimbT or -math.huge) < Config.Hitbox.ClimbGap then return "Air" end
		s.ClimbStance, s.ClimbLip, s.ClimbT = stance, p, now
		char:SetAttribute("ClimbStart", now - el)
		char:SetAttribute("ClimbDur", cd)
		char:SetAttribute("ClimbLedge", ledge)
		char:SetAttribute("ClimbDepth", math.clamp(depth, 0, 8))
	end
	return stance
end

Remotes.StateSync.OnServerEvent:Connect(function(plr, stance, pitch, ads, weapon, act, item, elapsed, dur, peek, climb)
	local s = State[plr]
	local char = plr.Character
	if not s or not char or not STANCES[stance] or type(pitch) ~= "number" or type(ads) ~= "number" then return end
	if type(act) ~= "string" or not ACTIONS[act] or type(item) ~= "string" or type(elapsed) ~= "number" or type(dur) ~= "number" then return end
	if weapon ~= nil and (type(weapon) ~= "string" or not Config.Weapons[weapon]) then return end
	-- climb attributes are written BEFORE the stance flips, so a client never sees "Mantle" together with the previous climb's data
	if stance == "Mantle" or stance == "Vault" then
		stance = acceptClimb(s, char, stance, climb)
	elseif s.ClimbStance then
		s.ClimbStance, s.ClimbLip = nil, nil
		for _, a in { "ClimbStart", "ClimbDur", "ClimbLedge", "ClimbDepth" } do char:SetAttribute(a, nil) end
	end
	CosmeticsService.OnState(plr, stance, act) -- moving or acting ends an emote
	char:SetAttribute("Stance", stance)
	char:SetAttribute("AimPitch", math.floor(math.clamp(pitch, -1.5, 1.5) * 50 + 0.5) / 50)
	char:SetAttribute("AdsAmt", math.floor(math.clamp(ads, 0, 1) * 20 + 0.5) / 20)
	-- corner peek (Q / E while aiming): only believed while the player is actually aiming in an upright stance
	local lean = (type(peek) == "number" and peek == peek and ads >= 0.2 and PEEK_STANCES[stance]) and math.clamp(peek, -1, 1) or 0
	char:SetAttribute("PeekAmt", math.floor(lean * 20 + 0.5) / 20)
	char:SetAttribute("WeaponName", weapon or "")
	if s.LastAct ~= act or s.LastItem ~= item then
		s.LastAct, s.LastItem = act, item
		char:SetAttribute("Action", act)
		char:SetAttribute("ActionItem", item)
		char:SetAttribute("ActionStart", workspace:GetServerTimeNow() - math.clamp(elapsed, 0, 30))
		char:SetAttribute("ActionDur", math.clamp(dur, 0, 30))
	end
end)
