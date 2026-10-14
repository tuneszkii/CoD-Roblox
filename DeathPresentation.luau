-- DeathPresentation: what you see when you die and when you spawn.
--
-- DEATH   (OnLocalDeath the moment your humanoid dies, then the server's "Death" message adds who / what / how far)
--   0.0 s  red edges, the world drains of colour and blurs, your view tilts and drops as you fall
--   0.9 s  KILLCAM: you watch through the killer's eyes for a few seconds (smoothed from the aim they replicate), "YOU WERE KILLED BY <name>"
--          with their player card, weapon, distance and headshot. No killer (fall, own grenade ...) = "YOU DIED" and a slow orbit round your body.
--   end    a respawn bar counts down; the screen fades to black just before you spawn.
--   Modes without respawns (Down and Out): after the killcam you spectate teammates (Fire = next player) until the round ends.
-- SPAWN   ("Spawned" from the server)
--   fade in from black, colour comes back, and a blue edge glow + "SPAWN PROTECTION" bar shows the invulnerability window.
--   (During the match intro the intro presentation owns the screen, so only the death state is cleared.)
--
-- hooks = { RigActive = function() -> bool, ViewCF = function() -> CFrame? (the current first-person view, nil when there is none) }
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Theme = require(script.Parent.Theme)
local Widgets = require(script.Parent.Widgets)
local InputMap = require(script.Parent.InputMap)
local MatchClient = require(script.Parent.MatchClient)
local PlayerCard = require(script.Parent.PlayerCard)
local ScreenFX = require(script.Parent.ScreenFX)
local CineCam = require(script.Parent.CineCam)
local UISound = require(script.Parent.UISound)

local DeathPresentation = {}
DeathPresentation.__index = DeathPresentation

local LEFT, CENTER = Enum.TextXAlignment.Left, Enum.TextXAlignment.Center
local player = Players.LocalPlayer
local FALL = 0.9                    -- seconds of "falling" before the killcam
local STUDS_TO_METERS = 0.28
local RED = Color3.fromRGB(190, 20, 20)

local function clamp01(x) return math.clamp(x, 0, 1) end
local function smooth(x) x = clamp01(x) return x * x * (3 - 2 * x) end
local function lerpAngle(a, b, k)
	local d = (b - a + math.pi) % (2 * math.pi) - math.pi
	return a + d * k
end

local function group(parent, size, pos, anchor)
	local g = Instance.new("CanvasGroup")
	g.BackgroundTransparency, g.BorderSizePixel = 1, 0
	g.Size, g.Position, g.AnchorPoint, g.GroupTransparency = size, pos, anchor or Vector2.zero, 1
	g.Parent = parent
	return g
end

local function kickerFor(p)
	if p.KillerName then
		if p.Kind == "Finisher" then return "YOU WERE FINISHED BY" end
		if p.Kind == "Bleed" then return "YOU BLED OUT  -  DOWNED BY" end
		return "YOU WERE KILLED BY"
	end
	if p.Kind == "Bleed" then return "YOU BLED OUT" end
	return "YOU DIED"
end

local function detailFor(p)
	local parts = {}
	local w = p.Weapon
	if w and w ~= "" and w ~= "Bleed" and w ~= "Finisher" then table.insert(parts, Theme.Spaced(w)) end
	if p.Kind == "Finisher" then table.insert(parts, "FINISHER") end
	if p.Kind == "Bullet" and p.Dist and p.Dist >= 3 then table.insert(parts, ("%d M"):format(math.floor(p.Dist * STUDS_TO_METERS))) end
	if p.Head then table.insert(parts, '<font color="rgb(235,70,70)">HEADSHOT</font>') end
	return table.concat(parts, "   |   ")
end

-- ---------------------------------------------------------------- build
function DeathPresentation.new(hooks)
	local self = setmetatable({ Hooks = hooks }, DeathPresentation)
	local gui = Instance.new("ScreenGui")
	gui.Name, gui.ResetOnSpawn, gui.IgnoreGuiInset, gui.DisplayOrder = "DeathHud", false, true, 7
	gui.Parent = player:WaitForChild("PlayerGui")
	local root = Widgets.ScaledRoot(gui, function() return InputMap.Device == "Touch" and 540 or 800 end, "Interface.HudScale")
	self.Gui, self.Root = gui, root

	-- who killed you (top centre)
	local banner = group(root, UDim2.fromOffset(700, 120), UDim2.new(0.5, 0, 0.1, 0), Vector2.new(0.5, 0))
	self.Banner = banner
	self.Kicker = Theme.Label(banner, "", 20, Theme.Dim, CENTER, Theme.Display, UDim2.fromOffset(0, 0), UDim2.new(1, 0, 0, 26))
	self.KillerName = Theme.Label(banner, "", 58, Theme.Danger, CENTER, Theme.Display, UDim2.fromOffset(0, 26), UDim2.new(1, 0, 0, 66))
	self.Detail = Theme.Label(banner, "", 20, Theme.Text, CENTER, Theme.Display, UDim2.fromOffset(0, 94), UDim2.new(1, 0, 0, 26))

	-- killer's player card (left)
	self.CardBox = group(root, UDim2.fromOffset(300, 110), UDim2.new(0, 50, 0.62, 0))
	self.Card = PlayerCard.Build(self.CardBox, 0.9, UDim2.fromOffset(0, 0))

	-- killcam tag (top left)
	self.CamTag = Theme.Label(root, '<font color="rgb(235,70,70)">[REC]</font>  KILLCAM', 20, Theme.Text, LEFT, Theme.Display, UDim2.new(0, 50, 0.1, 0), UDim2.fromOffset(200, 26))
	self.CamTag.Visible = false

	-- respawn countdown (bottom centre)
	local resp = group(root, UDim2.fromOffset(420, 80), UDim2.new(0.5, 0, 0.82, 0), Vector2.new(0.5, 0))
	self.Resp = resp
	self.RespLbl = Theme.Label(resp, "", 28, Theme.Accent, CENTER, Theme.Display, UDim2.fromOffset(0, 0), UDim2.new(1, 0, 0, 36))
	local back = Theme.Frame(resp, UDim2.fromOffset(320, 6), UDim2.new(0.5, 0, 0, 44), Vector2.new(0.5, 0), Color3.new(), 0.5)
	Theme.Round(back, 3)
	self.RespFill = Theme.Frame(back, UDim2.fromScale(0, 1), nil, nil, Theme.Accent, 0)
	Theme.Round(self.RespFill, 3)
	self.RespHint = Theme.Label(resp, "", 15, Theme.Dim, CENTER, Theme.Body, UDim2.fromOffset(0, 56), UDim2.new(1, 0, 0, 20))

	-- spawn protection (bottom centre)
	local shield = group(root, UDim2.fromOffset(320, 40), UDim2.new(0.5, 0, 0.86, 0), Vector2.new(0.5, 0))
	self.Shield = shield
	Theme.Label(shield, "SPAWN PROTECTION", 14, Theme.Plate, CENTER, Theme.Display, UDim2.fromOffset(0, 0), UDim2.new(1, 0, 0, 18))
	local sback = Theme.Frame(shield, UDim2.fromOffset(240, 5), UDim2.new(0.5, 0, 0, 24), Vector2.new(0.5, 0), Color3.new(), 0.5)
	Theme.Round(sback, 3)
	self.ShieldFill = Theme.Frame(sback, UDim2.fromScale(1, 1), nil, nil, Theme.Plate, 0)
	Theme.Round(self.ShieldFill, 3)

	MatchClient.OnEvent(function(kind, a)
		if kind == "Death" then self:_onDeath(a)
		elseif kind == "Spawned" then self:_onSpawned(a)
		elseif kind == "ProtectionEnd" then -- you fired: spawn protection is over
			self.Protect, self.Shield.GroupTransparency = nil, 1
			ScreenFX.Vignette(Theme.Plate, 0, 0.2)
		elseif kind == "Results" then self:_clearDead(false) end
	end)
	MatchClient.OnChanged(function()
		if MatchClient.Phase() ~= "Match" and (self.Dead or self.Protect) then
			self:_clearDead(false)
			self.Protect, self.Shield.GroupTransparency = nil, 1
		end
	end)
	InputMap.OnBegan("Fire", function() self:_cycleSpectate() end)
	RunService.Heartbeat:Connect(function(dt) self:_tick(dt) end)
	return self
end

-- ---------------------------------------------------------------- death
-- a view of the world from where you died, then from the killer's eyes, then (no respawn) from a teammate
local function deathShot(self, d)
	return {
		In = 0.2, Out = 0.5, fov = 70,
		Update = function(t, dt)
			local startCF = d.StartCF
			if t < FALL then -- the world tilts and drops as you fall
				local k = smooth(t / FALL)
				return startCF * CFrame.new(0, -1.2 * k, 0) * CFrame.Angles(0, 0, math.rad(24) * k)
			end

			local spectating = d.P ~= nil and d.P.Delay == false and t >= d.KillcamEnd
			if spectating then
				local spec = self:_spectateTarget(d)
				local root = spec and spec.Character and spec.Character:FindFirstChild("HumanoidRootPart")
				if root then
					local look = root.CFrame.LookVector
					local focus = root.Position + Vector3.new(0, 1.6, 0)
					local pos = focus - look * 5.5 + Vector3.new(0, 1.8, 0)
					d.SpecPos = d.SpecPos and d.SpecPos:Lerp(pos, 1 - math.exp(-8 * dt)) or pos
					return CFrame.lookAt(d.SpecPos, focus + look * 8), 70
				end
			elseif d.Killer then -- the killer's view
				local kc = d.Killer.Character
				local head = kc and kc:FindFirstChild("Head")
				local root = kc and kc:FindFirstChild("HumanoidRootPart")
				if head and root then
					local look = root.CFrame.LookVector
					local yaw = math.atan2(-look.X, -look.Z)
					local pitch = kc:GetAttribute("AimPitch") or 0
					local k = 1 - math.exp(-12 * dt)
					d.Yaw = d.Yaw and lerpAngle(d.Yaw, yaw, k) or yaw
					d.Pitch = d.Pitch and d.Pitch + (pitch - d.Pitch) * k or pitch
					local pos = head.Position + Vector3.new(0, 0.2, 0)
					d.Pos = d.Pos and d.Pos:Lerp(pos, 1 - math.exp(-14 * dt)) or pos
					d.KillerView = CFrame.new(d.Pos) * CFrame.fromOrientation(d.Pitch, d.Yaw, 0)
					return d.KillerView, 72
				elseif d.KillerView then
					return d.KillerView, 72 -- the killer left or died: hold the last view
				end
			end

			-- nobody to watch: circle your own body
			local c = startCF.Position - Vector3.new(0, 1.2, 0)
			local ang = (t - FALL) * 0.4
			local pos = c + Vector3.new(math.sin(ang) * 7, 2.6, math.cos(ang) * 7)
			return CFrame.lookAt(pos, c)
		end,
	}
end

function DeathPresentation:_begin()
	local cam = workspace.CurrentCamera
	local d = {
		Start = os.clock(), P = nil, Killer = nil, KillcamEnd = 3.5, Faded = false,
		StartCF = self.LastView or (cam and cam.CFrame) or CFrame.new(),
	}
	self.Dead = d
	self.Protect = nil
	self.Shield.GroupTransparency = 1
	ScreenFX.Vignette(RED, 0.85, 0.12)
	ScreenFX.Grade(-0.8, 10, 0.5)
	UISound.Play("Death")
	CineCam.Play(deathShot(self, d))
	return d
end

function DeathPresentation:OnLocalDeath()
	if MatchClient.Phase() ~= "Match" then return end
	if not self.Dead then self:_begin() end
end

function DeathPresentation:_onDeath(p)
	if type(p) ~= "table" then return end
	local d = self.Dead
	if not d or os.clock() - d.Start > 4 then d = self:_begin() end
	d.P = p
	d.Killer = p.KillerId and Players:GetPlayerByUserId(p.KillerId) or nil
	d.KillcamEnd = p.Delay and math.clamp(p.Delay - 0.9, 1.4, 4) or 3.5
	d.RespawnAt = p.Delay and d.Start + p.Delay or nil

	self.Kicker.Text = kickerFor(p)
	local team = p.KillerTeam
	self.KillerName.Text = p.KillerName and p.KillerName:upper() or ""
	self.KillerName.TextColor3 = team and Theme.TeamColor[team] or Theme.Danger
	self.Detail.Text = detailFor(p)
	if p.KillerName then
		self.Card.Set(d.Killer and PlayerCard.Options(d.Killer) or { Name = p.KillerName })
		d.ShowCard = true
	end
	d.ShowBanner = true
end

function DeathPresentation:_spectateTargets()
	local list = {}
	local mine = player.Team
	for _, other in Players:GetPlayers() do
		if other ~= player and mine ~= nil and other.Team == mine then
			local char = other.Character
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			if hum and hum.Health > 0 and char:FindFirstChild("HumanoidRootPart") then table.insert(list, other) end
		end
	end
	table.sort(list, function(a, b) return a.UserId < b.UserId end)
	return list
end

function DeathPresentation:_spectateTarget(d)
	local list = self:_spectateTargets()
	if d.Spec and table.find(list, d.Spec) then return d.Spec end
	d.Spec = list[1]
	d.SpecPos = nil
	return d.Spec
end

function DeathPresentation:_cycleSpectate()
	local d = self.Dead
	if not d or not d.P or d.P.Delay ~= false or os.clock() - d.Start < d.KillcamEnd then return end
	local list = self:_spectateTargets()
	if #list == 0 then return end
	local i = d.Spec and table.find(list, d.Spec) or 0
	d.Spec = list[i % #list + 1]
	d.SpecPos = nil
end

-- stop showing death UI. fade = also bring the screen and camera back (used when you spawn)
function DeathPresentation:_clearDead(restore)
	local d = self.Dead
	self.Dead = nil
	self.Banner.GroupTransparency, self.CardBox.GroupTransparency, self.Resp.GroupTransparency = 1, 1, 1
	self.CamTag.Visible = false
	if d and restore then
		CineCam.Stop(0.5)
		ScreenFX.Grade(0, 0, 0.4)
		ScreenFX.Vignette(RED, 0, 0.4)
	end
end

function DeathPresentation:_tick(dt)
	local cf = self.Hooks.ViewCF()
	if cf then self.LastView = cf end

	local d = self.Dead
	if d then
		local t = os.clock() - d.Start
		-- the blur only covers the fall; the killcam is sharp
		if not d.Cleared and t >= FALL then
			d.Cleared = true
			ScreenFX.Grade(-0.8, 0, 0.6)
			ScreenFX.Vignette(RED, 0.45, 1.2)
		end
		local spectate = d.P and d.P.Delay == false
		if d.ShowBanner then
			self.Banner.GroupTransparency = 1 - smooth((t - 0.15) / 0.35)
			self.Banner.Position = UDim2.new(0.5, 0, 0.1 - (1 - smooth((t - 0.15) / 0.5)) * 0.03, 0)
		end
		if d.ShowCard then self.CardBox.GroupTransparency = 1 - smooth((t - FALL) / 0.4) end
		self.CamTag.Visible = d.Killer ~= nil and t >= FALL and not (spectate and t >= d.KillcamEnd)
		if self.CamTag.Visible then self.CamTag.TextTransparency = 0.5 + 0.5 * math.sin(os.clock() * 5) * 0.4 end

		if d.P then
			self.Resp.GroupTransparency = 1 - smooth((t - 0.4) / 0.4)
			if spectate then
				self.RespLbl.Text = "ELIMINATED"
				self.RespFill.Size = UDim2.fromScale(0, 1)
				local n = #self:_spectateTargets()
				local key = InputMap.Label("Fire")
				self.RespHint.Text = (n > 0 and t >= d.KillcamEnd) and (key ~= "" and ("%s  -  NEXT TEAMMATE"):format(key:upper()) or "TAP  -  NEXT TEAMMATE") or "WAITING FOR THE NEXT ROUND"
			elseif d.RespawnAt then
				local left = d.RespawnAt - os.clock()
				self.RespLbl.Text = left > 0 and ("RESPAWNING IN %d"):format(math.ceil(left)) or "SPAWNING..."
				self.RespFill.Size = UDim2.fromScale(clamp01(1 - left / math.max(d.P.Delay, 0.1)), 1)
				self.RespHint.Text = ""
				if not d.Faded and left <= 0.55 then -- black just before the server puts you back on the map
					d.Faded = true
					ScreenFX.Fade(1, 0.5)
				end
			end
		end
	end

	local fi = self.FadeIn
	if fi and (self.Hooks.RigActive() or os.clock() - fi.Start > 1.6) and os.clock() - fi.Start > 0.25 then
		self.FadeIn = nil
		ScreenFX.Fade(0, 0.6)
	end

	local pr = self.Protect
	if pr then
		local left = pr.End - os.clock()
		if left <= 0 then
			self.Protect = nil
			self.Shield.GroupTransparency = 1
		else
			self.ShieldFill.Size = UDim2.fromScale(clamp01(left / pr.Total), 1)
			self.Shield.GroupTransparency = 1 - smooth(math.min(1, left / 0.4))
		end
	end
end

-- ---------------------------------------------------------------- spawn
function DeathPresentation:_onSpawned(protection)
	local intro = (MatchClient.Get("IntroEnd") or 0) > workspace:GetServerTimeNow()
	local wasDead = self.Dead ~= nil
	if wasDead then self:_clearDead(true) end
	if intro then return end -- the match intro owns the screen

	if wasDead or MatchClient.Phase() == "Match" then
		ScreenFX.Fade(1, 0) -- (already black after a death; a short dip for a loadout respawn)
		self.FadeIn = { Start = os.clock() }
	end
	UISound.Play("Respawn")
	if type(protection) == "number" and protection > 0.2 then
		ScreenFX.Vignette(Theme.Plate, 0.5, 0.3)
		task.delay(0.4, function() ScreenFX.Vignette(Theme.Plate, 0, math.max(protection - 0.4, 0.2)) end)
		self.Protect = { End = os.clock() + protection, Total = protection }
	end
end

return DeathPresentation
