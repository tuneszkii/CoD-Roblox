-- MatchHud: in-match overlay. Score + timer strip, round / alive info, announcements, respawn countdown and the results screen.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Theme = require(script.Parent.Theme)
local Widgets = require(script.Parent.Widgets)
local InputMap = require(script.Parent.InputMap)
local MatchClient = require(script.Parent.MatchClient)
local Modes = require(script.Parent.Modes)
local PlayerCard = require(script.Parent.PlayerCard)

local MatchHud = {}
MatchHud.__index = MatchHud

local CENTER, LEFT, RIGHT = Enum.TextXAlignment.Center, Enum.TextXAlignment.Left, Enum.TextXAlignment.Right
local C0 = Color3.new()
local TEAM_HEX = { Alpha = "#5aa0ff", Bravo = "#ff9a3c" }
local TEAM_COLOR = { Alpha = Color3.fromRGB(90, 160, 255), Bravo = Color3.fromRGB(255, 154, 60) }
local player = Players.LocalPlayer

local function clock(t)
	t = math.ceil(t)
	return ("%d:%02d"):format(t // 60, t % 60)
end

function MatchHud.new()
	local self = setmetatable({}, MatchHud)
	local gui = Instance.new("ScreenGui")
	gui.Name, gui.ResetOnSpawn, gui.IgnoreGuiInset, gui.DisplayOrder = "MatchHud", false, true, 6
	gui.Parent = player:WaitForChild("PlayerGui")
	self.Gui = gui
	local root = Widgets.ScaledRoot(gui, function() return InputMap.Device == "Touch" and 540 or 800 end, "Interface.HudScale")

	-- score strip (under the compass)
	local strip = Theme.Glass(root, UDim2.fromOffset(380, 54), UDim2.new(0.5, 0, 0, 78), Vector2.new(0.5, 0))
	self.Strip = strip
	self.Line1 = Theme.Label(strip, "", 22, Theme.Text, CENTER, Theme.Display, UDim2.fromOffset(0, 3), UDim2.new(1, 0, 0, 30))
	self.Line2 = Theme.Label(strip, "", 12, Theme.Dim, CENTER, Theme.Display, UDim2.fromOffset(0, 33), UDim2.new(1, 0, 0, 16))

	-- announcements (the respawn countdown lives in DeathPresentation)
	self.Msg = Theme.Label(root, "", 30, Theme.Text, CENTER, Theme.Display, UDim2.fromScale(0.5, 0.24), UDim2.fromOffset(700, 44), Vector2.new(0.5, 0.5))
	self.Msg.TextTransparency, self.Msg.TextStrokeTransparency = 1, 1
	self.Root = root
	self.Results = nil

	MatchClient.OnEvent(function(kind, a, b)
		if kind == "Message" then self:Announce(a, b)
		elseif kind == "Results" then
			-- MatchPresentation plays the victory / defeat sequence first, then the scoreboard slides in
			self.ResultsToken = (self.ResultsToken or 0) + 1
			local token = self.ResultsToken
			task.delay(Modes.Config.EndPresentTime or 0, function()
				if self.ResultsToken == token and MatchClient.Phase() == "Results" then self:ShowResults(a) end
			end)
		end
	end)
	MatchClient.OnChanged(function()
		if MatchClient.Phase() ~= "Results" and self.Results then self:HideResults() end
	end)

	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc >= 0.15 then
			acc = 0
			self:_update()
		end
	end)
	self:_update()
	return self
end

local TONES = { Good = Theme.Good, Bad = Theme.Danger, Warn = Theme.Warn }

function MatchHud:Announce(text, tone)
	self.MsgToken = (self.MsgToken or 0) + 1
	local token = self.MsgToken
	self.Msg.TextColor3 = TONES[tone] or Theme.Text
	self.Msg.Text, self.Msg.TextTransparency, self.Msg.TextStrokeTransparency = text, 0, 0.5
	task.delay(2.6, function()
		if self.MsgToken == token then
			for i = 1, 10 do
				if self.MsgToken ~= token then return end
				self.Msg.TextTransparency, self.Msg.TextStrokeTransparency = i / 10, 0.5 + i / 20
				task.wait(0.04)
			end
		end
	end)
end

function MatchHud:_update()
	local phase = MatchClient.Phase()
	local intro = (MatchClient.Get("IntroEnd") or 0) > workspace:GetServerTimeNow() -- the match intro / countdown is playing
	self.Strip.Visible = phase == "Match" and not intro
	if phase == "Results" and self.Results then
		self.Results.Footer.Text = ("NEXT VOTE IN %d"):format(math.ceil(MatchClient.TimeLeft()))
	end
	if phase ~= "Match" then return end

	local def = Modes.Get(MatchClient.Get("Mode") or "")
	if not def then return end
	local a, b = MatchClient.Get("ScoreAlpha") or 0, MatchClient.Get("ScoreBravo") or 0
	local t = clock(math.min(MatchClient.TimeLeft(), def.TimeLimit or def.RoundTime or math.huge))
	if def.Teams then
		self.Line1.Text = ('<font color="%s">ALPHA  %d</font>     %s     <font color="%s">%d  BRAVO</font>'):format(TEAM_HEX.Alpha, a, t, TEAM_HEX.Bravo, b)
		if def.Rounds then
			self.Line2.Text = ("ROUND %d   |   ALIVE  %d v %d   |   FIRST TO %d"):format(MatchClient.Get("Round") or 0,
				MatchClient.Get("AliveAlpha") or 0, MatchClient.Get("AliveBravo") or 0, def.RoundsToWin)
		else
			self.Line2.Text = ("%s   |   FIRST TO %d"):format(def.Name:upper(), def.ScoreLimit)
		end
	else
		local mine = player:GetAttribute("MatchKills") or 0
		local lead = MatchClient.Get("LeaderName") or ""
		self.Line1.Text = ("YOU  %d     %s     %s  %d"):format(mine, t, lead ~= "" and lead:upper():sub(1, 12) or "LEAD", MatchClient.Get("LeaderScore") or 0)
		self.Line2.Text = ("%s   |   FIRST TO %d"):format(def.Name:upper(), def.ScoreLimit)
	end
end

-- ---------------------------------------------------------------- results
function MatchHud:HideResults()
	if self.Results then
		self.Results.Frame:Destroy()
		self.Results = nil
	end
end

function MatchHud:ShowResults(data)
	self:HideResults()
	local fade = Instance.new("CanvasGroup") -- fades + slides in as one piece
	fade.BackgroundTransparency, fade.BorderSizePixel, fade.GroupTransparency = 1, 0, 1
	fade.Size, fade.Position, fade.AnchorPoint = UDim2.fromOffset(560, 410), UDim2.new(0.5, 0, 0.5, 30), Vector2.new(0.5, 0.5)
	fade.Parent = self.Root
	local frame = Theme.Glass(fade, UDim2.fromScale(1, 1), UDim2.new())
	frame.BackgroundTransparency = 0.08
	TweenService:Create(fade, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { GroupTransparency = 0, Position = UDim2.fromScale(0.5, 0.5) }):Play()
	local myTeam = player.Team and player.Team.Name
	local title, color
	if data.Winner == "Draw" then title, color = "DRAW", Theme.Dim
	elseif data.Teams then
		if data.WinnerTeam == myTeam then title, color = "VICTORY", Theme.Good else title, color = "DEFEAT", Theme.Danger end
	else
		if data.WinnerUserId == player.UserId then title, color = "VICTORY", Theme.Good else title, color = "MATCH OVER", Theme.Text end
	end
	Theme.Label(frame, title, 46, color, CENTER, Theme.Display, UDim2.fromOffset(0, 14), UDim2.new(1, 0, 0, 56))
	-- the top player's card (their equipped Cosmetics card / emblem / title) sits in the corner
	local top = data.Players[1] and Players:GetPlayerByUserId(data.Players[1].UserId)
	if top then
		local o = PlayerCard.Options(top)
		local card = PlayerCard.Build(frame, 0.5, UDim2.fromOffset(16, 14))
		card.Set(o)
	end
	local sub = ("%s  |  %s"):format(data.Mode:upper(), data.Map:upper())
	Theme.Label(frame, sub, 14, Theme.Dim, CENTER, Theme.Display, UDim2.fromOffset(0, 70), UDim2.new(1, 0, 0, 18))
	if data.Teams then
		Theme.Label(frame, ('<font color="%s">ALPHA  %d</font>      <font color="%s">%d  BRAVO</font>'):format(TEAM_HEX.Alpha, data.Score.Alpha, TEAM_HEX.Bravo, data.Score.Bravo),
			26, Theme.Text, CENTER, Theme.Display, UDim2.fromOffset(0, 94), UDim2.new(1, 0, 0, 34))
	elseif data.Winner ~= "Draw" then
		Theme.Label(frame, ("WINNER   %s"):format(tostring(data.Winner):upper()), 22, Theme.Accent, CENTER, Theme.Display, UDim2.fromOffset(0, 96), UDim2.new(1, 0, 0, 30))
	end

	Theme.Label(frame, "PLAYER", 12, Theme.Dim, LEFT, Theme.Display, UDim2.fromOffset(40, 140), UDim2.fromOffset(200, 16))
	Theme.Label(frame, "KILLS", 12, Theme.Dim, RIGHT, Theme.Display, UDim2.new(1, -120, 0, 140), UDim2.fromOffset(60, 16), Vector2.new(1, 0))
	Theme.Label(frame, "DEATHS", 12, Theme.Dim, RIGHT, Theme.Display, UDim2.new(1, -40, 0, 140), UDim2.fromOffset(70, 16), Vector2.new(1, 0))
	for i, row in data.Players do
		local y = 160 + (i - 1) * 28
		local mine = row.UserId == player.UserId
		local bar = Theme.Frame(frame, UDim2.new(1, -60, 0, 26), UDim2.fromOffset(30, y), nil, mine and Theme.Accent or Theme.Panel, mine and 0.78 or 0.55)
		Theme.Round(bar, 4)
		local col = row.Team and TEAM_COLOR[row.Team] or Theme.Text
		Theme.Label(bar, ("%d   %s"):format(i, row.Name), 16, col, LEFT, Theme.Display, UDim2.fromOffset(10, 0), UDim2.new(1, -170, 1, 0))
		Theme.Label(bar, tostring(row.K), 16, Theme.Text, RIGHT, Theme.Display, UDim2.new(1, -86, 0, 0), UDim2.fromOffset(60, 26), Vector2.new(1, 0))
		Theme.Label(bar, tostring(row.D), 16, Theme.Dim, RIGHT, Theme.Display, UDim2.new(1, -10, 0, 0), UDim2.fromOffset(70, 26), Vector2.new(1, 0))
	end
	local footer = Theme.Label(frame, "", 14, Theme.Accent, CENTER, Theme.Display, UDim2.new(0, 0, 1, -30), UDim2.new(1, 0, 0, 20))
	self.Results = { Frame = fade, Footer = footer }
end

return MatchHud
