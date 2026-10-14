-- Client weapon logic: input, ADS, fire modes, spread/bloom, pattern recoil, reload styles (mag / cylinder / shells / rocket),
-- bolt + pump cycling, scopes, melee, lethal + tactical equipment, armor plates, perks, status effects, HUD, FX.
local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local FPS = script.Parent
local Config = require(FPS.Config)
local Armory = require(script.Parent.Armory)
local Anim = require(FPS.Anim)
local Hud = require(FPS.Hud)
local Theme = require(FPS.Theme)
local ThirdPerson = require(FPS.ThirdPerson)
local Hitbox = require(FPS.Hitbox)
local TracerFX = require(FPS.TracerFX)
local BulletFX = require(FPS.BulletFX)
local Ballistics = require(FPS.Ballistics)
local Penetration = require(FPS.Penetration)
local Settings = require(FPS.Settings)
local UISound = require(FPS.UISound)
local InputMap = require(FPS.InputMap)
local Remotes = FPS:WaitForChild("Remotes")
local player = Players.LocalPlayer
local PV = Config.PerkValues
local function keyName(action)
	local l = InputMap.Label(action)
	return l ~= "" and l or "USE"
end

-- ---------------------------------------------------------------- fx helpers
-- the tracer style is the shooter's equipped Cosmetics tracer (player attribute "CosTracer", see TracerFX.luau)
local function tracer(a, b, shooter)
	TracerFX.Spawn(a, b, shooter and shooter:GetAttribute("CosTracer"))
end

local function impact(pos, normal, color)
	local p = Instance.new("Part")
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.Transparency = true, false, false, false, 1
	p.Size = Vector3.one * 0.2
	p.CFrame = CFrame.lookAt(pos, pos + normal)
	p.Parent = workspace.CurrentCamera
	local e = Instance.new("ParticleEmitter")
	e.Rate, e.Lifetime, e.Speed = 0, NumberRange.new(0.15, 0.3), NumberRange.new(8, 16)
	e.SpreadAngle, e.EmissionDirection, e.Acceleration = Vector2.new(35, 35), Enum.NormalId.Front, Vector3.new(0, -30, 0)
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.12), NumberSequenceKeypoint.new(1, 0) })
	e.Color, e.LightEmission = ColorSequence.new(color or Color3.fromRGB(255, 200, 120)), 1
	e.Parent = p
	e:Emit(6)
	Debris:AddItem(p, 0.6)
end

-- Penetration.Trace hooks for your own hitscan rays: a bullet hole wherever the ray enters / leaves / ends on a surface (ud = tracer colour)
local hitscanFX = { Impact = function(color, pos, normal) impact(pos, normal, color) end }

local function playSound(id, vol)
	if not id or id == "" then return end
	local s = Instance.new("Sound")
	s.SoundId, s.Volume = id, vol or 0.6
	s.Parent = workspace.CurrentCamera
	s:Play()
	Debris:AddItem(s, 3)
end

local function spreadDir(cf, deg)
	local r = math.tan(math.rad(deg)) * math.sqrt(math.random())
	local th = math.random() * math.pi * 2
	return (cf.LookVector + cf.RightVector * (r * math.cos(th)) + cf.UpVector * (r * math.sin(th))).Unit
end

local function approach(cur, target, step)
	if cur < target then return math.min(cur + step, target) end
	return math.max(cur - step, target)
end

local function ping(pos) -- heartbeat sensor blip
	local p = Instance.new("Part")
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.Transparency, p.Size = true, false, false, false, 1, Vector3.one
	p.Position = pos
	p.Parent = workspace.CurrentCamera
	local bb = Instance.new("BillboardGui")
	bb.Size, bb.AlwaysOnTop = UDim2.fromOffset(18, 18), true
	bb.Parent = p
	local f = Instance.new("Frame")
	f.Size, f.BackgroundColor3, f.BorderSizePixel = UDim2.fromScale(1, 1), Color3.fromRGB(255, 60, 60), 0
	f.Parent = bb
	Instance.new("UICorner", f).CornerRadius = UDim.new(1, 0)
	Debris:AddItem(p, 0.75)
end

-- ---------------------------------------------------------------- controller
local W = {}
W.__index = W

function W.new(movement, camRig, viewmodel)
	local self = setmetatable({}, W)
	self.Movement, self.Cam, self.VM = movement, camRig, viewmodel
	self.Hud = Hud.new(player)
	self.Slots, self.Inv, self.Index, self.Name, self.Cfg = { Config.Loadout.Primary, Config.Loadout.Secondary }, {}, 1, nil, nil
	self.Equip = { Lethal = nil, Tactical = nil }
	self.Armor, self.Plates, self.Perks, self.C4Out = 0, 0, {}, 0
	self.Ads, self.AdsEased, self.AdsHeld, self.FireHeld, self.SemiBuffer = 0, 0, false, false, 0
	self.PeekCur, self.PeekAmt = 0, 0 -- corner peek while aiming: -1 = full left, 1 = full right (PeekAmt is the eased value the camera uses)
	self.FireModeSel = {} -- [weapon] = the fire mode the player switched to (absent = the gun's default)
	self.Rl, self.Busy, self.ThrowHeld = nil, nil, {}
	self.NextFire, self.SprintLock, self.EquipLock, self.LastShot, self.ShotIndex, self.Bloom = 0, 0, 0, 0, 0, 0
	self.CycleT, self.CycleDrop, self.MeleeNext = 0, false, 0
	self.SpeedMult, self.Active = 1, false
	self.Scoped, self.HoldingBreath, self.BreathLeft, self.BreathRest, self.HideMag = false, false, 0, 0, false
	self.FlashT, self.FlashMax, self.StunT, self.StunMax, self.GasT, self.GasZones = 0, 1, 0, 1, 0, {}
	self.StimT, self.StimMult, self.DamageT, self.CoughT = 0, 1, 0, 0
	self.Act, self.SyncT, self.Projs = nil, 0, {}
	self.Downed, self.DownHealth, self.DownDrain, self.InteractHeld, self.Target = false, 0, 0, false, nil
	self:_bindInput()
	self:_bindRemotes()
	return self
end

-- ---------------------------------------------------------------- perks / state helpers
function W:_perk(name) return Config.Has(self.Perks, name) end

function W:_act(name, item, dur)
	self.Act = { Name = name, Item = item or "", Start = os.clock(), Dur = dur or 0 }
end

function W:_clearAct() self.Act = nil end

local function modeLabel(cfg, mode)
	if cfg.Class == "Melee" then return "" end
	if cfg.Cycle then return cfg.Model == "Pump" and "PUMP" or "BOLT" end
	if cfg.Projectile then return "SINGLE" end
	return mode == "Auto" and "AUTO" or "SEMI"
end

-- the fire mode in effect right now: what the player switched to, otherwise the gun's default
function W:_mode()
	local cfg = self.Cfg
	if not cfg then return "Semi" end
	local sel = self.FireModeSel[self.Name]
	if sel and table.find(Config.FireModesOf(cfg), sel) then return sel end
	return cfg.FireMode
end

-- cycles Auto <-> Semi (whatever the gun's FireModes list holds). Does nothing on guns that are locked to one mode.
function W:SwitchFireMode()
	local cfg = self.Cfg
	if not cfg then return end
	local modes = Config.FireModesOf(cfg)
	if #modes < 2 then return end
	if self.Rl or self.Busy or self.EquipLock > 0.15 or self.CycleT > 0 then return end
	local i = table.find(modes, self:_mode()) or 0
	self.FireModeSel[self.Name] = modes[i % #modes + 1]
	self.SemiBuffer = 0 -- a click that was still buffered must not fire one extra round in the new mode
	self.NextFire = math.max(self.NextFire, os.clock() + 0.15) -- short switch delay
	self.VM:Kick(0.25, self.AdsEased)
	UISound.Play("FireMode", 0.5)
	self:_updateHud()
end

function W:_updateHud()
	local inv, cfg = self.Inv[self.Name], self.Cfg
	if inv and cfg then
		self.Hud:SetAmmo(inv.Ammo, inv.Reserve, self.Name, cfg.Class == "Melee", modeLabel(cfg, self:_mode()), cfg.MagSize)
	end
	local function info(e)
		if not e then return nil end
		local def = Config.Equipment[e.Name]
		return { Label = def.Label, Count = e.Count, Max = def.Count }
	end
	self.Hud:SetEquip(info(self.Equip.Lethal), info(self.Equip.Tactical), self.C4Out > 0)
	self.Hud:SetArmor(self.Armor, self.Plates)
end

-- ---------------------------------------------------------------- input
function W:_bindInput()
	local LADDER_OK = { Fire = true, Aim = true, Reload = true, Interact = true } -- the hands are on the ladder: nothing else works there
	local function on(action, fn)
		InputMap.OnBegan(action, function()
			if not self.Active or self.Locked then return end
			if self.Movement.Ladder and not LADDER_OK[action] then return end
			fn()
		end)
	end
	on("Fire", function()
		if self.Cfg and self.Cfg.Class == "Melee" and not self.Movement.Ladder then self:MeleeAttack("Light") else self.FireHeld, self.SemiBuffer = true, os.clock() + 0.15 end
	end)
	InputMap.OnEnded("Fire", function() self.FireHeld = false end)
	on("Aim", function()
		if self.Cfg and self.Cfg.Class == "Melee" and not self.Movement.Ladder then self:MeleeAttack("Heavy")
		elseif Settings.Get("Gameplay.AdsMode") == "Toggle" then self.AdsHeld = not self.AdsHeld
		else self.AdsHeld = true end
	end)
	InputMap.OnEnded("Aim", function()
		if Settings.Get("Gameplay.AdsMode") ~= "Toggle" then self.AdsHeld = false end
	end)
	on("Reload", function()
		if self.Movement.Ladder and not (self.AdsHeld or self.FireHeld) then return end -- only with the pistol out
		self:Reload()
	end)
	on("FireMode", function() self:SwitchFireMode() end)
	on("Weapon1", function() self:Equip(1) end)
	on("Weapon2", function() self:Equip(2) end)
	on("SwitchWeapon", function() self:Equip(self.Index == 1 and 2 or 1) end)
	on("Lethal", function() self.ThrowHeld.Lethal = true; self:UseEquipment("Lethal") end)
	on("Tactical", function()
		if self:_peekOwnsKey("Tactical") then return end -- Q peeks left while aiming
		self.ThrowHeld.Tactical = true
		self:UseEquipment("Tactical")
	end)
	InputMap.OnEnded("Lethal", function() self.ThrowHeld.Lethal = false end)
	InputMap.OnEnded("Tactical", function() self.ThrowHeld.Tactical = false end)
	on("Melee", function() self:QuickMelee() end)
	on("Plate", function() self:Plate() end)
	on("Detonate", function() Remotes.Detonate:FireServer() end)
	on("Interact", function()
		if self:_peekOwnsKey("Interact") then return end -- E peeks right while aiming
		self.InteractHeld = true
		self:TryInteract()
	end)
	InputMap.OnEnded("Interact", function() self.InteractHeld = false end)
end

-- Q / E are also tactical / interact. While the player is aiming (RMB held, or toggled on) a key that is bound to a peek action
-- leans instead; any other key (or the same action once the player rebinds peek elsewhere) behaves as before.
function W:_peekOwnsKey(action)
	if not self.AdsHeld then return false end
	local binds = Settings.GetBinds()
	local mine = binds[action]
	if not mine then return false end
	for _, peek in { "PeekLeft", "PeekRight" } do
		local pb = binds[peek]
		if pb then
			for _, device in { "KBM", "PAD" } do
				for _, code in mine[device] do
					if code ~= "" and (pb[device][1] == code or pb[device][2] == code) then return true end
				end
			end
		end
	end
	return false
end

-- ---------------------------------------------------------------- remotes
function W:_bindRemotes()
	Remotes:WaitForChild("AmmoSync").OnClientEvent:Connect(function(ammo, reserve)
		local inv = self.Inv[self.Name]
		if inv and not self.Rl then
			inv.Ammo, inv.Reserve = ammo, reserve
			self:_updateHud()
		end
	end)
	Remotes.HitConfirm.OnClientEvent:Connect(function(head, kill) self.Hud:Hitmarker(head, kill) end)
	Remotes.FireFX.OnClientEvent:Connect(function(shooter, origin, ends, _name, ball)
		ThirdPerson.OnFire(shooter)
		if ball then -- real bullets: fly the same path the server simulates (no per-bullet traffic)
			local ignore = { workspace.CurrentCamera }
			if shooter and shooter.Character then table.insert(ignore, shooter.Character) end
			BulletFX.Spawn({
				Origin = origin, Vels = ball.Vels, G = ball.G, K = ball.K, T0 = ball.T0, Range = ball.Range, Pen = ball.Pen,
				Style = shooter and shooter:GetAttribute("CosTracer"), Ignore = ignore,
			})
			return
		end
		for i, e in ends do
			if i > 3 then break end
			tracer(origin, e, shooter)
		end
	end)
	Remotes.ArmorSync.OnClientEvent:Connect(function(armor, plates)
		self.Armor, self.Plates = armor, plates
		self:_updateHud()
	end)
	Remotes.EquipSync.OnClientEvent:Connect(function(lethal, tactical, c4)
		if self.Equip.Lethal then self.Equip.Lethal.Count = lethal end
		if self.Equip.Tactical then self.Equip.Tactical.Count = tactical end
		self.C4Out = c4
		self:_updateHud()
	end)
	Remotes.DamageFX.OnClientEvent:Connect(function(fromPos, amount, kind)
		self.DamageT = math.clamp(self.DamageT + amount / 80, 0, 0.8)
		local cam = workspace.CurrentCamera
		local rel = cam.CFrame:VectorToObjectSpace(fromPos - cam.CFrame.Position)
		if fromPos ~= Vector3.zero and (rel.X ~= 0 or rel.Z ~= 0) then
			self.Hud:DamageIndicator(math.atan2(rel.X, -rel.Z), amount)
		end
		if kind ~= "Fire" and kind ~= "Gas" then -- damage-over-time ticks would flinch every tick
			local F = Config.Flinch
			local k = math.clamp(amount / F.Hit.DamageRef, F.Hit.Min, F.Hit.Max)
			if kind == "Explosive" then k *= F.ExplosiveScale end
			self:_flinch(F.Hit, k, fromPos ~= Vector3.zero and rel or nil)
		end
	end)
	-- a bullet cracked past without hitting: a much lighter flinch than a hit (Config.Flinch.Suppress)
	Remotes.Suppress.OnClientEvent:Connect(function(closeness, fromPos)
		if type(closeness) ~= "number" then return end
		local def = Config.Flinch.Suppress
		local k = def.MinStrength + (1 - def.MinStrength) * math.clamp(closeness, 0, 1)
		local cam = workspace.CurrentCamera
		self:_flinch(def, k, typeof(fromPos) == "Vector3" and cam.CFrame:VectorToObjectSpace(fromPos - cam.CFrame.Position) or nil)
	end)
	Remotes.ExplosionFX.OnClientEvent:Connect(function(pos, power)
		local root = self.Movement.Root
		if not root then return end
		self.Cam:AddShake(Vector3.new(-0.6 * power, (math.random() - 0.5) * power * 0.5, (math.random() - 0.5) * power * 0.7))
		local away = root.Position - pos
		if away.Magnitude > 0.1 and power > 0.2 then
			root.AssemblyLinearVelocity += (away.Unit * 45 + Vector3.new(0, 14, 0)) * power
		end
	end)
	Remotes.EquipFX.OnClientEvent:Connect(function(kind, a, b, c)
		if kind == "Stim" then self.StimT, self.StimMult = a, b
		elseif kind == "Flash" or kind == "Stun" then self:_exposure(kind, a, b, c)
		elseif kind == "Gas" then table.insert(self.GasZones, { Pos = a, Radius = b, Expire = os.clock() + c }) end
	end)
	Remotes.DownSync.OnClientEvent:Connect(function(state, health, drain)
		self:_setDowned(state, health, drain)
	end)
	Remotes.XPSync.OnClientEvent:Connect(function(profile, leveledUp)
		if not profile then return end
		self.Hud:SetXP(profile.Level, profile.Into, profile.Needed)
		if leveledUp then self.Hud:Toast("LEVEL UP!  LV " .. profile.Level, Theme.Accent) end
	end)
	Remotes.ScoreEvent.OnClientEvent:Connect(function(tag, xp)
		local def = Config.Scoring.Tags[tag]
		if def then self.Hud:ScorePopup(def.Label, xp, def.Medal == true) end
	end)
	Remotes.SensorPing.OnClientEvent:Connect(function(list) for _, p in list do ping(p) end end)
	Remotes.ProjectileSpawn.OnClientEvent:Connect(function(id, kind, origin, vel, g, t0) self:_spawnProjectile(id, kind, origin, vel, g, t0) end)
	Remotes.ProjectileEnd.OnClientEvent:Connect(function(id, pos, normal, kind) self:_endProjectile(id, pos, normal, kind) end)
end

-- head snap + weapon jolt. def = Config.Flinch.Hit / .Suppress, k = strength, rel = where it came from in camera space (nil = unknown)
function W:_flinch(def, k, rel)
	local now = os.clock()
	if now - (self.FlinchAt or 0) < def.Cooldown then return end
	if self.Locked then return end
	self.FlinchAt = now
	local side = 0
	if rel and rel.Magnitude > 0.1 and math.abs(rel.X) > rel.Magnitude * 0.25 then
		side = rel.X > 0 and 1 or -1 -- shot from the right: head snaps left, and the other way round
	end
	self.Cam:Flinch(def, k, side, self.AdsEased)
	self.VM:Flinch(k * def.Viewmodel * (1 - (1 - Config.Flinch.AdsScale) * (self.AdsEased or 0)), side == 0 and (math.random() < 0.5 and -1 or 1) or side)
end

function W:_exposure(kind, pos, radius, duration)
	local cam = workspace.CurrentCamera
	local to = pos - cam.CFrame.Position
	local dist = to.Magnitude
	if dist > radius then return end
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.FilterDescendantsInstances = { player.Character, cam }
	if workspace:Raycast(cam.CFrame.Position, to, rp) then return end -- blocked by geometry
	local facing = to.Magnitude > 0.01 and cam.CFrame.LookVector:Dot(to.Unit) or 1
	local amount = (1 - dist / radius) * math.clamp(0.35 + 0.65 * (facing + 0.2) / 1.2, 0.2, 1)
	if kind == "Flash" and facing < -0.3 then amount *= 0.35 end
	local t = duration * amount
	if self:_perk("BattleHardened") then t *= PV.BattleHardened end
	if kind == "Flash" then
		self.FlashT = math.max(self.FlashT, t)
		self.FlashMax = math.max(self.FlashMax, self.FlashT)
	else
		self.StunT = math.max(self.StunT, t)
		self.StunMax = math.max(self.StunMax, self.StunT)
	end
end

-- cosmetic projectiles follow the exact analytic path the server simulates
function W:_spawnProjectile(id, kind, origin, vel, g, t0)
	local p = Instance.new("Part")
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
	if kind == "Rocket" then
		p.Size, p.Color, p.Material = Vector3.new(0.35, 0.35, 1.6), Color3.fromRGB(90, 96, 80), Enum.Material.Metal
		local e = Instance.new("ParticleEmitter")
		e.Rate, e.Lifetime, e.Speed = 60, NumberRange.new(0.5, 0.9), NumberRange.new(0, 2)
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.9), NumberSequenceKeypoint.new(1, 2.2) })
		e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 1) })
		e.Color = ColorSequence.new(Color3.fromRGB(200, 200, 200))
		e.Parent = p
	elseif kind == "Knife" then
		p.Size, p.Color, p.Material = Vector3.new(0.08, 0.2, 1), Color3.fromRGB(200, 200, 205), Enum.Material.Metal
	else
		p.Size, p.Color, p.Material, p.Shape = Vector3.one * 0.6, Color3.fromRGB(70, 80, 60), Enum.Material.Metal, Enum.PartType.Ball
	end
	p.Parent = workspace.CurrentCamera
	self.Projs[id] = { Part = p, Origin = origin, Vel = vel, G = g, T0 = t0 }
end

function W:_endProjectile(id, pos, normal, kind)
	local pr = self.Projs[id]
	if not pr then return end
	self.Projs[id] = nil
	if kind == "Knife" then
		pr.Part.CFrame = CFrame.lookAt(pos, pos - normal)
		Debris:AddItem(pr.Part, 6)
	else
		pr.Part:Destroy()
	end
end

function W:_stepProjectiles()
	local now = workspace:GetServerTimeNow()
	for id, pr in self.Projs do
		local t = now - pr.T0
		if t > 12 then
			pr.Part:Destroy()
			self.Projs[id] = nil
		elseif t >= 0 then
			local pos = pr.Origin + pr.Vel * t + Vector3.new(0, -0.5 * pr.G * t * t, 0)
			local v = pr.Vel + Vector3.new(0, -pr.G * t, 0)
			pr.Part.CFrame = CFrame.lookAt(pos, pos + v)
		end
	end
end

-- ---------------------------------------------------------------- lifecycle
-- Locked = every action key is ignored (match countdown, end of match). The HUD stays up.
function W:SetLocked(on)
	self.Locked = on
	if on then self.FireHeld, self.AdsHeld, self.ThrowHeld = false, false, {} end
end

function W:SetActive(a)
	self.Active = a
	self.Hud:SetEnabled(a)
	if not a then self.FireHeld, self.AdsHeld, self.ThrowHeld = false, false, {} end
end

-- state = result of Remotes.GetState
function W:Reset(state)
	self.RayIgnore = { player.Character, workspace.CurrentCamera } -- local tracers use the same pose-aware hitboxes as the server
	self.Inv, self.Rl, self.Busy, self.Act, self.GasZones = {}, nil, nil, nil, {}
	self.PeekCur, self.PeekAmt = 0, 0
	self.FireModeSel = {}
	self.Slots = { state.Slots.Primary, state.Slots.Secondary }
	self.Attach, self.Cfgs = state.Attach or {}, {}
	for _, name in self.Slots do self.Cfgs[name] = Armory.Build(name, self.Attach[name]) end -- same call the server makes
	self.Equip.Lethal = state.Lethal and { Name = state.Lethal.Name, Count = state.Lethal.Count } or nil
	self.Equip.Tactical = state.Tactical and { Name = state.Tactical.Name, Count = state.Tactical.Count } or nil
	self.Armor, self.Plates, self.C4Out = state.Armor, state.Plates, 0
	self.Perks = {}
	for _, n in state.Perks do self.Perks[n] = true end
	self.Hud:SetPerks(state.Perks)
	if state.Profile then self.Hud:SetXP(state.Profile.Level, state.Profile.Into, state.Profile.Needed) end
	self.Movement.TacTimeMult = self:_perk("DoubleTime") and PV.DoubleTime or 1
	self.FlashT, self.StunT, self.GasT, self.StimT, self.DamageT = 0, 0, 0, 0, 0
	self.Downed, self.Target = false, nil
	self.Movement.Downed = false
	self.Hud:SetDown(false)
	self.Hud:SetPrompt(nil)
	for _, pr in self.Projs do pr.Part:Destroy() end
	self.Projs = {}
	BulletFX.Clear()
	self:SetActive(true)
	self.Index = 0
	self:Equip(1, true)
end

function W:Equip(i, force)
	if not self.LadderEquipping then self.LadderRestore = nil end -- a weapon the player chose cancels "put the old gun back"
	if self.Busy and self.Busy.Kind ~= "Plate" and not force then return end
	local name = self.Slots[i]
	if not name then return end
	if self.Downed and not force and not self:_downAllowed(name) then return end
	if not force and (i == self.Index or self.EquipLock > 0.15) then return end
	if self.Busy and self.Busy.Kind == "Plate" then self:_cancelPlate() end
	local cfg = self.Cfgs and self.Cfgs[name] or Config.Weapons[name]
	self.Index, self.Name, self.Cfg = i, name, cfg
	self.Inv[name] = self.Inv[name] or { Ammo = cfg.MagSize, Reserve = cfg.Reserve }
	self.Rl, self.Busy = nil, nil
	self.VM:CancelGunAnim()
	self.Ads, self.AdsEased, self.ShotIndex, self.Bloom, self.CycleT = 0, 0, 0, 0, 0
	self.EquipLock = cfg.EquipTime * (self:_perk("Amped") and PV.AmpedEquip or 1)
	self.VM:SetGun(name, cfg, self.Attach and self.Attach[name])
	self.VM:PlayEquip()
	self.BreathLeft = cfg.Scope and cfg.Scope.Breath or 0
	self:_clearAct()
	Remotes.Equip:FireServer(name)
	self:_updateHud()
end

-- ---------------------------------------------------------------- reload
function W:Reload()
	local cfg, inv = self.Cfg, self.Inv[self.Name]
	if not cfg or cfg.MagSize <= 0 or self.Rl or self.Busy or self.EquipLock > 0 or self.CycleT > 0 then return end
	if inv.Ammo >= cfg.MagSize or inv.Reserve <= 0 then return end
	local G = self.VM.G
	local perk = self:_perk("FastHands") and PV.FastHands or 1
	if cfg.ReloadStyle == "Shell" then
		local dur = cfg.ReloadStart * perk
		self.Rl = { Style = "Shell", Stage = "Start", T = 0, Dur = dur }
		local a = Anim.Shell(G, "Start")
		a.Kind = "Shell"
		self.VM:PlayGunAnim(a, dur)
		self:_act("ShellStart", "", dur)
	else
		local empty = inv.Ammo == 0
		local total = (empty and cfg.ReloadEmptyTime or cfg.ReloadTime) * perk
		self.Rl = { Style = cfg.ReloadStyle, Stage = "Main", T = 0, Total = total, Empty = empty, Filled = false,
			InsertAt = Anim.InsertAt(cfg.ReloadStyle, empty) }
		local a = Anim.Reload(G, cfg.ReloadStyle, empty)
		a.Kind = "Reload"
		self.VM:PlayGunAnim(a, total)
		self:_act(empty and "ReloadEmpty" or "Reload", "", total)
	end
	Remotes.Reload:FireServer()
end

function W:_cancelReload()
	if not self.Rl then return end
	if self.Rl.Style == "Shell" then Remotes.Reload:FireServer("Cancel") end
	self.Rl = nil
	self.VM:CancelGunAnim()
	self:_clearAct()
end

function W:_updateReload(dt)
	local rl, cfg, inv = self.Rl, self.Cfg, self.Inv[self.Name]
	rl.T += dt
	if rl.Stage == "Main" then
		if not rl.Filled and rl.T / rl.Total >= rl.InsertAt then
			local take = math.min(cfg.MagSize - inv.Ammo, inv.Reserve)
			inv.Ammo += take
			inv.Reserve -= take
			rl.Filled = true
			self:_updateHud()
		end
		if rl.T >= rl.Total then
			self.Rl = nil
			self:_clearAct()
		end
		return
	end
	-- shell by shell
	local perk = self:_perk("FastHands") and PV.FastHands or 1
	if rl.Stage == "Start" and rl.T >= rl.Dur then
		rl.Stage, rl.T, rl.Dur = "Load", 0, cfg.ShellTime * perk
		local a = Anim.Shell(self.VM.G, "Load")
		a.Kind = "Shell"
		self.VM:PlayGunAnim(a, rl.Dur)
		self:_act("ShellLoad", "", rl.Dur)
	elseif rl.Stage == "Load" and rl.T >= rl.Dur then
		inv.Ammo += 1
		inv.Reserve -= 1
		self:_updateHud()
		if inv.Ammo >= cfg.MagSize or inv.Reserve <= 0 then
			rl.Stage, rl.T, rl.Dur = "End", 0, cfg.ReloadEnd * perk
			local a = Anim.Shell(self.VM.G, "End")
			a.Kind = "Shell"
			self.VM:PlayGunAnim(a, rl.Dur)
			self:_act("ShellEnd", "", rl.Dur)
		else
			rl.T = 0
			local a = Anim.Shell(self.VM.G, "Load")
			a.Kind = "Shell"
			self.VM:PlayGunAnim(a, rl.Dur)
			self:_act("ShellLoad", "", rl.Dur)
		end
	elseif rl.Stage == "End" and rl.T >= rl.Dur then
		self.Rl = nil
		self:_clearAct()
	end
end

-- ---------------------------------------------------------------- spread
function W:GetSpread()
	local cfg, mv = self.Cfg, self.Movement
	local S = cfg.Spread
	local s = S.Hip + (S.Ads - S.Hip) * self.AdsEased
	s += S.Move * math.clamp(mv.Speed / Config.Movement.WalkSpeed, 0, 1.5) * (1 - 0.7 * self.AdsEased)
	if not mv.Grounded then s += S.Air end
	if mv.Prone then s *= (mv.DropShot > 0 and Config.Movement.DropShotSpread or Config.Movement.ProneSpread) -- drop shot: tightest, for a moment
	elseif mv.Crouched then s *= 0.75 end
	if self:_perk("SteadyAim") then s = s * (1 - self.AdsEased) * PV.SteadyAim + s * self.AdsEased end
	if self.HoldingBreath then s *= 0.3 end
	return s + self.Bloom
end

function W:GetSpeedMult()
	if not self.Cfg then return 1 end
	return self.SpeedMult
end

-- ---------------------------------------------------------------- firing
function W:_fire(now)
	local cfg, inv, mv = self.Cfg, self.Inv[self.Name], self.Movement
	if inv.Ammo <= 0 then
		self.NextFire, self.SemiBuffer = now + 0.2, 0
		self:Reload()
		return
	end
	inv.Ammo -= 1

	local interval = 60 / cfg.RPM
	local base = (now - self.NextFire > 0.1) and now or self.NextFire
	self.NextFire = base + interval
	if self:_mode() == "Semi" then self.SemiBuffer = 0 end

	local cf = self.Cam.CFrame
	local spread = self:GetSpread()
	local dirs = {}
	for i = 1, cfg.Pellets or 1 do dirs[i] = spreadDir(cf, spread) end
	Remotes.Fire:FireServer(self.Name, cf.Position, dirs)

	if not cfg.Projectile then
		local muzzle = self.VM:GetMuzzleCFrame().Position
		local bal = Ballistics.For(cfg)
		if bal then
			-- real bullet: same origin / velocity the server gets, so the tracer flies the path the server simulates
			local vels = {}
			for i, d in dirs do vels[i] = d * bal.Speed end
			local style = player:GetAttribute("CosTracer")
			BulletFX.Spawn({
				Origin = cf.Position, Muzzle = muzzle, Vels = vels, G = bal.Gravity, K = bal.Drag, T0 = workspace:GetServerTimeNow(),
				Range = cfg.Range, Style = style, Ignore = self.RayIgnore, Pen = Penetration.PowerOf(cfg),
				OnImpact = function(pos, normal) impact(pos, normal, TracerFX.Color(style)) end,
			})
		else
			local color = TracerFX.Color(player:GetAttribute("CosTracer"))
			local power = Penetration.PowerOf(cfg)
			for i, d in dirs do
				if i > 3 then break end
				-- same walls / bodies the server ray goes through; a bullet hole on every surface it enters, leaves or ends on
				local e = Penetration.Trace(cf.Position, d * cfg.Range, table.clone(self.RayIgnore), Penetration.New(power), hitscanFX, color)
				tracer(muzzle, e, player)
			end
		end
	end
	playSound(cfg.Sounds and cfg.Sounds.Fire, 0.7)

	if now - self.LastShot > cfg.Recoil.Reset then self.ShotIndex = 0 end
	self.ShotIndex += 1
	self.LastShot = now
	local pat = cfg.Recoil.Pattern
	local p = pat[math.min(self.ShotIndex, #pat)]
	local mult = 1 - (1 - cfg.Recoil.AdsMult) * self.AdsEased
	if mv.Prone then mult *= (mv.DropShot > 0 and Config.Movement.DropShotRecoil or Config.Movement.ProneRecoil)
	elseif mv.Crouched then mult *= 0.85 end
	if self.HoldingBreath then mult *= 0.6 end
	local j = cfg.Recoil.Jitter
	self.Cam:AddRecoil((p.X + (math.random() - 0.5) * j) * mult, (p.Y + (math.random() - 0.5) * j) * mult)
	self.VM:Kick(cfg.Kick, self.AdsEased)
	self.VM:MuzzleFlash()
	self.Bloom = math.min(self.Bloom + cfg.Spread.PerShot, cfg.Spread.MaxBloom)

	if cfg.Cycle and inv.Ammo > 0 then
		self.CycleT, self.CycleDrop = cfg.Cycle.Time, cfg.Cycle.DropAds
		local kind = cfg.Model == "Pump" and "Pump" or "Bolt"
		local a = Anim.Cycle(self.VM.G, kind)
		a.Kind = kind
		self.VM:PlayGunAnim(a, cfg.Cycle.Time)
		self:_act(kind, "", cfg.Cycle.Time)
	end
	self:_updateHud()
end

-- ---------------------------------------------------------------- melee
function W:_beginBusy(kind, dur, track, item, color, actName, extra)
	local b = { Kind = kind, T = 0, Dur = dur, Sent = false }
	if extra then for k, v in extra do b[k] = v end end
	self.Busy = b
	self:_cancelReload()
	self.VM:StartTrack(track, dur, item, color)
	self:_act(actName, item, dur)
	return b
end

function W:QuickMelee()
	local now = os.clock()
	if self.Busy or self.EquipLock > 0.1 or now < self.MeleeNext or not self.Cfg or self.Cfg.Class == "Melee" or self.Downed then return end
	local M = Config.QuickMelee
	self.MeleeNext = now + M.Cooldown
	self.AdsHeld = false
	self:_beginBusy("Bash", M.Time, "Bash", nil, nil, "Bash", { HitAt = M.HitAt, Attack = "Quick" })
end

function W:MeleeAttack(kind)
	local cfg, now = self.Cfg, os.clock()
	if self.Busy or self.EquipLock > 0.1 or now < self.MeleeNext or not cfg or cfg.Class ~= "Melee" or self.Downed then return end
	local atk = cfg.Melee[kind]
	self.MeleeNext = now + atk.Time
	local track
	if kind == "Heavy" then
		track = cfg.Model == "Hammer" and "Smash" or "Lunge"
	else
		self.SwingSide = not self.SwingSide
		track = self.SwingSide and "SwingR" or "SwingL"
	end
	self:_beginBusy("Swing", atk.Time, track, nil, nil, track, { HitAt = atk.HitAt, Attack = kind })
	if atk.Lunge and self.Movement.Root then
		local look = self.Cam.CFrame.LookVector
		self.Movement.Root.AssemblyLinearVelocity += Vector3.new(look.X, 0, look.Z).Unit * atk.Lunge
	end
	self.Cam:AddShake(Vector3.new(-0.12, 0, 0.1))
end

-- ---------------------------------------------------------------- equipment
function W:UseEquipment(slot)
	local e = self.Equip[slot]
	local def = e and Config.Equipment[e.Name]
	if not def or self.Busy or self.EquipLock > 0.1 or self.Downed then return end
	if e.Count <= 0 then
		self.Hud:Toast("NO " .. def.Label:upper(), Theme.Warn)
		return
	end
	self.AdsHeld = false
	local mult = self:_perk("Amped") and PV.AmpedUse or 1
	if def.Mode == "Throw" then
		self:_beginBusy("Throw", def.PullTime * mult, "Pull", def.Item, def.Color, "Pull",
			{ Slot = slot, Def = def, Phase = "Pull", Mult = mult })
		Remotes.EquipBegin:FireServer(slot)
	elseif def.Mode == "Use" then
		local track = def.Effect == "Sensor" and "Sensor" or "Use"
		self:_beginBusy("Use", def.UseTime * mult, track, def.Item, def.Color, track, { Slot = slot, Def = def })
	elseif def.Mode == "Plant" then
		self:_beginBusy("Plant", def.UseTime * mult, "Plant", def.Item, def.Color, "Plant", { Slot = slot, Def = def })
	end
end

function W:_consume(slot)
	local e = self.Equip[slot]
	if e then e.Count = math.max(0, e.Count - 1) end
	self:_updateHud()
end

function W:_endBusy()
	self.Busy = nil
	self.VM:EndTrack()
	self:_clearAct()
	self.Hud:SetProgress(nil, nil)
end

function W:Plate()
	local b = self.Busy
	if b and b.Kind == "Plate" then self:_cancelPlate() return end
	if b or self.EquipLock > 0.1 or self.Downed then return end
	if self.Plates <= 0 then
		self.Hud:Toast("NO ARMOR PLATES", Theme.Warn)
		return
	elseif self.Armor >= Config.Armor.PlateArmor * Config.Armor.MaxEquipped then
		self.Hud:Toast("ARMOR FULL", Theme.Plate)
		return
	end
	self.AdsHeld = false
	local dur = Config.Armor.ApplyTime * (self:_perk("QuickFix") and PV.QuickFixPlate or 1)
	self:_beginBusy("Plate", dur, "Plate", "Plate", nil, "Plate")
	Remotes.PlateStart:FireServer()
end

function W:_cancelPlate()
	Remotes.PlateCancel:FireServer()
	self:_endBusy()
end

function W:_updateBusy(dt)
	local b = self.Busy
	b.T += dt
	local cam = self.Cam
	if b.Kind == "Throw" then
		local def = b.Def
		if b.Phase == "Pull" and b.T >= b.Dur then
			b.Phase, b.T = "Hold", 0
			self.VM:StartTrack("Hold", nil, def.Item, def.Color)
			self:_act("Hold", def.Item, 0)
		end
		if b.Phase == "Hold" then
			if def.Cook and def.Fuse then
				self.Hud:SetProgress("Cooking", b.T / def.Fuse, Color3.fromRGB(255, 160, 60))
				if b.T >= def.Fuse then -- cooked off in hand
					self:_consume(b.Slot)
					self:_endBusy()
					return
				end
			end
			if not self.ThrowHeld[b.Slot] then
				b.Phase, b.T, b.Dur = "Throw", 0, def.ThrowTime * b.Mult
				self.Hud:SetProgress(nil, nil)
				self.VM:StartTrack("Throw", b.Dur, def.Item, def.Color)
				self:_act("Throw", def.Item, b.Dur)
			end
		elseif b.Phase == "Throw" then
			if not b.Sent and b.T >= b.Dur * 0.45 then
				b.Sent = true
				local cf = cam.CFrame
				Remotes.EquipThrow:FireServer(b.Slot, cf.Position, (cf.LookVector + Vector3.new(0, 0.1, 0)).Unit)
				self.VM:DropItem()
				self:_consume(b.Slot)
			end
			if b.T >= b.Dur then self:_endBusy() end
		end
	elseif b.Kind == "Use" or b.Kind == "Plant" then
		if not b.Sent and b.T >= b.Dur * b.Def.UseAt then
			b.Sent = true
			local cf = cam.CFrame
			if b.Kind == "Use" then Remotes.EquipUse:FireServer(b.Slot) else Remotes.EquipPlace:FireServer(b.Slot, cf.Position, cf.LookVector) end
			self.VM:DropItem()
			self:_consume(b.Slot)
		end
		if b.T >= b.Dur then self:_endBusy() end
	elseif b.Kind == "Plate" then
		self.Hud:SetProgress("Applying plate", b.T / b.Dur, Color3.fromRGB(120, 190, 255))
		if b.T >= b.Dur then self:_endBusy() end
	elseif b.Kind == "Interact" then
		local tc = b.Target.Character
		local tr = tc and tc:FindFirstChild("HumanoidRootPart")
		local root = self.Movement.Root
		if self.Downed or not self.InteractHeld or not tc or not tc:GetAttribute("Down") or not tr or not root
			or (tr.Position - root.Position).Magnitude > Config.Down.InteractRange + 3 then
			Remotes.Interact:FireServer("Cancel")
			self:_endBusy()
			return
		end
		self.Hud:SetProgress(b.Label, b.T / b.Dur, b.Color)
		if b.T >= b.Dur then self:_endBusy() end
	elseif b.Kind == "Bash" or b.Kind == "Swing" then
		if not b.Sent and b.T >= b.Dur * b.HitAt then
			b.Sent = true
			local cf = cam.CFrame
			Remotes.Melee:FireServer(b.Attack, cf.Position, cf.LookVector)
		end
		if b.T >= b.Dur then self:_endBusy() end
	end
end

-- ---------------------------------------------------------------- downed state + revive / finish
function W:_downAllowed(name)
	local cfg = name and Config.Weapons[name]
	return cfg ~= nil and Config.Down.AllowedClasses[cfg.Class] == true
end

function W:_setDowned(state, health, drain)
	if state then
		local first = not self.Downed
		self.Downed, self.DownHealth, self.DownDrain = true, health, drain
		self.Movement.Downed = true
		if first then
			self.AdsHeld, self.Target = false, nil
			if self.Busy then
				if self.Busy.Kind == "Plate" then Remotes.PlateCancel:FireServer() end
				self:_endBusy()
			end
			if not self:_downAllowed(self.Name) then
				for i, n in self.Slots do
					if self:_downAllowed(n) then
						self:Equip(i, true)
						break
					end
				end
			end
			self.Hud:SetDown(true)
		end
	else
		self.Downed = false
		self.Movement.Downed = false
		self.Hud:SetDown(false)
		self.Hud:Toast("REVIVED", Theme.Good)
	end
end

function W:_scanInteract()
	local mv = self.Movement
	local root = mv.Root
	if mv.Ladder then
		mv.InteractTaken = false
		self.Target = nil
		if not self.Busy then
			local keys = InputMap.Device == "PAD" and "MOVE STICK UP / DOWN" or ("%s / %s"):format(keyName("MoveForward"), keyName("MoveBack"))
			self.Hud:SetPrompt(("[%s]  CLIMB     [%s]  LET GO"):format(keys, keyName("Jump")))
		end
		return
	end
	if not root or self.Busy then
		if not self.Busy then self.Hud:SetPrompt(nil) end
		return
	end
	local best, bd = nil, Config.Down.InteractRange
	for _, p in Players:GetPlayers() do
		local c = p ~= player and p.Character
		if c and c:GetAttribute("Down") then
			local r = c:FindFirstChild("HumanoidRootPart")
			local d = r and (r.Position - root.Position).Magnitude
			if d and d < bd then best, bd = p, d end
		end
	end
	self.Target = best
	if best then
		local ally = player.Team ~= nil and player.Team == best.Team
		if ally then
			self.Hud:SetPrompt(("HOLD [%s]  REVIVE  %s"):format(keyName("Interact"), best.DisplayName))
		elseif Config.Down.AllowFinish then
			self.Hud:SetPrompt(("HOLD [%s]  FINISH  %s"):format(keyName("Interact"), best.DisplayName))
		else
			self.Target = nil
			self.Hud:SetPrompt(nil)
		end
	else
		self.Hud:SetPrompt(mv.LadderPrompt and ("[%s]  CLIMB LADDER"):format(keyName("Interact")) or nil)
	end
	mv.InteractTaken = self.Target ~= nil -- Interact is revive / finish while a downed player is in reach, not "climb"
end

-- Ladders (Movement.luau drives the climb). The hands are on the ladder, so the gun is tucked away. Aiming or firing pulls the PISTOL
-- (the secondary; any other gun if the loadout has no pistol) and Movement pauses the climb until the player stops; when the ladder is
-- left, the gun that was drawn before comes back.
function W:_ladderUpdate()
	local mv = self.Movement
	mv.LadderBlocked = self.Busy ~= nil or self.Locked == true
	mv.LadderHold = self.Rl ~= nil or self.CycleT > 0 -- reloading / cycling the pistol keeps the climb paused too
	local on = mv.Ladder ~= nil
	if on and not self.WasOnLadder then
		self.WasOnLadder = true
		self.MeleeNext = math.max(self.MeleeNext, os.clock() + 0.2)
		if self.Rl then self:_cancelReload() end
	elseif not on and self.WasOnLadder then
		self.WasOnLadder = false
		if self.LadderRestore then self.LadderRestoreT = 2 end
	end
	if on then
		if (self.AdsHeld or self.FireHeld) and not self.Busy and not self.Downed and not self:_downAllowed(self.Name) then
			local idx
			for i = 2, 1, -1 do
				if self:_downAllowed(self.Slots[i]) then idx = i break end
			end
			if idx and idx ~= self.Index then
				local prev = self.Index
				self.LadderEquipping = true
				self:Equip(idx)
				self.LadderEquipping = false
				if self.Index == idx then self.LadderRestore = self.LadderRestore or prev end
			end
		end
	elseif self.LadderRestore then
		local want = self.LadderRestore
		self.LadderRestoreT = (self.LadderRestoreT or 2) - 1 / 60
		if self.Index == want or self.Downed or self.LadderRestoreT <= 0 or self.Locked then
			self.LadderRestore = nil
		elseif not (self.Busy or self.Rl) then
			self.LadderEquipping = true
			self:Equip(want)
			self.LadderEquipping = false
			if self.Index == want then self.LadderRestore = nil end
		end
	end
end

function W:TryInteract()
	local target = self.Target
	if not target or self.Busy or self.Downed or self.EquipLock > 0.1 then return end
	local ally = player.Team ~= nil and player.Team == target.Team
	local dur = ally and Config.Down.ReviveTime or Config.Down.FinishTime
	Remotes.Interact:FireServer("Start", target)
	self:_beginBusy("Interact", dur, "Plant", nil, nil, "Plant",
		{ Target = target, Label = ally and "Reviving" or "Finishing", Color = ally and Theme.Good or Theme.Danger })
	self.Hud:SetPrompt(nil)
end

-- ---------------------------------------------------------------- per frame
function W:Update(dt)
	if not self.Active or not self.Cfg then return end
	self:_ladderUpdate() -- may swap the gun, so it runs before the config is read
	local cfg, inv, mv = self.Cfg, self.Inv[self.Name], self.Movement
	local melee = cfg.Class == "Melee"
	local now = os.clock()

	self.EquipLock = math.max(0, self.EquipLock - dt)
	self.Bloom = math.max(0, self.Bloom - cfg.Spread.Recover * dt)
	self.CycleT = math.max(0, self.CycleT - dt)

	if self.Downed then
		self.DownHealth = math.max(0, self.DownHealth - self.DownDrain * dt)
		self.Hud:SetDownBar(self.DownHealth / Config.Down.Health)
		self.Hud:SetPrompt(nil)
	else
		self:_scanInteract()
	end

	if self.Busy then self:_updateBusy(dt) end
	if self.Rl then
		if cfg.ReloadStyle == "Shell" and self.FireHeld and inv.Ammo > 0 and self.Rl.Stage ~= "Start" then
			self:_cancelReload()
		else
			self:_updateReload(dt)
		end
	end

	-- status effects
	self.FlashT = math.max(0, self.FlashT - dt)
	self.StunT = math.max(0, self.StunT - dt)
	self.StimT = math.max(0, self.StimT - dt)
	self.DamageT = math.max(0, self.DamageT - dt * 1.2)
	if self.FlashT <= 0 then self.FlashMax = 1 end
	if self.StunT <= 0 then self.StunMax = 1 end
	local root = mv.Root
	local inGas = false
	for i = #self.GasZones, 1, -1 do
		local z = self.GasZones[i]
		if now > z.Expire then table.remove(self.GasZones, i)
		elseif root and (root.Position - z.Pos).Magnitude < z.Radius then inGas = true end
	end
	local gasRate = self:_perk("BattleHardened") and PV.BattleHardened or 1
	self.GasT = math.clamp(self.GasT + (inGas and dt * 1.5 or -dt * 0.8), 0, 1)
	if self.GasT > 0.3 and now > self.CoughT then
		self.CoughT = now + 0.9
		self.Cam:AddShake(Vector3.new(-0.5 * gasRate, 0, (math.random() - 0.5) * 0.4) * self.GasT)
	end
	if self.StunT > 0 and math.random() < dt * 12 then
		self.Cam:AddShake(Vector3.new((math.random() - 0.5) * 0.35, (math.random() - 0.5) * 0.3, (math.random() - 0.5) * 0.5))
	end
	self.Hud:SetOverlay("Flash", 1 - math.clamp(self.FlashT / math.max(self.FlashMax, 0.01) * 1.5, 0, 1) * (self.FlashT > 0 and 1 or 0))
	self.Hud:SetOverlay("Stun", 1 - math.clamp(self.StunT / math.max(self.StunMax, 0.01), 0, 1) * 0.55)
	self.Hud:SetOverlay("Gas", 1 - self.GasT * 0.45 * gasRate)
	self.Hud:SetOverlay("Damage", 1 - math.clamp(self.DamageT, 0, 0.8))

	-- movement multipliers
	local plating = self.Busy and self.Busy.Kind == "Plate"
	mv.GlobalMult = (self.StimT > 0 and self.StimMult or 1) * (self.StunT > 0 and 0.6 or 1) * (self.GasT > 0.3 and 0.85 or 1)
	mv.SprintBlocked = self.AdsHeld or self.FireHeld or self.Rl ~= nil or self.Busy ~= nil or self.StunT > 0
	mv.Engaged = self.AdsHeld or self.FireHeld -- going prone while this is true is a drop shot (Movement.luau)

	if mv.IsSprinting then self.SprintLock = cfg.SprintOutTime else self.SprintLock = math.max(0, self.SprintLock - dt) end

	-- ADS (melee has none)
	local ladderOk = not mv.Ladder or self:_downAllowed(self.Name) or not (self:_downAllowed(self.Slots[1]) or self:_downAllowed(self.Slots[2])) -- on a ladder only the pistol (if there is one)
	local canAds = self.AdsHeld and ladderOk and not melee and not self.Rl and not self.Busy and not mv.IsSprinting and not mv.Diving and not mv.Mantle
		and self.EquipLock < 0.2 and not (self.CycleT > 0 and self.CycleDrop) and self.StunT <= 0
	self.Ads = approach(self.Ads, canAds and 1 or 0, dt / cfg.AdsTime)
	self.AdsEased = self.Ads * self.Ads * (3 - 2 * self.Ads)

	-- corner peek: Q / E lean the body out while aiming (both keys together cancel). Only while grounded, upright and really aiming.
	do
		local P = Config.Camera.Peek
		local dir = (InputMap.IsDown("PeekRight") and 1 or 0) - (InputMap.IsDown("PeekLeft") and 1 or 0)
		local ok = canAds and self.Ads >= P.MinAds and mv.Grounded and not self.Downed and mv.State ~= "Slide" and not mv.Prone
		self.PeekCur = approach(self.PeekCur, ok and dir or 0, dt / P.Time)
		local a = math.abs(self.PeekCur)
		self.PeekAmt = (self.PeekCur < 0 and -1 or 1) * a * a * (3 - 2 * a)
	end
	self.SpeedMult = cfg.MoveMult * (1 - (1 - cfg.AdsMoveMult) * self.AdsEased) * (plating and Config.Armor.MoveMult or 1)

	-- scope + hold breath
	self.Scoped = cfg.Scope ~= nil and self.AdsEased > 0.92
	local maxBreath = cfg.Scope and cfg.Scope.Breath or 0
	self.BreathRest = math.max(0, self.BreathRest - dt)
	if self.Scoped and InputMap.IsDown("HoldBreath") and self.BreathLeft > 0 and self.BreathRest <= 0 then
		self.HoldingBreath = true
		self.BreathLeft -= dt
		if self.BreathLeft <= 0 then self.BreathRest = 1.5 end
	else
		self.HoldingBreath = false
		self.BreathLeft = math.min(maxBreath, self.BreathLeft + dt * 0.8)
	end
	local vp = workspace.CurrentCamera.ViewportSize
	self.Hud:SetScope(self.Scoped and cfg.Scope.Overlay == true, vp)
	self.VM:SetHidden(self.Scoped and cfg.Scope.Overlay == true)
	if self.Scoped and not self.Busy then
		self.Hud:SetProgress("Holding breath", self.BreathLeft / maxBreath, Color3.fromRGB(200, 220, 255))
	elseif not self.Busy then
		self.Hud:SetProgress(nil, nil)
	end

	self.HideMag = cfg.ReloadStyle == "Rocket" and inv.Ammo <= 0

	-- fire
	if not melee then
		local wantFire = self.FireHeld and (self:_mode() == "Auto" or now < self.SemiBuffer)
		local canFire = not self.Rl and not self.Busy and self.EquipLock <= 0 and self.SprintLock <= 0
			and mv.Alpha.Sprint < 0.35 and self.CycleT <= 0 and self.StunT <= 0 and not mv.Diving and not mv.Mantle and ladderOk
			and (not self.Downed or self:_downAllowed(self.Name))
		if wantFire and canFire and now >= self.NextFire then self:_fire(now) end
	end

	-- crosshair
	local spread = self:GetSpread()
	local gap = (vp.Y / 2) * math.tan(math.rad(spread)) / math.tan(math.rad(self.Cam.Fov / 2)) + 4
	local ct = melee and 1 or math.clamp(self.AdsEased * 1.5, 0, 1)
	self.Hud:UpdateCrosshair(gap, ct)

	self.Hud:SetCompass(workspace.CurrentCamera.CFrame.LookVector)
	local hum = mv.Humanoid
	if hum then self.Hud:SetHealth(hum.Health, hum.MaxHealth) end
	self.Hud:SetDebug(Config.Debug and ("%s   %.1f st/s"):format(mv.State, mv.Speed) or "")

	self:_stepProjectiles()

	-- replicate pose / action to the server (third-person animation for other players)
	-- a mantle / vault also sends where the ledge is and how far along the climb is, so other clients can plant its hands and feet on it
	local climbing = mv.Mantle ~= nil
	if climbing ~= self.WasClimbing then self.WasClimbing, self.SyncT = climbing, 1 end -- a climb is short: send its first frame (and its end) at once
	self.SyncT += dt
	if self.SyncT >= 0.08 then
		self.SyncT = 0
		local a = self.Act
		local elapsed = a and (now - a.Start) or 0
		local m = mv.Mantle
		local climb = m and m.Ledge and { Ledge = m.Ledge, Depth = m.Depth or 0, Elapsed = m.T, Dur = m.Dur } or nil
		Remotes.StateSync:FireServer(mv.State == "Ladder" and "Air" or mv.State, self.Cam.Pitch, self.AdsEased, self.Name, a and a.Name or "", a and a.Item or "", elapsed, a and a.Dur or 0, self.PeekAmt, climb)
	end
end

return W
