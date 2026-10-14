-- Scoreboard: hold the Scoreboard key (default Tab, touch SCORES button) to see the match.
-- Teams: two tables (Alpha / Bravo) with the team score; free for all: one ranked list. Columns: kills, deaths and, in objective modes, OBJ
-- (flags captured / neutralised, tags confirmed / denied, hill time). Data is replicated by MatchService as player attributes
-- (Deployed, MatchKills, MatchDeaths, MatchObj) + the Alpha / Bravo score on MatchState. Replaces Roblox's own player list.
local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Theme = require(script.Parent.Theme)
local Widgets = require(script.Parent.Widgets)
local InputMap = require(script.Parent.InputMap)
local Modes = require(script.Parent.Modes)
local MatchClient = require(script.Parent.MatchClient)

local Scoreboard = {}
Scoreboard.__index = Scoreboard

local LEFT, CENTER, RIGHT = Enum.TextXAlignment.Left, Enum.TextXAlignment.Center, Enum.TextXAlignment.Right
local player = Players.LocalPlayer
local ROWS, ROW_H, COL_W = 10, 28, 330

local function clock(t)
	t = math.max(0, math.ceil(t))
	return ("%d:%02d"):format(t // 60, t % 60)
end

local function alive(plr)
	local c = plr.Character
	local h = c and c:FindFirstChildOfClass("Humanoid")
	return h ~= nil and h.Health > 0
end

-- one table: header (team name + score), column titles, ROWS rows
local function buildTable(parent, x)
	local t = { Rows = {} }
	t.Header = Theme.Label(parent, "", 24, Theme.Text, LEFT, Theme.Display, UDim2.fromOffset(x, 62), UDim2.fromOffset(COL_W - 90, 30))
	t.Score = Theme.Label(parent, "", 24, Theme.Text, RIGHT, Theme.Display, UDim2.fromOffset(x + COL_W - 100, 62), UDim2.fromOffset(100, 30))
	t.ColK = Theme.Label(parent, "K", 12, Theme.Dim, RIGHT, Theme.Display, UDim2.fromOffset(x + COL_W - 130, 96), UDim2.fromOffset(40, 16))
	t.ColD = Theme.Label(parent, "D", 12, Theme.Dim, RIGHT, Theme.Display, UDim2.fromOffset(x + COL_W - 86, 96), UDim2.fromOffset(40, 16))
	t.ColO = Theme.Label(parent, "OBJ", 12, Theme.Dim, RIGHT, Theme.Display, UDim2.fromOffset(x + COL_W - 44, 96), UDim2.fromOffset(40, 16))
	for i = 1, ROWS do
		local row = Theme.Frame(parent, UDim2.fromOffset(COL_W, ROW_H - 2), UDim2.fromOffset(x, 116 + (i - 1) * ROW_H), nil, Theme.Panel, 0.55)
		Theme.Round(row, 4)
		local rank = Theme.Label(row, "", 14, Theme.Dim, CENTER, Theme.Display, UDim2.fromOffset(0, 0), UDim2.fromOffset(26, ROW_H - 2))
		local name = Theme.Label(row, "", 16, Theme.Text, LEFT, Theme.Display, UDim2.fromOffset(30, 0), UDim2.fromOffset(COL_W - 170, ROW_H - 2))
		name.TextTruncate = Enum.TextTruncate.AtEnd
		local k = Theme.Label(row, "", 16, Theme.Text, RIGHT, Theme.Display, UDim2.fromOffset(COL_W - 130, 0), UDim2.fromOffset(40, ROW_H - 2))
		local d = Theme.Label(row, "", 16, Theme.Dim, RIGHT, Theme.Display, UDim2.fromOffset(COL_W - 86, 0), UDim2.fromOffset(40, ROW_H - 2))
		local o = Theme.Label(row, "", 16, Theme.Accent, RIGHT, Theme.Display, UDim2.fromOffset(COL_W - 44, 0), UDim2.fromOffset(40, ROW_H - 2))
		row.Visible = false
		t.Rows[i] = { Frame = row, Rank = rank, Name = name, K = k, D = d, O = o }
	end
	return t
end

function Scoreboard.new()
	local self = setmetatable({}, Scoreboard)
	pcall(function() StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false) end) -- this replaces it
	local gui = Instance.new("ScreenGui")
	gui.Name, gui.ResetOnSpawn, gui.IgnoreGuiInset, gui.DisplayOrder = "Scoreboard", false, true, 12
	gui.Parent = player:WaitForChild("PlayerGui")
	local root = Widgets.ScaledRoot(gui, function() return InputMap.Device == "Touch" and 540 or 800 end, "Interface.HudScale")

	local panel = Instance.new("CanvasGroup")
	panel.BackgroundTransparency, panel.BorderSizePixel, panel.GroupTransparency = 1, 0, 1
	panel.Size, panel.Position, panel.AnchorPoint = UDim2.fromOffset(720, 450), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5)
	panel.Visible = false
	panel.Parent = root
	local back = Theme.Glass(panel, UDim2.fromScale(1, 1))
	back.BackgroundTransparency = 0.12
	self.Panel = panel
	self.Title = Theme.Label(panel, "", 28, Theme.Text, LEFT, Theme.Display, UDim2.fromOffset(20, 12), UDim2.fromOffset(500, 36))
	self.Sub = Theme.Label(panel, "", 14, Theme.Dim, LEFT, Theme.Display, UDim2.fromOffset(20, 40), UDim2.fromOffset(500, 18))
	self.Time = Theme.Label(panel, "", 28, Theme.Accent, RIGHT, Theme.Display, UDim2.new(1, -20, 0, 12), UDim2.fromOffset(160, 36), Vector2.new(1, 0))
	self.Left = buildTable(panel, 20)
	self.Right = buildTable(panel, 370)

	self.Held = false
	InputMap.OnBegan("Scoreboard", function() self:_set(true) end)
	InputMap.OnEnded("Scoreboard", function() self:_set(false) end)
	MatchClient.OnChanged(function() if MatchClient.Phase() ~= "Match" then self:_set(false) end end)

	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if self.Held and acc >= 0.2 then
			acc = 0
			self:_refresh()
		end
	end)
	return self
end

function Scoreboard:_set(on)
	if on and MatchClient.Phase() ~= "Match" then return end
	if self.Held == on then return end
	self.Held = on
	if on then
		self.Panel.Visible = true
		self:_refresh()
	end
	TweenService:Create(self.Panel, TweenInfo.new(0.12), { GroupTransparency = on and 0 or 1 }):Play()
	if not on then
		task.delay(0.14, function() if not self.Held then self.Panel.Visible = false end end)
	end
end

local function fill(t, list, color, startRank, objective)
	t.ColO.Visible = objective
	for i = 1, ROWS do
		local row, e = t.Rows[i], list[i]
		if e then
			local plr = e.Plr
			local mine = plr == player
			row.Frame.Visible = true
			row.Frame.BackgroundColor3 = mine and Theme.Accent or Theme.Panel
			row.Frame.BackgroundTransparency = mine and 0.78 or 0.55
			row.Rank.Text = tostring(startRank + i - 1)
			row.Name.Text = plr.DisplayName
			row.Name.TextColor3 = e.Alive and (color or Theme.Text) or Theme.Dim
			row.K.Text, row.D.Text = tostring(e.K), tostring(e.D)
			row.O.Text = objective and tostring(e.O) or ""
		else
			row.Frame.Visible = false
		end
	end
end

function Scoreboard:_refresh()
	local def = Modes.Get(MatchClient.Get("Mode") or "")
	if not def then return end
	local all = {}
	for _, plr in Players:GetPlayers() do
		if plr:GetAttribute("Deployed") == true then
			table.insert(all, {
				Plr = plr, Team = plr.Team and plr.Team.Name, Alive = alive(plr),
				K = plr:GetAttribute("MatchKills") or 0, D = plr:GetAttribute("MatchDeaths") or 0, O = plr:GetAttribute("MatchObj") or 0,
			})
		end
	end
	local objective = def.Objective ~= nil
	table.sort(all, function(a, b)
		if objective and a.O ~= b.O then return a.O > b.O end
		if a.K ~= b.K then return a.K > b.K end
		return a.D < b.D
	end)

	self.Title.Text = def.Name:upper()
	local map = Modes.GetMap(MatchClient.Get("Map") or "")
	self.Sub.Text = map and map.Name:upper() or ""
	self.Time.Text = clock(math.min(MatchClient.TimeLeft(), def.TimeLimit or def.RoundTime or math.huge))

	if def.Teams then
		local a, b = {}, {}
		for _, e in all do
			table.insert(e.Team == "Alpha" and a or b, e)
		end
		for side, t in { Alpha = self.Left, Bravo = self.Right } do
			t.Header.Text = side:upper()
			t.Header.TextColor3 = Theme.TeamColor[side]
			t.Score.Text = tostring(MatchClient.Get("Score" .. side) or 0)
			t.Score.TextColor3 = Theme.TeamColor[side]
		end
		fill(self.Left, a, Theme.TeamColor.Alpha, 1, objective)
		fill(self.Right, b, Theme.TeamColor.Bravo, 1, objective)
	else
		local first, second = {}, {}
		for i, e in all do
			if i <= ROWS then table.insert(first, e) elseif i <= ROWS * 2 then table.insert(second, e) end
		end
		self.Left.Header.Text, self.Left.Score.Text = "PLAYERS", tostring(#all)
		self.Right.Header.Text, self.Right.Score.Text = "", ""
		self.Left.Header.TextColor3, self.Left.Score.TextColor3 = Theme.Text, Theme.Dim
		fill(self.Left, first, nil, 1, false)
		fill(self.Right, second, nil, ROWS + 1, false)
	end
end

return Scoreboard
