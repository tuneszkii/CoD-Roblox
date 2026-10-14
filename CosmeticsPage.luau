-- CosmeticsPage: the COSMETICS tab of the main menu. Register with CosmeticsPage.Register(MainMenu) before MainMenu.new.
--
-- Three columns (categories | items | preview + details), same look as the Armory:
--   nav     OPERATORS, PLAYER CARDS, EMBLEMS, TITLES, EMOTES, TRACERS (each shows what you have equipped)
--   items   a grid of everything in the category (locked items show the level they need)
--   detail  live preview on top: operators spin on a pad, emotes play on your operator, cards / emblems / titles show on your card,
--           tracers fly across a strip. Below: rarity, description, unlock progress, EQUIP / BUY FORWARD (emotes: pick a wheel slot).
-- Unlocks: reach the item's level, or buy it early with credits (same buy-forward idea as the Armory, price drops as you get closer).
local GuiService = game:GetService("GuiService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local Theme = require(script.Parent.Theme)
local Widgets = require(script.Parent.Widgets)
local Cosmetics = require(script.Parent.Cosmetics)
local Emotes = require(script.Parent.Emotes)
local Progression = require(script.Parent.Progression)
local CC = require(script.Parent.CosmeticsClient)
local PlayerCard = require(script.Parent.PlayerCard)
local RigPreview = require(script.Parent.RigPreview)

local CosmeticsPage = {}

local LEFT, RIGHT, CENTER = Enum.TextXAlignment.Left, Enum.TextXAlignment.Right, Enum.TextXAlignment.Center
local C0 = Color3.new()
local RESERVE = 232 -- height of the preview area at the top of the detail column
local localPlayer = Players.LocalPlayer

local function commas(n)
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

local function clear(frame)
	for _, c in frame:GetChildren() do
		if not c:IsA("UIListLayout") and not c:IsA("UIGridLayout") and not c:IsA("UIPadding") then c:Destroy() end
	end
end

-- ---------------------------------------------------------------- columns / rows / tiles
-- opts: Grid = true for a tile grid, Reserve = pixels kept free above the scrolling area (for the preview)
local function column(parent, xScale, xOff, wScale, wOff, title, opts)
	opts = opts or {}
	local reserve = opts.Reserve or 0
	local p = Theme.Glass(parent, UDim2.new(wScale, wOff, 1, -54), UDim2.new(xScale, xOff, 0, 54))
	p.BackgroundTransparency = 0.25
	local titleLbl = Theme.Label(p, title, 13, Theme.Accent, LEFT, Theme.Display, UDim2.fromOffset(14, 6), UDim2.new(1, -28, 0, 20))
	Theme.Frame(p, UDim2.new(1, -28, 0, 1), UDim2.fromOffset(14, 28), nil, Theme.Accent, 0.7)
	local sf = Instance.new("ScrollingFrame")
	sf.BackgroundTransparency, sf.BorderSizePixel = 1, 0
	sf.Position, sf.Size = UDim2.fromOffset(8, 36 + reserve), UDim2.new(1, -12, 1, -(44 + reserve))
	sf.ScrollBarThickness, sf.ScrollBarImageColor3 = 5, Theme.Accent
	sf.CanvasSize, sf.AutomaticCanvasSize = UDim2.new(), Enum.AutomaticSize.Y
	sf.Parent = p
	if opts.Grid then
		local pad = Instance.new("UIPadding")
		pad.PaddingTop, pad.PaddingLeft, pad.PaddingBottom = UDim.new(0, 4), UDim.new(0, 4), UDim.new(0, 4)
		pad.Parent = sf
		local g = Instance.new("UIGridLayout")
		g.CellSize, g.CellPadding, g.SortOrder = UDim2.fromOffset(136, 118), UDim2.fromOffset(8, 8), Enum.SortOrder.LayoutOrder
		g.Parent = sf
	else
		local list = Instance.new("UIListLayout")
		list.Padding, list.SortOrder = UDim.new(0, 5), Enum.SortOrder.LayoutOrder
		list.Parent = sf
	end
	return p, sf, titleLbl
end

-- o = { Small, Name, Active, Selected, OnClick }
local function row(parent, order, o)
	local b = Instance.new("TextButton")
	b.AutoButtonColor, b.Text, b.LayoutOrder, b.BorderSizePixel = false, "", order, 0
	b.Size, b.BackgroundColor3 = UDim2.new(1, -8, 0, 52), Theme.Panel
	b.BackgroundTransparency = o.Selected and 0.15 or 0.4
	Theme.Round(b, 5)
	Theme.Stroke(b, o.Selected and Theme.Accent or Theme.Dim, o.Selected and 2 or 1, o.Selected and 0.1 or 0.75)
	Theme.Label(b, o.Small, 10, o.Selected and Theme.Accent or Theme.Dim, LEFT, Theme.Display, UDim2.fromOffset(14, 5), UDim2.new(1, -28, 0, 12))
	Theme.Label(b, o.Name, 18, Theme.Text, LEFT, Theme.Display, UDim2.fromOffset(14, 18), UDim2.new(1, -28, 0, 24))
	b.Parent = parent
	Widgets.Selectable(b)
	b.Activated:Connect(o.OnClick)
	return b
end

-- a small rectangle positioned from the horizontal centre of its parent (used for the mini operator figure)
local function rect(parent, x, y, w, h, color, round)
	local f = Theme.Frame(parent, UDim2.fromOffset(w, h), UDim2.new(0.5, x, 0, y), nil, color, 0)
	if round then Theme.Round(f, round) end
	return f
end

local RAINBOW = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 80, 80)), ColorSequenceKeypoint.new(0.2, Color3.fromRGB(255, 220, 80)),
	ColorSequenceKeypoint.new(0.4, Color3.fromRGB(100, 255, 120)), ColorSequenceKeypoint.new(0.6, Color3.fromRGB(80, 220, 255)),
	ColorSequenceKeypoint.new(0.8, Color3.fromRGB(120, 120, 255)), ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 100, 230)),
})

-- ---------------------------------------------------------------- what each tile shows (area is 124 x 80)
local DRAW = {}

function DRAW.Operator(area, op)
	if op.Avatar then
		Theme.Label(area, "YOUR\nAVATAR", 16, Theme.Dim, CENTER, Theme.Display)
		return
	end
	rect(area, -7, 3, 14, 14, op.Head or op.Skin, 7)
	rect(area, -7, 7, 14, 3, op.Accent)
	rect(area, -13, 18, 26, 26, op.Torso)
	rect(area, -10, 21, 20, 18, op.Vest)
	rect(area, -20, 18, 7, 24, op.Sleeve)
	rect(area, 13, 18, 7, 24, op.Sleeve)
	rect(area, -20, 40, 7, 5, op.Skin)
	rect(area, 13, 40, 7, 5, op.Skin)
	rect(area, -12, 44, 11, 24, op.Pants)
	rect(area, 1, 44, 11, 24, op.Pants)
	rect(area, -13, 68, 12, 8, op.Boots)
	rect(area, 1, 68, 12, 8, op.Boots)
end

function DRAW.Card(area, def)
	local card = PlayerCard.Build(area, 0.38, UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5))
	card.Set({ Card = def.Id, Emblem = "Rookie", Title = "Rookie" })
end

function DRAW.Emblem(area, def)
	PlayerCard.Emblem(area, def.Id, 64, UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5))
end

function DRAW.Title(area, def)
	local l = Theme.Label(area, def.Name:upper(), 17, Cosmetics.RarityColor(def), CENTER, Theme.Display, UDim2.fromOffset(6, 0), UDim2.new(1, -12, 1, 0))
	l.TextWrapped = true
end

function DRAW.Emote(area, def)
	local ring = Theme.Frame(area, UDim2.fromOffset(50, 50), UDim2.new(0.5, 0, 0.5, -4), Vector2.new(0.5, 0.5), C0, 1)
	Theme.Round(ring, 25)
	Theme.Stroke(ring, Theme.Accent, 2, 0.2)
	Theme.Label(ring, def.Name:sub(1, 1), 28, Theme.Accent, CENTER, Theme.Display)
	Theme.Label(area, ("%.1fs"):format(def.Duration), 11, Theme.Dim, CENTER, Theme.Display, UDim2.new(0, 0, 1, -16), UDim2.new(1, 0, 0, 14))
end

function DRAW.Tracer(area, def)
	local glow = Theme.Frame(area, UDim2.new(0.84, 0, 0, 12), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5), def.Color, 0.78)
	Theme.Round(glow, 6)
	local core = Theme.Frame(area, UDim2.new(0.84, 0, 0, 3), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5), def.Color, 0)
	local g = Instance.new("UIGradient")
	g.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0) })
	g.Color = def.Rainbow and RAINBOW or ColorSequence.new(def.Color)
	g.Parent = core
end

-- o = { Def, Locked, LockText, Equipped, Selected, OnClick }
local function tile(parent, order, o)
	local def = o.Def
	local b = Instance.new("TextButton")
	b.AutoButtonColor, b.Text, b.LayoutOrder, b.BorderSizePixel = false, "", order, 0
	b.BackgroundColor3, b.BackgroundTransparency = Theme.Panel, o.Selected and 0.1 or 0.4
	Theme.Round(b, 5)
	Theme.Stroke(b, (o.Selected or o.Equipped) and Theme.Accent or Theme.Dim, o.Selected and 2 or 1, (o.Selected or o.Equipped) and 0.1 or 0.75)
	local area = Theme.Frame(b, UDim2.new(1, -12, 1, -42), UDim2.fromOffset(6, 6), nil, C0, 0.55)
	Theme.Round(area, 4)
	area.ClipsDescendants = true
	DRAW[def.Category](area, def)
	if o.Locked then
		local shade = Theme.Frame(area, UDim2.fromScale(1, 1), nil, nil, C0, 0.5)
		shade.ZIndex = 5
		local lbl = Theme.Label(shade, o.LockText, 15, Theme.Danger, CENTER, Theme.Display)
		lbl.ZIndex = 6
	elseif o.Equipped then
		local chip = Theme.Frame(area, UDim2.fromOffset(62, 14), UDim2.fromOffset(4, 4), nil, C0, 0.3)
		chip.ZIndex = 5
		Theme.Round(chip, 3)
		Theme.Label(chip, "EQUIPPED", 10, Theme.Accent, CENTER, Theme.Display).ZIndex = 6
	end
	Theme.Frame(b, UDim2.new(1, -12, 0, 3), UDim2.new(0, 6, 1, -33), nil, Cosmetics.RarityColor(def), 0)
	Theme.Label(b, def.Name:upper(), 15, o.Locked and Theme.Dim or Theme.Text, LEFT, Theme.Display, UDim2.new(0, 8, 1, -28), UDim2.new(1, -16, 0, 22))
	b.Parent = parent
	Widgets.Selectable(b)
	b.Activated:Connect(o.OnClick)
	return b
end

-- ---------------------------------------------------------------- the page
function CosmeticsPage.build(holder, menu)
	local page = { Cat = "Operator", Sel = nil, Active = false, T0 = os.clock(), PMode = "Spin" }

	local head = Theme.Frame(holder, UDim2.new(1, 0, 0, 46), nil, nil, C0, 1)
	local crumb = Theme.Label(head, "COSMETICS", 26, Theme.Text, LEFT, Theme.Display, UDim2.fromOffset(4, 0), UDim2.new(1, -420, 1, 0))
	local msgLbl = Theme.Label(head, "", 14, Theme.Warn, RIGHT, Theme.Display, UDim2.new(1, 0, 0, 0), UDim2.fromOffset(420, 46), Vector2.new(1, 0))

	local navPanel, nav = column(holder, 0, 0, 0.22, -6, "CATEGORIES")
	local listPanel, list, titleList = column(holder, 0.22, 0, 0.40, -6, "ITEMS", { Grid = true })
	local detPanel, det = column(holder, 0.62, 0, 0.38, 0, "PREVIEW", { Reserve = RESERVE })
	navPanel.Position, listPanel.Position = UDim2.new(0, 0, 0, 54), UDim2.new(0.22, 0, 0, 54)

	local function say(text)
		msgLbl.Text = text or ""
		local token = (page.MsgToken or 0) + 1
		page.MsgToken = token
		task.delay(3, function() if page.MsgToken == token then msgLbl.Text = "" end end)
	end

	-- -------------------------------------------------------------- preview (built once, reused for every item)
	local previewHolder = Theme.Frame(detPanel, UDim2.new(1, -16, 0, RESERVE - 6), UDim2.fromOffset(8, 36), nil, C0, 0.45)
	Theme.Round(previewHolder, 5)
	previewHolder.ClipsDescendants = true

	local vp = Instance.new("ViewportFrame")
	vp.Size, vp.BackgroundTransparency, vp.BorderSizePixel = UDim2.fromScale(1, 1), 1, 0
	vp.Parent = previewHolder
	local rig = RigPreview.new(vp)
	rig:SetOperator(Cosmetics.Operator("Default"))
	rig:Update(0.5, nil, 0)

	local cardHolder = Theme.Frame(previewHolder, UDim2.fromScale(1, 1), nil, nil, C0, 1)
	local bigCard = PlayerCard.Build(cardHolder, 1.2, UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5))

	local strip = Theme.Frame(previewHolder, UDim2.fromScale(1, 1), nil, nil, Color3.fromRGB(10, 12, 16), 0.1)
	local streak = Theme.Frame(strip, UDim2.fromOffset(60, 12), UDim2.fromScale(-0.3, 0.5), Vector2.new(0, 0.5), C0, 1)
	local streakGlow = Theme.Frame(streak, UDim2.fromScale(1, 1), nil, nil, Color3.new(1, 1, 1), 0.75)
	Theme.Round(streakGlow, 6)
	local streakCore = Theme.Frame(streak, UDim2.new(1, 0, 0, 4), UDim2.fromScale(0, 0.5), Vector2.new(0, 0.5), Color3.new(1, 1, 1), 0)
	local streakGrad = Instance.new("UIGradient")
	streakGrad.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0) })
	streakGrad.Parent = streakCore
	local glowGrad = streakGrad:Clone()
	glowGrad.Parent = streakGlow
	Theme.Label(strip, "MUZZLE", 11, Theme.Dim, LEFT, Theme.Display, UDim2.fromOffset(10, 8), UDim2.fromOffset(80, 14))
	Theme.Label(strip, "TARGET", 11, Theme.Dim, RIGHT, Theme.Display, UDim2.new(1, -10, 0, 8), UDim2.fromOffset(80, 14), Vector2.new(1, 0))
	Theme.Round(Theme.Frame(strip, UDim2.fromOffset(8, 8), UDim2.new(0, 8, 0.5, 0), Vector2.new(0, 0.5), Theme.Dim, 0), 4)
	local target = Theme.Frame(strip, UDim2.fromOffset(36, 36), UDim2.new(1, -14, 0.5, 0), Vector2.new(1, 0.5), C0, 1)
	Theme.Round(target, 18)
	Theme.Stroke(target, Theme.Dim, 2, 0.4)

	local function showPreview(mode)
		vp.Visible = mode == "Spin" or mode == "Emote"
		cardHolder.Visible = mode == "Card"
		strip.Visible = mode == "Tracer"
		page.PMode = mode
		page.T0 = os.clock()
	end

	local function tick()
		local t = os.clock() - page.T0
		if page.PMode == "Spin" then
			rig:Update(t * 0.8 + 0.5, nil, 0)
		elseif page.PMode == "Emote" then
			local def = Emotes.Defs[page.PEmote]
			if not def then return end
			local len = math.min(def.Duration, 3.4)
			local lt = t % (len + 0.9)
			local pose, w = nil, 0
			if lt <= len then
				pose, w = Emotes.Sample(page.PEmote, lt)
				if pose and w and lt > len - 0.3 then w *= Emotes.Smooth((len - lt) / 0.3) end
			end
			rig:Update(0.45, pose, w or 0)
		elseif page.PMode == "Tracer" and page.PTracer then
			local lt = (t % 1.5) / 0.55 -- 0..1 flight, then a pause
			if lt <= 1 then
				streak.Visible = true
				streak.Position = UDim2.new(-0.25 + lt * 1.3, 0, 0.5, 0)
			else
				streak.Visible = false
			end
		end
	end

	-- -------------------------------------------------------------- reading the data
	local function data() return CC.Data end

	local function equippedName(cat)
		local E = data().Equipped
		if cat == "Emote" then
			local n = 0
			for _, e in E.Emotes do
				if e ~= "" then n += 1 end
			end
			return ("%d / %d SLOTS"):format(n, Cosmetics.EmoteSlots)
		end
		local def = Cosmetics.Get(cat, E[cat])
		return def and def.Name:upper() or "NONE"
	end

	local function isEquipped(cat, id)
		local E = data().Equipped
		if cat == "Emote" then return table.find(E.Emotes, id) ~= nil end
		return E[cat] == id
	end

	local function defaultSel(cat)
		local E = data().Equipped
		if cat == "Emote" then
			for _, e in E.Emotes do
				if e ~= "" then return e end
			end
			return Cosmetics.List("Emote")[1].Id
		end
		return E[cat]
	end

	local function progress(cat, id)
		local D = data()
		return Cosmetics.Progress(D.XP, D.Owned, cat, id)
	end

	-- -------------------------------------------------------------- actions
	local function equip(cat, id, slot)
		task.spawn(function()
			local ok, msg = CC.Equip(cat, id, slot)
			if not ok then
				say(msg)
			elseif cat == "Operator" then
				say("OPERATOR APPLIES ON YOUR NEXT SPAWN")
			elseif cat == "Emote" then
				say(id == "" and "SLOT CLEARED" or "EMOTE ASSIGNED")
			else
				say("EQUIPPED")
			end
		end)
	end

	local function buy(cat, id)
		task.spawn(function()
			local ok, msg = CC.Buy(cat, id)
			say(ok and "UNLOCKED" or msg)
		end)
	end

	-- -------------------------------------------------------------- detail panel
	local DESC = {
		Card = "Your banner. Other players see it on the results screen.",
		Emblem = "The badge on your player card.",
		Title = "The line of text under your name on your card.",
		Tracer = "Every player sees your bullets in this style. Takes effect immediately.",
	}

	local function showDetail(cat, id)
		clear(det)
		local def = Cosmetics.Get(cat, id)
		if not def then return end
		local p = progress(cat, id)
		local order = 0
		local function nextOrder()
			order += 1
			return order
		end
		local function textBlock(text, size, color, font, height)
			local l = Theme.Label(det, text, size, color, LEFT, font or Theme.Body, nil, UDim2.new(1, -8, 0, height or 20))
			l.LayoutOrder = nextOrder()
			l.TextWrapped, l.TextYAlignment = true, Enum.TextYAlignment.Top
			return l
		end
		textBlock(("%s  |  %s"):format(Cosmetics.Singular[cat], def.Rarity:upper()), 12, Cosmetics.RarityColor(def), Theme.Display, 16)
		textBlock(def.Name:upper(), 30, Theme.Text, Theme.Display, 38)
		local desc = def.Desc
		if cat == "Operator" then
			desc = (def.Desc or "") .. "\nROLE  " .. def.Role
		elseif cat == "Emote" then
			desc = ("A %.1f second emote played in third person. Move, jump or shoot to cancel.%s"):format(def.Duration, def.Duration > 6 and " It loops until you do." or "")
		else
			desc = desc or DESC[cat]
		end
		if desc then
			local l = textBlock(desc, 14, Theme.Dim, Theme.Body, 44)
			l.AutomaticSize = Enum.AutomaticSize.Y
			l.Size = UDim2.new(1, -8, 0, 20)
		end

		if not p.Unlocked and p.Reward then -- achievement / mastery reward: nothing to buy
			local box = Theme.Glass(det, UDim2.new(1, -8, 0, 60))
			box.LayoutOrder = nextOrder()
			Theme.Label(box, "LOCKED REWARD", 12, Theme.Danger, LEFT, Theme.Display, UDim2.fromOffset(12, 6), UDim2.new(1, -24, 0, 14))
			Theme.Label(box, p.Reward, 15, Theme.Text, LEFT, Theme.Display, UDim2.fromOffset(12, 24), UDim2.new(1, -24, 0, 28))
			return
		end
		if not p.Unlocked then
			local box = Theme.Glass(det, UDim2.new(1, -8, 0, 92))
			box.LayoutOrder = nextOrder()
			Theme.Label(box, "LOCKED", 12, Theme.Danger, LEFT, Theme.Display, UDim2.fromOffset(12, 6), UDim2.new(1, -24, 0, 14))
			Theme.Label(box, ("REACH LEVEL %d  |  %s XP TO GO"):format(p.Level, commas(p.Remaining)), 15, Theme.Text, LEFT, Theme.Display,
				UDim2.fromOffset(12, 22), UDim2.new(1, -24, 0, 20))
			local back = Theme.Frame(box, UDim2.new(1, -24, 0, 8), UDim2.fromOffset(12, 50), nil, C0, 0.45)
			Theme.Round(back, 4)
			Theme.Round(Theme.Frame(back, UDim2.fromScale(math.max(p.Frac, 0.01), 1), nil, nil, Theme.Accent), 4)
			Theme.Label(box, ("%d%%  |  buy forward price drops as you get closer"):format(math.floor(p.Frac * 100)), 11, Theme.Dim, LEFT, Theme.Body,
				UDim2.fromOffset(12, 64), UDim2.new(1, -24, 0, 16))
			local afford = data().Credits >= p.Price
			local b = Widgets.FlatButton(det, ("BUY FORWARD  -  %s CR"):format(commas(p.Price)), UDim2.new(1, -8, 0, 44), nil, nil, afford)
			b.LayoutOrder, b.TextSize = nextOrder(), 18
			b.Activated:Connect(function() buy(cat, id) end)
			return
		end

		if cat == "Emote" then
			textBlock("PUT IT ON THE EMOTE WHEEL  (PRESS A SLOT; PRESS AGAIN TO CLEAR)", 12, Theme.Accent, Theme.Display, 16)
			local bar = Theme.Frame(det, UDim2.new(1, -8, 0, 42), nil, nil, C0, 1)
			bar.LayoutOrder = nextOrder()
			local lay = Instance.new("UIListLayout")
			lay.FillDirection, lay.Padding = Enum.FillDirection.Horizontal, UDim.new(0, 6)
			lay.Parent = bar
			local E = data().Equipped
			for i = 1, Cosmetics.EmoteSlots do
				local mine = E.Emotes[i] == id
				local b = Widgets.FlatButton(bar, tostring(i), UDim2.fromOffset(42, 42), nil, nil, mine)
				b.TextSize = 20
				b.Activated:Connect(function() equip("Emote", mine and "" or id, i) end)
			end
			local names = {}
			for i = 1, Cosmetics.EmoteSlots do
				local e = E.Emotes[i]
				names[i] = ("%d  %s"):format(i, e ~= "" and e:upper() or "-")
			end
			textBlock(table.concat(names, "    "), 12, Theme.Dim, Theme.Display, 34)
		else
			local on = isEquipped(cat, id)
			local b = Widgets.FlatButton(det, on and "EQUIPPED" or "EQUIP", UDim2.new(1, -8, 0, 44), nil, nil, not on)
			b.LayoutOrder, b.TextSize = nextOrder(), 18
			b.Activated:Connect(function() if not on then equip(cat, id) end end)
		end
		textBlock("The Emote key (default B) opens the wheel in a match.", 12, Theme.Dim, Theme.Body, 18).Visible = cat == "Emote"
		textBlock("Operators are placeholder rigs for now. They change your colors on the next spawn.", 12, Theme.Dim, Theme.Body, 32).Visible = cat == "Operator"
	end

	-- -------------------------------------------------------------- preview content for the highlighted item
	local function updatePreview(cat, id)
		local D = data()
		if cat == "Operator" then
			rig:SetOperator(Cosmetics.Operator(id))
			showPreview("Spin")
		elseif cat == "Emote" then
			rig:SetOperator(Cosmetics.Operator(D.Equipped.Operator) or Cosmetics.Operator("Default"))
			page.PEmote = id
			showPreview("Emote")
		elseif cat == "Tracer" then
			local def = Cosmetics.Get("Tracer", id)
			page.PTracer = def
			local w = math.floor(def.Length * 12)
			local h = math.max(4, math.floor(def.Width * 40))
			streak.Size = UDim2.fromOffset(w, h + 8)
			streakCore.Size = UDim2.new(1, 0, 0, h)
			streakGlow.BackgroundColor3, streakCore.BackgroundColor3 = def.Color, def.Color
			streakGlow.BackgroundTransparency = (def.Trail or def.Sparks) and 0.6 or 0.85
			streakGrad.Color = def.Rainbow and RAINBOW or ColorSequence.new(def.Color)
			glowGrad.Color = streakGrad.Color
			showPreview("Tracer")
		else
			local o = { Name = localPlayer.DisplayName, Level = (Progression.LevelFromXP(D.XP)), Card = D.Equipped.Card, Emblem = D.Equipped.Emblem, Title = D.Equipped.Title }
			o[cat] = id
			bigCard.Set(o)
			showPreview("Card")
		end
	end

	-- -------------------------------------------------------------- render
	local function render()
		if not data() then
			clear(nav)
			clear(list)
			clear(det)
			crumb.Text = "COSMETICS  >  LOADING..."
			return
		end
		local cat = page.Cat
		if not page.Sel or not Cosmetics.Get(cat, page.Sel) then page.Sel = defaultSel(cat) end
		crumb.Text = ("COSMETICS  >  %s"):format(Cosmetics.Labels[cat])

		clear(nav)
		for i, c in Cosmetics.Categories do
			row(nav, i, { Small = Cosmetics.Labels[c], Name = equippedName(c), Selected = c == cat, OnClick = function()
				page.Cat, page.Sel = c, nil
				render()
			end })
		end

		clear(list)
		local items = Cosmetics.List(cat)
		local unlocked = 0
		for i, def in items do
			local p = progress(cat, def.Id)
			if p.Unlocked then unlocked += 1 end
			tile(list, i, { Def = def, Locked = not p.Unlocked, LockText = ("LV %d"):format(def.Level), Equipped = isEquipped(cat, def.Id),
				Selected = page.Sel == def.Id, OnClick = function()
					page.Sel = def.Id
					render()
				end })
		end
		titleList.Text = ("%s  |  %d / %d UNLOCKED"):format(Cosmetics.Labels[cat], unlocked, #items)

		showDetail(cat, page.Sel)
		updatePreview(cat, page.Sel)
	end
	page.render = render

	CC.OnChanged(function()
		if page.Active then render() end
	end)

	local conn
	return {
		Show = function()
			page.Active = true
			page.T0 = os.clock()
			if not conn then conn = RunService.RenderStepped:Connect(tick) end
			task.spawn(function()
				CC.Load()
				if page.Active then render() end
			end)
		end,
		Hide = function()
			page.Active = false
			if conn then
				conn:Disconnect()
				conn = nil
			end
		end,
		Focus = function()
			local first = list:FindFirstChildWhichIsA("TextButton", true)
			if first then GuiService.SelectedObject = first end
		end,
	}
end

function CosmeticsPage.Register(MainMenu)
	MainMenu.RegisterPage("COSMETICS", CosmeticsPage.build)
end

return CosmeticsPage
