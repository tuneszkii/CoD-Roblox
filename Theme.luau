-- Shared UI look: dark glass panels, amber accent, condensed type. Original styling (no franchise assets).
local Theme = {}

Theme.Accent = Color3.fromRGB(255, 178, 64)
Theme.Panel = Color3.fromRGB(14, 17, 20)
Theme.PanelAlpha = 0.35
Theme.Text = Color3.fromRGB(240, 242, 244)
Theme.Dim = Color3.fromRGB(150, 158, 166)
Theme.Warn = Color3.fromRGB(255, 150, 50)
Theme.Danger = Color3.fromRGB(235, 70, 70)
Theme.Plate = Color3.fromRGB(122, 190, 235)
Theme.Good = Color3.fromRGB(120, 220, 140)
Theme.TeamColor = { Alpha = Color3.fromRGB(90, 160, 255), Bravo = Color3.fromRGB(255, 154, 60) }
Theme.TeamHex = { Alpha = "#5aa0ff", Bravo = "#ff9a3c" } -- for rich text:  <font color="#5aa0ff">
Theme.Display = Enum.Font.Oswald     -- numbers / headings
Theme.Body = Enum.Font.GothamMedium  -- labels

function Theme.Frame(parent, size, pos, anchor, color, alpha)
	local f = Instance.new("Frame")
	f.Size, f.Position, f.AnchorPoint = size, pos or UDim2.new(), anchor or Vector2.zero
	f.BackgroundColor3, f.BackgroundTransparency, f.BorderSizePixel = color or Theme.Panel, alpha or 0, 0
	f.Parent = parent
	return f
end

function Theme.Round(obj, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r or 4)
	c.Parent = obj
	return c
end

function Theme.Stroke(obj, color, thickness, alpha)
	local s = Instance.new("UIStroke")
	s.Color, s.Thickness, s.Transparency = color or Theme.Dim, thickness or 1, alpha or 0.6
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = obj
	return s
end

function Theme.Label(parent, text, size, color, align, font, pos, boxSize, anchor)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font, l.TextSize, l.TextColor3 = font or Theme.Body, size, color or Theme.Text
	l.TextXAlignment, l.Text = align or Enum.TextXAlignment.Left, text or ""
	l.TextYAlignment = Enum.TextYAlignment.Center
	l.TextStrokeTransparency = 0.75
	l.Position, l.Size, l.AnchorPoint = pos or UDim2.new(), boxSize or UDim2.fromScale(1, 1), anchor or Vector2.zero
	l.RichText = true
	l.Parent = parent
	return l
end

-- glass panel: translucent dark fill + hairline stroke
function Theme.Glass(parent, size, pos, anchor)
	local f = Theme.Frame(parent, size, pos, anchor, Theme.Panel, Theme.PanelAlpha)
	Theme.Round(f, 5)
	Theme.Stroke(f, Theme.Dim, 1, 0.75)
	return f
end

-- small key-cap chip
function Theme.Chip(parent, text, size, pos, anchor)
	local f = Theme.Frame(parent, size or UDim2.fromOffset(22, 18), pos, anchor, Color3.fromRGB(0, 0, 0), 0.35)
	Theme.Round(f, 3)
	Theme.Stroke(f, Theme.Accent, 1, 0.55)
	local t = Theme.Label(f, text, 11, Theme.Accent, Enum.TextXAlignment.Center, Theme.Display)
	return f, t
end

function Theme.Spaced(name) -- "DoubleTime" -> "DOUBLE TIME"
	return (name:gsub("(%l)(%u)", "%1 %2")):upper()
end

return Theme
