-- MatchPresentation: how a match starts and how it ends. Created once by FPSMain; driven by the server's MatchEvent messages.
--
-- START  ("Intro" at deploy, "Go" when the countdown ends; timings come from the server clock so every client is in step)
--   fade in from black, cinematic bars, a flyover of the map (sweeping across the flags / hills in objective modes), a title card
--   (mode, map, your team, the objective), then the camera settles into your spawn view and a 3-2-1 plays, then FIGHT.
--   While it plays you are frozen (the server anchors you), cannot hurt anyone and cannot fire (hooks.SetLocked).
--   Players who deploy into a running match get a short banner instead (no flyover, no countdown).
-- END    ("Results")
--   cinematic bars, VICTORY / DEFEAT / DRAW with the reason and the score, the camera orbits your operator (or the map when you have no body),
--   then MatchHud slides the scoreboard in (Modes.Config.EndPresentTime) and the screen fades to black just before the next vote.
--
-- hooks = { CloseMenu = function(), SetLocked = function(bool), RigActive = function() -> bool }
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Theme = require(script.Parent.Theme)
local Widgets = require(script.Parent.Widgets)
local InputMap = require(script.Parent.InputMap)
local Modes = require(script.Parent.Modes)
local MatchClient = require(script.Parent.MatchClient)
local ScreenFX = require(script.Parent.ScreenFX)
local CineCam = require(script.Parent.CineCam)
local UISound = require(script.Parent.UISound)

local MatchPresentation = {}
MatchPresentation.__index = MatchPresentation

local LEFT, CENTER = Enum.TextXAlignment.Left, Enum.TextXAlignment.Center
local C0 = Color3.new()
local player = Players.LocalPlayer
local MC = Modes.Config

local REASONS = {
	ScoreLimit = "SCORE LIMIT REACHED", TimeLimit = "TIME LIMIT REACHED", Rounds = "ROUND LIMIT REACHED", Empty = "NOT ENOUGH PLAYERS",
}

local function clamp01(x) return math.clamp(x, 0, 1) end
local function smooth(x) x = clamp01(x) return x * x * (3 - 2 * x) end

local function show(label, a) -- 0 = invisible, 1 = fully visible
	label.TextTransparency, label.TextStrokeTransparency = 1 - a, 1 - a * 0.25
end

local function group(parent, size, pos, anchor)
	local g = Instance.new("CanvasGroup")
	g.BackgroundTransparency, g.BorderSizePixel = 1, 0
	g.Size, g.Position, g.AnchorPoint, g.GroupTransparency = size, pos, anchor or Vector2.zero, 1
	g.Parent = parent
	return g
end

local function teamLine(team)
	if not team then return "FREE FOR ALL", Theme.Text end
	return ('YOU ARE ON <font color="%s">%s</font>'):format(Theme.TeamHex[team] or "#ffffff", team:upper()), Theme.TeamColor[team] or Theme.Text
end

-- ---------------------------------------------------------------- build
function MatchPresentation.new(hooks)
	local self = setmetatable({ Hooks = hooks }, MatchPresentation)
	local gui = Instance.new("ScreenGui")
	gui.Name, gui.ResetOnSpawn, gui.IgnoreGuiInset, gui.DisplayOrder = "MatchPresentation", false, true, 9
	gui.Parent = player:WaitForChild("PlayerGui")
	local root = Widgets.ScaledRoot(gui, function() return InputMap.Device == "Touch" and 540 or 800 end, "Interface.HudScale")
	self.Gui, self.Root = gui, root

	-- title card (left side)
	local title = group(root, UDim2.fromOffset(680, 270), UDim2.new(0, 70, 0.5, 0), Vector2.new(0, 0.5))
	self.Title = title
	Theme.Frame(title, UDim2.fromOffset(120, 4), UDim2.fromOffset(0, 6), nil, Theme.Accent, 0)
	Theme.Label(title, "MATCH START", 18, Theme.Accent, LEFT, Theme.Display, UDim2.fromOffset(0, 14), UDim2.fromOffset(600, 24))
	self.ModeLbl = Theme.Label(title, "", 76, Theme.Text, LEFT, Theme.Display, UDim2.fromOffset(0, 38), UDim2.fromOffset(680, 86))
	self.MapLbl = Theme.Label(title, "", 28, Theme.Dim, LEFT, Theme.Display, UDim2.fromOffset(0, 124), UDim2.fromOffset(640, 34))
	local pill = Theme.Frame(title, UDim2.fromOffset(290, 34), UDim2.fromOffset(0, 168), nil, Theme.Panel, 0.25)
	Theme.Round(pill, 4)
	self.PillStroke = Theme.Stroke(pill, Theme.Dim, 2, 0.2)
	self.TeamLbl = Theme.Label(pill, "", 20, Theme.Text, CENTER, Theme.Display)
	self.BriefLbl = Theme.Label(title, "", 18, Theme.Text, LEFT, Theme.Body, UDim2.fromOffset(0, 214), UDim2.fromOffset(600, 50))
	self.BriefLbl.TextWrapped, self.BriefLbl.TextYAlignment = true, Enum.TextYAlignment.Top

	-- countdown + FIGHT (centre)
	self.CdSmall = Theme.Label(root, "MATCH STARTS IN", 20, Theme.Dim, CENTER, Theme.Display, UDim2.fromScale(0.5, 0.33), UDim2.fromOffset(500, 28), Vector2.new(0.5, 0.5))
	self.CdNum = Theme.Label(root, "", 150, Theme.Text, CENTER, Theme.Display, UDim2.fromScale(0.5, 0.45), UDim2.fromOffset(400, 170), Vector2.new(0.5, 0.5))
	self.CdScale = Instance.new("UIScale")
	self.CdScale.Parent = self.CdNum
	self.Fight = Theme.Label(root, "FIGHT", 130, Theme.Accent, CENTER, Theme.Display, UDim2.fromScale(0.5, 0.45), UDim2.fromOffset(600, 150), Vector2.new(0.5, 0.5))
	self.FightScale = Instance.new("UIScale")
	self.FightScale.Parent = self.Fight
	for _, l in { self.CdSmall, self.CdNum, self.Fight } do show(l, 0) end

	-- short banner for players who join a running match
	local late = group(root, UDim2.fromOffset(560, 104), UDim2.new(0.5, 0, 0.17, 0), Vector2.new(0.5, 0))
	self.Late = late
	local lateBack = Theme.Glass(late, UDim2.fromScale(1, 1))
	lateBack.BackgroundTransparency = 0.2
	self.LateTeam = Theme.Label(lateBack, "", 26, Theme.Text, CENTER, Theme.Display, UDim2.fromOffset(0, 6), UDim2.new(1, 0, 0, 34))
	self.LateMode = Theme.Label(lateBack, "", 15, Theme.Accent, CENTER, Theme.Display, UDim2.fromOffset(0, 40), UDim2.new(1, 0, 0, 20))
	self.LateBrief = Theme.Label(lateBack, "", 14, Theme.Dim, CENTER, Theme.Body, UDim2.fromOffset(16, 62), UDim2.new(1, -32, 0, 36))
	self.LateBrief.TextWrapped, self.LateBrief.TextYAlignment = true, Enum.TextYAlignment.Top

	-- end of match (centre)
	local fin = group(root, UDim2.fromOffset(900, 300), UDim2.fromScale(0.5, 0.4), Vector2.new(0.5, 0.5))
	self.EndGroup = fin
	self.EndReason = Theme.Label(fin, "", 22, Theme.Dim, CENTER, Theme.Display, UDim2.fromOffset(0, 8), UDim2.new(1, 0, 0, 30))
	self.EndTitle = Theme.Label(fin, "", 120, Theme.Text, CENTER, Theme.Display, UDim2.fromOffset(0, 40), UDim2.new(1, 0, 0, 140))
	self.EndSub = Theme.Label(fin, "", 30, Theme.Text, CENTER, Theme.Display, UDim2.fromOffset(0, 188), UDim2.new(1, 0, 0, 40))
	self.EndScale = Instance.new("UIScale")
	self.EndScale.Parent = fin

	MatchClient.OnEvent(function(kind, a)
		if kind == "Intro" then self:_startIntro(a)
		elseif kind == "Go" then self:_go()
		elseif kind == "Results" then self:_startEnd(a) end
	end)
	MatchClient.OnChanged(function()
		local phase = MatchClient.Phase()
		if phase == "Voting" then
			if self.End then self:_finishEnd() end
			self:_clearIntro(true)
		end
	end)
	RunService.Heartbeat:Connect(function() self:_tick() end)
	return self
end

-- ---------------------------------------------------------------- start of match
local function flyover(info)
	local c, size = info.Center, info.Size
	local floorY = c.Y - size.Y / 2
	local radius = math.max(size.X, size.Z) * 0.55 + 15
	local base = info.Team == "Bravo" and math.pi or 0
	local focus = info.Focus
	return {
		In = 0.01, Out = 1.2, HideHud = true, fov = 62,
		Update = function()
			local T = math.max(0, workspace:GetServerTimeNow() - info.IntroStart)
			local ang = base + T * 0.16
			local pos = Vector3.new(c.X + math.sin(ang) * radius * 0.75, floorY + 52 + 6 * math.sin(T * 0.6), c.Z + math.cos(ang) * radius)
			local target = Vector3.new(c.X, floorY + 4, c.Z)
			if focus and #focus > 0 then -- sweep across the flags / hills one after the other
				local seg = T / 1.7
				local i = math.floor(seg)
				local k = smooth(seg - i)
				target = focus[i % #focus + 1]:Lerp(focus[(i + 1) % #focus + 1], k) + Vector3.new(0, 2, 0)
			end
			return CFrame.lookAt(pos, target)
		end,
	}
end

function MatchPresentation:_startIntro(info)
	if self.End then self:_finishEnd() end
	self:_clearIntro(false)
	self.Intro = info
	self.Map = info
	info.Local = os.clock()

	local teamText, teamColor = teamLine(info.Team)
	if info.Late then -- the spawn itself fades in (DeathPresentation) and closes the menu (FPSMain); this is only the banner
		self.LateTeam.Text = teamText
		self.LateMode.Text = ("%s  |  %s"):format(info.Mode:upper(), info.Map:upper())
		self.LateBrief.Text = info.Brief
		UISound.Play("Intro")
		return
	end
	self.Hooks.CloseMenu() -- the front end must be gone to see the flyover (round modes have no body yet, so FPSMain would not close it)

	self.ModeLbl.Text = info.Mode:upper()
	self.MapLbl.Text = info.Map:upper() .. (info.MapDesc and info.MapDesc ~= "" and ("   <font color=\"#969ea6\" size=\"18\">" .. info.MapDesc .. "</font>") or "")
	self.TeamLbl.Text = teamText
	self.PillStroke.Color = teamColor
	self.BriefLbl.Text = info.Brief
	self.Hooks.SetLocked(true)
	ScreenFX.Fade(1, 0)
	ScreenFX.Fade(0, 1.0)
	ScreenFX.Letterbox(true, 0.8)
	CineCam.Play(flyover(info))
	self.FlyStopped = false
	UISound.Play("Intro")
end

function MatchPresentation:_go()
	local info = self.Intro
	if info and not info.Late then
		info.Go = true
		self.Hooks.SetLocked(false)
	end
end

function MatchPresentation:_clearIntro(stopCamera)
	local info = self.Intro
	self.Intro = nil
	self.Title.GroupTransparency, self.Late.GroupTransparency = 1, 1
	for _, l in { self.CdSmall, self.CdNum, self.Fight } do show(l, 0) end
	self.LastCount = nil
	if info and not info.Late then
		self.Hooks.SetLocked(false)
		ScreenFX.Letterbox(false, 0.5)
		if stopCamera then CineCam.Stop(0.4) end
	end
end

function MatchPresentation:_introTick(info)
	if info.Late then
		local t = os.clock() - info.Local
		local dur = info.LateTime or MC.LateIntroTime
		self.Late.GroupTransparency = 1 - clamp01(t / 0.3) * clamp01((dur - t) / 0.5)
		if t >= dur then self:_clearIntro(false) end
		return
	end

	local T = workspace:GetServerTimeNow() - info.IntroStart
	local total = info.IntroEnd - info.IntroStart
	local cdStart = total - info.Countdown

	-- title card: slides in, holds, leaves just before the countdown
	local a = smooth((T - 0.3) / 0.6) * smooth((cdStart - 0.2 - T) / 0.5)
	self.Title.GroupTransparency = 1 - a
	self.Title.Position = UDim2.new(0, 70 - (1 - smooth((T - 0.3) / 0.8)) * 60, 0.5, 0)

	-- the flyover hands the camera back to the player just before the countdown (or at GO when there is no body yet)
	if not self.FlyStopped and T >= cdStart - 0.9 and (self.Hooks.RigActive() or T >= total) then
		self.FlyStopped = true
		CineCam.Stop(1.1)
		ScreenFX.Letterbox(false, 0.8)
	end

	-- 3 - 2 - 1
	if T >= cdStart and T < total then
		local remaining = total - T
		local n = math.ceil(remaining)
		local frac = n - remaining -- 0 at the start of each second, 1 at the end
		if self.LastCount ~= n then
			self.LastCount = n
			UISound.Play("Tick")
		end
		self.CdNum.Text = tostring(n)
		self.CdScale.Scale = 1 + 0.55 * (1 - smooth(frac * 3)) ^ 2
		show(self.CdNum, 1 - smooth((frac - 0.7) / 0.3))
		show(self.CdSmall, smooth((T - cdStart) / 0.4))
	else
		show(self.CdNum, 0)
		show(self.CdSmall, 0)
	end

	-- FIGHT
	if T >= total then
		if not info.Fought then
			info.Fought = true
			self.Hooks.SetLocked(false)
			ScreenFX.Flash(Color3.new(1, 1, 1), 0.25, 0.4)
			UISound.Play("Fight")
		end
		local u = T - total
		self.FightScale.Scale = 1 + 0.6 * (1 - smooth(u / 0.25))
		show(self.Fight, smooth(u / 0.08) * (1 - smooth((u - 0.7) / 0.5)))
		if u >= 1.3 then self:_clearIntro(false) end
	end
end

-- ---------------------------------------------------------------- end of match
local function orbit(self)
	local start = os.clock()
	local map = self.Map
	return {
		In = 0.8, Out = 0.6, HideHud = true, ShowBody = true, fov = 55,
		Update = function()
			local t = os.clock() - start
			local char = player.Character
			local root = char and char:FindFirstChild("HumanoidRootPart")
			if root then
				self.LastFocus = root.Position
				self.LastFacing = root.CFrame.LookVector
			end
			local base = self.LastFocus
			if not base then -- no body (not deployed): circle the map instead
				local c = map and map.Center or Vector3.new(0, 400, 0)
				local size = map and map.Size or Vector3.new(120, 30, 160)
				local ang = t * 0.2
				local r = math.max(size.X, size.Z) * 0.6
				local pos = c + Vector3.new(math.sin(ang) * r, size.Y * 0.5 + 25, math.cos(ang) * r)
				return CFrame.lookAt(pos, c - Vector3.new(0, size.Y * 0.3, 0))
			end
			local face = self.LastFacing or Vector3.new(0, 0, -1)
			local focus = base + Vector3.new(0, 1.6, 0)
			local ang = math.atan2(face.X, face.Z) + t * 0.32 -- start in front of the operator, then drift round
			local r = 9 - 3.5 * smooth(t / 2.5)
			local pos = focus + Vector3.new(math.sin(ang) * r, 0.5 + 0.3 * math.sin(t * 0.8), math.cos(ang) * r)
			return CFrame.lookAt(pos, focus + Vector3.new(0, -0.1, 0))
		end,
	}
end

local function outcomeOf(data)
	local myTeam = player.Team and player.Team.Name
	if data.Winner == "Draw" then return "DRAW", Theme.Dim, "Draw" end
	if data.Teams then
		if data.WinnerTeam == myTeam then return "VICTORY", Theme.Good, "Victory" end
		return "DEFEAT", Theme.Danger, "Defeat"
	end
	if data.WinnerUserId == player.UserId then return "VICTORY", Theme.Good, "Victory" end
	return "MATCH OVER", Theme.Text, "Defeat"
end

function MatchPresentation:_startEnd(data)
	self:_clearIntro(false)
	local title, color, sound = outcomeOf(data)
	self.End = { Start = os.clock(), Faded = false }
	self.EndTitle.Text, self.EndTitle.TextColor3 = title, color
	self.EndReason.Text = REASONS[data.Reason] or ""
	if data.Teams then
		self.EndSub.Text = ('<font color="%s">ALPHA  %d</font>      <font color="%s">%d  BRAVO</font>'):format(
			Theme.TeamHex.Alpha, data.Score.Alpha, Theme.TeamHex.Bravo, data.Score.Bravo)
	elseif data.Winner and data.Winner ~= "Draw" then
		self.EndSub.Text = ("WINNER   %s"):format(tostring(data.Winner):upper())
	else
		self.EndSub.Text = ""
	end
	self.Hooks.SetLocked(true)
	ScreenFX.Letterbox(true, 0.6)
	ScreenFX.Grade(title == "VICTORY" and 0.2 or -0.55, 0, 1.2)
	ScreenFX.Flash(color, 0.3, 0.7)
	CineCam.Play(orbit(self))
	UISound.Play(sound)
end

function MatchPresentation:_endTick(e)
	local t = os.clock() - e.Start
	local hold = MC.EndPresentTime or 3.6
	local a = smooth((t - 0.25) / 0.3) * (1 - smooth((t - (hold - 0.4)) / 0.4))
	self.EndGroup.GroupTransparency = 1 - a
	self.EndScale.Scale = 1 + 0.5 * (1 - smooth((t - 0.25) / 0.45))
	if not e.Faded and MatchClient.Phase() == "Results" and MatchClient.TimeLeft() <= 1 then -- black just before the next vote
		e.Faded = true
		ScreenFX.Fade(1, 0.9)
	end
end

function MatchPresentation:_finishEnd()
	self.End = nil
	self.EndGroup.GroupTransparency = 1
	self.Hooks.SetLocked(false)
	CineCam.Stop(0.01)
	ScreenFX.Letterbox(false, 0.4)
	ScreenFX.Grade(0, 0, 0.8)
	ScreenFX.Fade(0, 0.8) -- from black into the vote screen
end

function MatchPresentation:_tick()
	if self.Intro then self:_introTick(self.Intro) end
	if self.End then self:_endTick(self.End) end
end

return MatchPresentation
