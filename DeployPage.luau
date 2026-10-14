-- DeployPage: the DEPLOY tab. Vote for a mode and a map, press DEPLOY. Register with DeployPage.Register(MainMenu) before MainMenu.new.
-- Voting is live (counts update for everybody); the highlighted cards are your votes. During a match the cards show what is being played.
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local Theme = require(script.Parent.Theme)
local Widgets = require(script.Parent.Widgets)
local Modes = require(script.Parent.Modes)
local MatchClient = require(script.Parent.MatchClient)

local DeployPage = {}

local LEFT, CENTER, RIGHT = Enum.TextXAlignment.Left, Enum.TextXAlignment.Center, Enum.TextXAlignment.Right
local C0 = Color3.new()
local player = Players.LocalPlayer

local function clock(t)
	t = math.ceil(t)
	return ("%d:%02d"):format(t // 60, t % 60)
end

local function column(parent, x, w)
	local sf = Instance.new("ScrollingFrame")
	sf.BackgroundTransparency, sf.BorderSizePixel = 1, 0
	sf.Position, sf.Size = UDim2.new(x, x > 0 and 8 or 0, 0, 0), UDim2.new(w, -8, 1, -76)
	sf.ScrollBarThickness, sf.ScrollBarImageColor3 = 5, Theme.Accent
	sf.CanvasSize, sf.AutomaticCanvasSize = UDim2.new(), Enum.AutomaticSize.Y
	sf.Parent = parent
	local list = Instance.new("UIListLayout")
	list.Padding, list.SortOrder = UDim.new(0, 6), Enum.SortOrder.LayoutOrder
	list.Parent = sf
	return sf
end

-- one vote card. Returns { Button, Set = function(state) } where state = { Votes, Mine, Active, Locked, Interactive }
local function card(parent, order, title, desc, onClick)
	local b = Instance.new("TextButton")
	b.AutoButtonColor, b.Text, b.LayoutOrder, b.BorderSizePixel = false, "", order, 0
	b.Size, b.BackgroundColor3, b.BackgroundTransparency = UDim2.new(1, -8, 0, 64), Theme.Panel, 0.4
	Theme.Round(b, 5)
	local stroke = Theme.Stroke(b, Theme.Dim, 1, 0.7)
	local name = Theme.Label(b, title:upper(), 20, Theme.Text, LEFT, Theme.Display, UDim2.fromOffset(16, 7), UDim2.new(1, -150, 0, 26))
	local d = Theme.Label(b, desc, 12, Theme.Dim, LEFT, Theme.Body, UDim2.fromOffset(16, 34), UDim2.new(1, -150, 0, 26))
	d.TextWrapped, d.TextYAlignment = true, Enum.TextYAlignment.Top
	local tag = Theme.Label(b, "", 15, Theme.Accent, RIGHT, Theme.Display, UDim2.new(1, -14, 0, 0), UDim2.fromOffset(130, 64), Vector2.new(1, 0))
	b.Parent = parent
	Widgets.Selectable(b)
	b.Activated:Connect(onClick)
	return {
		Button = b,
		Set = function(s)
			local on = s.Mine or s.Active
			stroke.Color, stroke.Transparency, stroke.Thickness = on and Theme.Accent or Theme.Dim, on and 0.05 or 0.7, on and 2 or 1
			b.BackgroundTransparency = s.Locked and 0.7 or (on and 0.2 or 0.4)
			name.TextColor3 = s.Locked and Theme.Dim or Theme.Text
			if s.Locked then tag.Text, tag.TextColor3 = "LOCKED", Theme.Dim
			elseif s.Active then tag.Text, tag.TextColor3 = "PLAYING", Theme.Good
			elseif s.Votes and s.Votes > 0 then tag.Text, tag.TextColor3 = ("%d VOTE%s"):format(s.Votes, s.Votes == 1 and "" or "S"), Theme.Accent
			else tag.Text = "" end
		end,
	}
end

function DeployPage.build(holder, menu)
	local modeCards, mapCards = {}, {}
	local modes = column(holder, 0, 0.5)
	local maps = column(holder, 0.5, 0.5)
	Widgets.Header(modes, "VOTE: MODE", 0)
	Widgets.Header(maps, "VOTE: MAP", 0)

	for i, def in Modes.List do
		local c = card(modes, i, def.Name, def.Desc, function()
			if def.Enabled then MatchClient.Vote("Mode", def.Id) end
		end)
		modeCards[def.Id] = c
	end

	local builtFor = ""
	local function buildMaps()
		local ids = MatchClient.Candidates()
		local key = table.concat(ids, ",")
		if key == builtFor then return end
		builtFor = key
		for _, c in mapCards do c.Button:Destroy() end
		mapCards = {}
		for i, id in ids do
			local def = Modes.GetMap(id)
			if def then
				mapCards[id] = card(maps, i, def.Name, def.Desc, function() MatchClient.Vote("Map", id) end)
			end
		end
	end

	-- bottom bar: status + deploy button
	local bar = Theme.Glass(holder, UDim2.new(1, 0, 0, 60), UDim2.new(0, 0, 1, 0), Vector2.new(0, 1))
	bar.BackgroundTransparency = 0.25
	local status = Theme.Label(bar, "", 20, Theme.Text, LEFT, Theme.Display, UDim2.fromOffset(18, 0), UDim2.new(1, -300, 1, 0))
	local button = Widgets.FlatButton(bar, "DEPLOY", UDim2.fromOffset(250, 44), UDim2.new(1, -8, 0.5, 0), Vector2.new(1, 0.5), true)
	button.TextSize = 22

	local function charAlive()
		local c = player.Character
		local h = c and c:FindFirstChildOfClass("Humanoid")
		return h ~= nil and h.Health > 0
	end

	local function refresh()
		if not holder.Parent then return end
		buildMaps()
		local phase = MatchClient.Phase()
		local voting = phase == "Voting"
		local activeMode, activeMap = MatchClient.Get("Mode"), MatchClient.Get("Map")
		for id, c in modeCards do
			local def = Modes.Get(id)
			c.Set({ Votes = MatchClient.VoteCount("Mode", id), Mine = voting and MatchClient.MyVote("Mode") == id,
				Active = not voting and activeMode == id, Locked = not def.Enabled })
			c.Button.Active = voting and def.Enabled
		end
		for id, c in mapCards do
			c.Set({ Votes = MatchClient.VoteCount("Map", id), Mine = voting and MatchClient.MyVote("Map") == id, Active = not voting and activeMap == id })
			c.Button.Active = voting
		end

		local left = clock(MatchClient.TimeLeft())
		if phase == "Voting" then
			status.Text = ("VOTING   %s"):format(left)
			button.Text = MatchClient.IsReady() and "READY  (TAP TO CANCEL)" or "DEPLOY"
		elseif phase == "Match" then
			local def, map = Modes.Get(activeMode or ""), Modes.GetMap(activeMap or "")
			status.Text = ("%s  |  %s   %s"):format(def and def.Name:upper() or "", map and map.Name:upper() or "", left)
			if MatchClient.IsDeployed() then button.Text = charAlive() and "RETURN TO GAME" or "RESPAWNING..."
			else button.Text = "DEPLOY" end
		else
			status.Text = ("MATCH OVER   next vote in %d"):format(math.ceil(MatchClient.TimeLeft()))
			button.Text = "..."
		end
	end

	button.Activated:Connect(function()
		local phase = MatchClient.Phase()
		if phase == "Voting" then
			MatchClient.Deploy()
		elseif phase == "Match" then
			if MatchClient.IsDeployed() then menu:Close() else MatchClient.Deploy(true) end
		end
	end)

	MatchClient.OnChanged(refresh)
	task.spawn(function() -- countdown tick
		while holder.Parent do
			refresh()
			task.wait(0.25)
		end
	end)
	refresh()

	return {
		Show = refresh,
		Focus = function()
			local first = modeCards[Modes.List[1].Id]
			GuiService.SelectedObject = first and first.Button or button
		end,
	}
end

function DeployPage.Register(MainMenu)
	MainMenu.RegisterPage("DEPLOY", DeployPage.build)
end

return DeployPage
