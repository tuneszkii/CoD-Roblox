-- ScreenFX: full-screen effects shared by the match and death presentations.
--   ScreenFX.Fade(alpha, seconds)               0 = clear, 1 = black
--   ScreenFX.Letterbox(on, seconds)             cinematic bars
--   ScreenFX.Vignette(color, alpha, seconds)    coloured screen edges (0 = off)
--   ScreenFX.Flash(color, alpha, seconds)       full-screen flash that fades out
--   ScreenFX.Grade(saturation, blur, seconds)   colour grading (0 = normal, -1 = grey) + blur size (0 = none)
--   ScreenFX.Reset(seconds)                     everything back to normal
-- One ScreenGui above the HUD and the menu. It never blocks input.
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")

local ScreenFX = {}

local LETTERBOX = 0.11 -- bar height as a fraction of the screen

local gui, black, barTop, barBottom, flash, vignette, edges, cc, blur
local running = setmetatable({}, { __mode = "k" }) -- [instance] = tween in progress

local function to(obj, seconds, props)
	local old = running[obj]
	if old then old:Cancel() end
	if not seconds or seconds <= 0 then
		running[obj] = nil
		for k, v in props do obj[k] = v end
		return
	end
	local tw = TweenService:Create(obj, TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props)
	running[obj] = tw
	tw:Play()
end

local function solid(parent, name, color)
	local f = Instance.new("Frame")
	f.Name, f.BorderSizePixel, f.BackgroundColor3, f.BackgroundTransparency = name, 0, color, 1
	f.Size = UDim2.fromScale(1, 1)
	f.Active = false
	f.Parent = parent
	return f
end

local function ensure()
	if gui and gui.Parent then return end
	gui = Instance.new("ScreenGui")
	gui.Name, gui.ResetOnSpawn, gui.IgnoreGuiInset, gui.DisplayOrder = "ScreenFX", false, true, 80
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	-- vignette: four edge gradients inside a CanvasGroup (GroupTransparency is the strength)
	vignette = Instance.new("CanvasGroup")
	vignette.Name, vignette.BackgroundTransparency, vignette.Size, vignette.GroupTransparency = "Vignette", 1, UDim2.fromScale(1, 1), 1
	vignette.Parent = gui
	edges = {}
	local seq = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.5, 0.6), NumberSequenceKeypoint.new(1, 1) })
	local defs = {
		{ Pos = UDim2.fromScale(0, 0), Size = UDim2.fromScale(1, 0.32), Rot = 90 },    -- top
		{ Pos = UDim2.fromScale(0, 0.68), Size = UDim2.fromScale(1, 0.32), Rot = 270 }, -- bottom
		{ Pos = UDim2.fromScale(0, 0), Size = UDim2.fromScale(0.22, 1), Rot = 0 },      -- left
		{ Pos = UDim2.fromScale(0.78, 0), Size = UDim2.fromScale(0.22, 1), Rot = 180 }, -- right
	}
	for _, d in defs do
		local f = Instance.new("Frame")
		f.BorderSizePixel, f.BackgroundColor3, f.Position, f.Size = 0, Color3.new(1, 0, 0), d.Pos, d.Size
		local g = Instance.new("UIGradient")
		g.Transparency, g.Rotation = seq, d.Rot
		g.Parent = f
		f.Parent = vignette
		table.insert(edges, f)
	end

	flash = solid(gui, "Flash", Color3.new(1, 1, 1))
	barTop = solid(gui, "BarTop", Color3.new())
	barTop.BackgroundTransparency, barTop.Size = 0, UDim2.fromScale(1, 0)
	barBottom = solid(gui, "BarBottom", Color3.new())
	barBottom.BackgroundTransparency, barBottom.Size, barBottom.AnchorPoint, barBottom.Position = 0, UDim2.fromScale(1, 0), Vector2.new(0, 1), UDim2.fromScale(0, 1)
	black = solid(gui, "Black", Color3.new())

	cc = Lighting:FindFirstChild("FPSGrade") or Instance.new("ColorCorrectionEffect")
	cc.Name, cc.Saturation, cc.Parent = "FPSGrade", 0, Lighting
	blur = Lighting:FindFirstChild("FPSBlur") or Instance.new("BlurEffect")
	blur.Name, blur.Size, blur.Parent = "FPSBlur", 0, Lighting
end

function ScreenFX.Fade(alpha, seconds)
	ensure()
	to(black, seconds, { BackgroundTransparency = 1 - math.clamp(alpha, 0, 1) })
end

function ScreenFX.Letterbox(on, seconds)
	ensure()
	to(barTop, seconds, { Size = UDim2.fromScale(1, on and LETTERBOX or 0) })
	to(barBottom, seconds, { Size = UDim2.fromScale(1, on and LETTERBOX or 0) })
end

function ScreenFX.Vignette(color, alpha, seconds)
	ensure()
	for _, f in edges do f.BackgroundColor3 = color end
	to(vignette, seconds, { GroupTransparency = 1 - math.clamp(alpha, 0, 1) })
end

function ScreenFX.Flash(color, alpha, seconds)
	ensure()
	local o = running[flash]
	if o then o:Cancel() end
	flash.BackgroundColor3, flash.BackgroundTransparency = color, 1 - math.clamp(alpha, 0, 1)
	to(flash, seconds, { BackgroundTransparency = 1 })
end

function ScreenFX.Grade(saturation, blurSize, seconds)
	ensure()
	to(cc, seconds, { Saturation = saturation })
	to(blur, seconds, { Size = blurSize })
end

function ScreenFX.Reset(seconds)
	ensure()
	ScreenFX.Fade(0, seconds)
	ScreenFX.Letterbox(false, seconds)
	ScreenFX.Vignette(Color3.new(1, 0, 0), 0, seconds)
	ScreenFX.Grade(0, 0, seconds)
end

return ScreenFX
