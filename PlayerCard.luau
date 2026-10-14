-- PlayerCard: the banner shown for a player (card background, emblem, name, title, level).
--   local card = PlayerCard.Build(parent, scale, position, anchor)
--   card.Set({ Name = "...", Level = 12, Card = "Slate", Emblem = "Rookie", Title = "Rookie" })
--   PlayerCard.Options(player) -> the same table for any player in the server (reads the Cos* player attributes CosmeticsService sets)
-- Designed at 320 x 112 and scaled with a UIScale, so it looks the same at any size.
local Theme = require(script.Parent.Theme)
local Cosmetics = require(script.Parent.Cosmetics)

local PlayerCard = {}
PlayerCard.W, PlayerCard.H = 320, 112

local LEFT, CENTER = Enum.TextXAlignment.Left, Enum.TextXAlignment.Center
local C0 = Color3.new()
local DARK = Color3.fromRGB(20, 20, 22)

-- ---------------------------------------------------------------- background patterns (decorative, drawn on the right 2/3 of the card)
local function pattern(parent, kind, color)
	local function bar(size, pos, rot, alpha)
		local f = Theme.Frame(parent, size, pos, Vector2.new(0.5, 0.5), color, alpha or 0.9)
		f.Rotation = rot or 0
		return f
	end
	if kind == "Stripes" then
		for i = 0, 9 do bar(UDim2.fromOffset(10, 260), UDim2.fromOffset(130 + i * 26, 56), 28) end
	elseif kind == "Chevron" then
		for i = 0, 6 do
			local x = 150 + i * 28
			bar(UDim2.fromOffset(8, 56), UDim2.fromOffset(x, 40), -35, 0.88)
			bar(UDim2.fromOffset(8, 56), UDim2.fromOffset(x, 74), 35, 0.88)
		end
	elseif kind == "Dots" then
		for x = 0, 11 do
			for y = 0, 4 do
				local d = bar(UDim2.fromOffset(6, 6), UDim2.fromOffset(126 + x * 17, 12 + y * 24), 0, 0.82)
				Theme.Round(d, 3)
			end
		end
	elseif kind == "Grid" then
		for i = 0, 11 do bar(UDim2.fromOffset(1, 130), UDim2.fromOffset(120 + i * 18, 56), 0, 0.8) end
		for j = 0, 5 do bar(UDim2.fromOffset(340, 1), UDim2.fromOffset(250, 8 + j * 20), 0, 0.8) end
	end
end

-- ---------------------------------------------------------------- emblem
-- draws an emblem into a square area of `size` px. Returns the holder frame.
function PlayerCard.Emblem(parent, id, size, pos, anchor)
	local def = Cosmetics.Get("Emblem", id) or Cosmetics.Get("Emblem", "Rookie")
	local box = Theme.Frame(parent, UDim2.fromOffset(size, size), pos, anchor, C0, 1)
	local col = def.Color
	local C5, A5 = UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5)
	local markColor = DARK
	if def.Shape == "Circle" then
		Theme.Round(Theme.Frame(box, UDim2.fromScale(0.86, 0.86), C5, A5, col, 0), size)
	elseif def.Shape == "Diamond" then
		local f = Theme.Frame(box, UDim2.fromScale(0.6, 0.6), C5, A5, col, 0)
		f.Rotation = 45
		Theme.Round(f, math.floor(size * 0.05))
	elseif def.Shape == "Square" then
		Theme.Round(Theme.Frame(box, UDim2.fromScale(0.74, 0.74), C5, A5, col, 0), math.floor(size * 0.08))
	else -- Ring / Crosshair: outline shapes, the mark is drawn in the shape color
		markColor = col
		local ring = Theme.Frame(box, UDim2.fromScale(0.8, 0.8), C5, A5, C0, 1)
		Theme.Round(ring, size)
		local s = Instance.new("UIStroke")
		s.Color, s.Thickness = col, math.max(2, size * 0.07)
		s.Parent = ring
		if def.Shape == "Crosshair" then
			local t = math.max(2, size * 0.06)
			Theme.Frame(box, UDim2.new(0, t, 0.34, 0), UDim2.fromScale(0.5, 0.5), A5, col, 0)
			Theme.Frame(box, UDim2.new(0.34, 0, 0, t), UDim2.fromScale(0.5, 0.5), A5, col, 0)
			Theme.Round(Theme.Frame(box, UDim2.fromOffset(size * 0.12, size * 0.12), C5, A5, col, 0), size)
		end
	end
	if def.Mark and def.Mark ~= "" then
		Theme.Label(box, def.Mark, math.max(8, math.floor(size * 0.34)), markColor, CENTER, Theme.Display)
	end
	return box
end

-- ---------------------------------------------------------------- card
function PlayerCard.Build(parent, scale, pos, anchor)
	scale = scale or 1
	local W, H = PlayerCard.W, PlayerCard.H
	local outer = Theme.Frame(parent, UDim2.fromOffset(W * scale, H * scale), pos, anchor, C0, 1)
	outer.ClipsDescendants = true
	local canvas = Theme.Frame(outer, UDim2.fromOffset(W, H), nil, nil, Color3.new(1, 1, 1), 0)
	local ui = Instance.new("UIScale")
	ui.Scale = scale
	ui.Parent = canvas
	Theme.Round(canvas, 6)
	Theme.Stroke(canvas, Theme.Dim, 1, 0.5)
	local grad = Instance.new("UIGradient")
	grad.Rotation = 20
	grad.Parent = canvas
	local deco = Theme.Frame(canvas, UDim2.fromScale(1, 1), nil, nil, C0, 1)
	deco.ClipsDescendants = true
	local plate = Theme.Frame(canvas, UDim2.fromOffset(88, 88), UDim2.fromOffset(12, 12), nil, C0, 0.5)
	Theme.Round(plate, 6)
	local nameLbl = Theme.Label(canvas, "", 28, Theme.Text, LEFT, Theme.Display, UDim2.fromOffset(114, 14), UDim2.fromOffset(196, 36))
	nameLbl.TextTruncate = Enum.TextTruncate.AtEnd
	local titleLbl = Theme.Label(canvas, "", 14, Theme.Accent, LEFT, Theme.Display, UDim2.fromOffset(114, 52), UDim2.fromOffset(196, 20))
	local levelLbl = Theme.Label(canvas, "", 13, Theme.Dim, LEFT, Theme.Display, UDim2.fromOffset(114, 78), UDim2.fromOffset(196, 18))

	local card = { Frame = outer }
	local emblem
	function card.Set(o)
		local def = Cosmetics.Get("Card", o.Card) or Cosmetics.Get("Card", "Slate")
		grad.Color = ColorSequence.new(def.A, def.B)
		for _, c in deco:GetChildren() do c:Destroy() end
		pattern(deco, def.Pattern, def.PatternColor)
		if emblem then emblem:Destroy() end
		emblem = PlayerCard.Emblem(plate, o.Emblem, 76, UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5))
		nameLbl.Text = o.Name or ""
		local title = Cosmetics.Get("Title", o.Title) or Cosmetics.Get("Title", "Rookie")
		titleLbl.Text = title.Name:upper()
		titleLbl.TextColor3 = def.Accent
		levelLbl.Text = o.Level and ("LEVEL %d"):format(o.Level) or ""
	end
	card.Set({})
	return card
end

-- what a player has equipped (server-set attributes, replicated to everyone)
function PlayerCard.Options(plr)
	local ls = plr:FindFirstChild("leaderstats")
	local lvl = ls and ls:FindFirstChild("Level")
	return {
		Name = plr.DisplayName, Level = lvl and lvl.Value or nil,
		Card = plr:GetAttribute("CosCard"), Emblem = plr:GetAttribute("CosEmblem"), Title = plr:GetAttribute("CosTitle"),
	}
end

return PlayerCard
