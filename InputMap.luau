-- InputMap: one action layer for keyboard + mouse, gamepad and touch.
-- Gameplay code never reads keys directly: it listens for actions ("Fire", "Jump" ...) and asks for the move / look vectors.
-- Bindings come from Settings (rebindable); MobileControls presses actions through InputMap.Press / Release.
local UIS = game:GetService("UserInputService")
local Players = game:GetService("Players")
local HapticService = game:GetService("HapticService")
local Settings = require(script.Parent.Settings)

local InputMap = {}
InputMap.Device = "KBM"      -- "KBM" | "PAD" | "Touch": whichever the player used last
InputMap.Enabled = true      -- false while a menu is open (actions marked Always still fire)
InputMap.TouchMove = Vector2.zero -- written by MobileControls (x right, y up, length <= 1)

local ACTIONS = {}
for _, a in Settings.Actions do ACTIONS[a.Id] = a end

local held = {}              -- [action] = { [source] = true }
local listeners = { Began = {}, Ended = {} } -- [kind][action] = { { Fn } }
local deviceCbs, bindCbs, enabledCbs = {}, {}, {}
local codeMap = {}           -- code -> { action ids }
local triggerOn = {}
local touchLook = Vector2.zero
local capture
local gamepad = Enum.UserInputType.Gamepad1

local function connect(list, fn)
	local entry = { Fn = fn }
	table.insert(list, entry)
	return { Disconnect = function()
		local i = table.find(list, entry)
		if i then table.remove(list, i) end
	end }
end

local function fireList(list, ...)
	for _, e in table.clone(list) do task.spawn(e.Fn, ...) end
end

local function fire(kind, action)
	local l = listeners[kind][action]
	if l then fireList(l, action) end
end

function InputMap.OnBegan(action, fn)
	listeners.Began[action] = listeners.Began[action] or {}
	return connect(listeners.Began[action], fn)
end
function InputMap.OnEnded(action, fn)
	listeners.Ended[action] = listeners.Ended[action] or {}
	return connect(listeners.Ended[action], fn)
end
function InputMap.OnDeviceChanged(fn) return connect(deviceCbs, fn) end
function InputMap.OnBindingsChanged(fn) return connect(bindCbs, fn) end
function InputMap.OnEnabledChanged(fn) return connect(enabledCbs, fn) end

-- ---------------------------------------------------------------- action state
function InputMap.Press(action, src)
	local def = ACTIONS[action]
	if not def then return end
	if not InputMap.Enabled and not def.Always then return end
	local set = held[action]
	if not set then
		set = {}
		held[action] = set
	end
	if set[src] then return end
	local was = next(set) ~= nil
	set[src] = true
	if not was then fire("Began", action) end
end

function InputMap.Release(action, src)
	local set = held[action]
	if not set or not set[src] then return end
	set[src] = nil
	if next(set) == nil then fire("Ended", action) end
end

function InputMap.IsDown(action)
	local set = held[action]
	return set ~= nil and next(set) ~= nil
end

-- menus call this: releases everything that is held so nothing stays stuck (fire, ADS, sprint ...)
function InputMap.SetEnabled(on)
	if InputMap.Enabled == on then return end
	InputMap.Enabled = on
	if not on then
		touchLook = Vector2.zero
		for action, set in held do
			if not ACTIONS[action].Always and next(set) ~= nil then
				held[action] = {}
				fire("Ended", action)
			end
		end
	end
	fireList(enabledCbs, on)
end

-- ---------------------------------------------------------------- codes
local MOUSE = {
	[Enum.UserInputType.MouseButton1] = "M:1",
	[Enum.UserInputType.MouseButton2] = "M:2",
	[Enum.UserInputType.MouseButton3] = "M:3",
}
local TRIGGERS = { [Enum.KeyCode.ButtonL2] = true, [Enum.KeyCode.ButtonR2] = true }

local function isPad(ut) return ut.Name:sub(1, 7) == "Gamepad" end

-- digital inputs only (triggers and the wheel are analog and handled in InputChanged)
local function codeOf(input)
	local ut = input.UserInputType
	if ut == Enum.UserInputType.Keyboard then
		if input.KeyCode == Enum.KeyCode.Unknown then return nil end
		return "K:" .. input.KeyCode.Name, "KBM"
	end
	if MOUSE[ut] then return MOUSE[ut], "KBM" end
	if isPad(ut) then
		local kc = input.KeyCode
		if kc == Enum.KeyCode.Unknown or TRIGGERS[kc] or kc == Enum.KeyCode.Thumbstick1 or kc == Enum.KeyCode.Thumbstick2 then return nil end
		return "G:" .. kc.Name, "PAD"
	end
	return nil
end

local function rebuild()
	codeMap = {}
	for _, def in Settings.Actions do
		local b = Settings.GetBinds()[def.Id]
		if b then
			for _, device in { "KBM", "PAD" } do
				for _, code in b[device] do
					if code ~= "" then
						local l = codeMap[code]
						if not l then
							l = {}
							codeMap[code] = l
						end
						table.insert(l, def.Id)
					end
				end
			end
		end
	end
	fireList(bindCbs)
end
rebuild()
Settings.OnChanged(function(key)
	if key == "Binds" or key == "All" then rebuild() end
end)

local function pressCode(code)
	local actions = codeMap[code]
	if actions then for _, a in actions do InputMap.Press(a, code) end end
end
local function releaseCode(code)
	local actions = codeMap[code]
	if actions then for _, a in actions do InputMap.Release(a, code) end end
end

-- ---------------------------------------------------------------- labels
local KEY_NAMES = {
	LeftShift = "L-SHIFT", RightShift = "R-SHIFT", LeftControl = "L-CTRL", RightControl = "R-CTRL", LeftAlt = "L-ALT", RightAlt = "R-ALT",
	Space = "SPACE", Return = "ENTER", Backspace = "BKSP", CapsLock = "CAPS", Tab = "TAB", Backquote = "`", Minus = "-", Equals = "=",
	LeftBracket = "[", RightBracket = "]", Semicolon = ";", Quote = "'", Comma = ",", Period = ".", Slash = "/", BackSlash = "\\",
	Zero = "0", One = "1", Two = "2", Three = "3", Four = "4", Five = "5", Six = "6", Seven = "7", Eight = "8", Nine = "9",
	Up = "UP", Down = "DOWN", Left = "LEFT", Right = "RIGHT", Insert = "INS", Delete = "DEL", Home = "HOME", End = "END",
	PageUp = "PG UP", PageDown = "PG DN",
}
local XBOX = {
	ButtonA = "A", ButtonB = "B", ButtonX = "X", ButtonY = "Y", ButtonL1 = "LB", ButtonR1 = "RB", ButtonL2 = "LT", ButtonR2 = "RT",
	ButtonL3 = "L3", ButtonR3 = "R3", ButtonSelect = "VIEW", ButtonStart = "MENU",
	DPadUp = "D-PAD UP", DPadDown = "D-PAD DOWN", DPadLeft = "D-PAD LEFT", DPadRight = "D-PAD RIGHT",
}
local PLAYSTATION = {
	ButtonA = "CROSS", ButtonB = "CIRCLE", ButtonX = "SQUARE", ButtonY = "TRIANGLE", ButtonL1 = "L1", ButtonR1 = "R1", ButtonL2 = "L2", ButtonR2 = "R2",
	ButtonL3 = "L3", ButtonR3 = "R3", ButtonSelect = "SHARE", ButtonStart = "OPTIONS",
	DPadUp = "D-PAD UP", DPadDown = "D-PAD DOWN", DPadLeft = "D-PAD LEFT", DPadRight = "D-PAD RIGHT",
}

function InputMap.CodeLabel(code)
	if not code or code == "" then return "NONE" end
	local kind, name = code:match("^(%a):(%w+)$")
	if kind == "K" then return KEY_NAMES[name] or name:upper() end
	if kind == "M" then return name == "1" and "LEFT CLICK" or (name == "2" and "RIGHT CLICK" or "MIDDLE CLICK") end
	if kind == "W" then return "WHEEL " .. name:upper() end
	if kind == "G" then
		local map = Settings.Get("Interface.Glyphs") == "PlayStation" and PLAYSTATION or XBOX
		return map[name] or name:upper()
	end
	return code:upper()
end

-- short label for the player's current device ("" on touch). Used by HUD key chips and prompts.
function InputMap.Label(action, device)
	device = device or InputMap.Device
	if device == "Touch" then return "" end
	local b = Settings.GetBinds()[action]
	if not b then return "" end
	for _, code in b[device] do
		if code ~= "" then return InputMap.CodeLabel(code) end
	end
	return ""
end

-- ---------------------------------------------------------------- device detection
local function updateDevice(t)
	local d
	if t == Enum.UserInputType.Touch then d = "Touch"
	elseif isPad(t) then
		d = "PAD"
		gamepad = t
	elseif t == Enum.UserInputType.Keyboard or t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.MouseButton2
		or t == Enum.UserInputType.MouseButton3 or t == Enum.UserInputType.MouseMovement or t == Enum.UserInputType.MouseWheel then
		d = "KBM"
	end
	if d and d ~= InputMap.Device then
		InputMap.Device = d
		fireList(deviceCbs, d)
	end
end
if UIS.TouchEnabled and not UIS.KeyboardEnabled and not UIS.MouseEnabled then
	InputMap.Device = "Touch"
elseif UIS.GamepadEnabled and not UIS.KeyboardEnabled then
	InputMap.Device = "PAD"
end
UIS.LastInputTypeChanged:Connect(updateDevice)

-- ---------------------------------------------------------------- rebinding
-- InputMap.Capture("KBM" | "PAD", function(code, status) end): the next button / key / wheel notch the player uses is reported.
-- status: "set", "clear" (Backspace / Delete, or VIEW on a pad) or "cancel" (Escape, or MENU on a pad). Returns a cancel function.
function InputMap.Capture(device, cb)
	if capture then
		local old = capture
		capture = nil
		old.Cb(nil, "cancel")
	end
	local me = { Device = device, Cb = cb, Born = os.clock() }
	capture = me
	return function()
		if capture == me then
			capture = nil
			cb(nil, "cancel")
		end
	end
end

function InputMap.IsCapturing() return capture ~= nil end

function InputMap.CancelCapture()
	if capture then
		local c = capture
		capture = nil
		c.Cb(nil, "cancel")
	end
end

local function handleCapture(code, dev)
	local c = capture
	if not c or dev ~= c.Device or os.clock() - c.Born < 0.15 then return end
	capture = nil
	if code == "K:Escape" or code == "G:ButtonStart" then c.Cb(nil, "cancel")
	elseif code == "K:Backspace" or code == "K:Delete" or code == "G:ButtonSelect" then c.Cb("", "clear")
	else c.Cb(code, "set") end
end

-- ---------------------------------------------------------------- raw input
UIS.InputBegan:Connect(function(input, gpe)
	local code, dev = codeOf(input)
	if not code then return end
	if gpe and dev ~= "PAD" then return end
	if capture then
		handleCapture(code, dev)
		return
	end
	pressCode(code)
end)

UIS.InputEnded:Connect(function(input)
	local code = codeOf(input)
	if code then releaseCode(code) end
end)

UIS.InputChanged:Connect(function(input, gpe)
	local ut = input.UserInputType
	if ut == Enum.UserInputType.MouseWheel then
		if gpe or input.Position.Z == 0 then return end
		local code = input.Position.Z > 0 and "W:Up" or "W:Down"
		if capture then
			handleCapture(code, "KBM")
		else
			pressCode(code)
			releaseCode(code)
		end
	elseif isPad(ut) and TRIGGERS[input.KeyCode] then
		local code = "G:" .. input.KeyCode.Name
		local z = input.Position.Z
		local threshold = capture and 0.6 or Settings.Get("Pad.TriggerThreshold") / 100
		if not triggerOn[code] and z >= threshold then
			triggerOn[code] = true
			if capture then handleCapture(code, "PAD") else pressCode(code) end
		elseif triggerOn[code] and z < threshold * 0.6 then
			triggerOn[code] = false
			releaseCode(code)
		end
	end
end)

-- ---------------------------------------------------------------- analog: move + look
local function stick(keyCode)
	for _, obj in UIS:GetGamepadState(gamepad) do
		if obj.KeyCode == keyCode then return Vector2.new(obj.Position.X, obj.Position.Y) end
	end
	return Vector2.zero
end

local function radial(v, deadzone)
	local m = v.Magnitude
	if m <= deadzone then return Vector2.zero end
	return v.Unit * math.min((m - deadzone) / (1 - deadzone), 1)
end

local CURVE = { Linear = 1, Standard = 1.5, Precision = 2.2 }
local function shape(v)
	local m = v.Magnitude
	if m == 0 then return v end
	return v.Unit * m ^ (CURVE[Settings.Get("Pad.Curve")] or 1.5)
end

-- the stick that moves / looks depends on the stick layout; the deadzone belongs to the physical stick
local function padMove()
	if not UIS.GamepadEnabled then return Vector2.zero end
	local south = Settings.Get("Pad.Layout") == "Southpaw"
	return radial(stick(south and Enum.KeyCode.Thumbstick2 or Enum.KeyCode.Thumbstick1),
		Settings.Get(south and "Pad.DeadzoneR" or "Pad.DeadzoneL") / 100)
end

local function padLook()
	if not UIS.GamepadEnabled then return Vector2.zero end
	local south = Settings.Get("Pad.Layout") == "Southpaw"
	return shape(radial(stick(south and Enum.KeyCode.Thumbstick1 or Enum.KeyCode.Thumbstick2),
		Settings.Get(south and "Pad.DeadzoneL" or "Pad.DeadzoneR") / 100))
end

-- x = right, z = back (same convention as the default control module), length <= 1
function InputMap.GetMoveVector()
	if not InputMap.Enabled then return Vector3.zero end
	local kx = (InputMap.IsDown("MoveRight") and 1 or 0) - (InputMap.IsDown("MoveLeft") and 1 or 0)
	local kz = (InputMap.IsDown("MoveBack") and 1 or 0) - (InputMap.IsDown("MoveForward") and 1 or 0)
	local best = Vector3.new(kx, 0, kz)
	if best.Magnitude > 1 then best = best.Unit end
	local p = padMove()
	local pv = Vector3.new(p.X, 0, -p.Y)
	if pv.Magnitude > best.Magnitude then best = pv end
	local t = InputMap.TouchMove
	local tv = Vector3.new(t.X, 0, -t.Y)
	if tv.Magnitude > best.Magnitude then best = tv end
	return best
end

-- aim assist: gentle slowdown while the crosshair is over a living enemy (pad + touch only)
local assistParams = RaycastParams.new()
assistParams.FilterType = Enum.RaycastFilterType.Exclude
function InputMap.SetCharacter(char)
	assistParams.FilterDescendantsInstances = { char }
end

local function assistFactor()
	local strength = Settings.Get("Pad.AimAssist") / 100
	local cam = workspace.CurrentCamera
	if strength <= 0 or not cam then return 1 end
	local hit = workspace:Raycast(cam.CFrame.Position, cam.CFrame.LookVector * 250, assistParams)
	local model = hit and hit.Instance:FindFirstAncestorOfClass("Model")
	local hum = model and model:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then return 1 end
	local me = Players.LocalPlayer
	local other = Players:GetPlayerFromCharacter(model)
	if other and (other == me or (me.Team ~= nil and other.Team == me.Team)) then return 1 end
	return 1 - 0.5 * strength
end

function InputMap.AddTouchLook(pixels)
	touchLook += pixels
end

-- Look this frame in radians, "mouse delta" convention: x = right, y = down.
-- zoom = tan(fov/2) relative to the hip fov (so zoomed aim is slower), ads = the player is aiming, mouseDelta = UIS:GetMouseDelta()
function InputMap.GetLook(dt, zoom, ads, mouseDelta)
	local out = Vector2.zero
	if not InputMap.Enabled then
		touchLook = Vector2.zero
		return out
	end
	if mouseDelta.Magnitude > 0 then
		local k = Settings.Get("Mouse.Sens") * 0.00022 * zoom * (ads and Settings.Get("Mouse.AdsMult") or 1)
		local d = mouseDelta * k
		out += Settings.Get("Mouse.InvertY") and Vector2.new(d.X, -d.Y) or d
	end

	local pad = padLook()
	local assist = 1
	if pad.Magnitude > 0 or touchLook.Magnitude > 0 then assist = assistFactor() end
	if pad.Magnitude > 0 then
		local k = zoom * (ads and Settings.Get("Pad.AdsMult") or 1) * assist * 22.5 * dt
		local yaw = math.rad(pad.X * Settings.Get("Pad.SensX") * k)
		local pitch = math.rad(-pad.Y * Settings.Get("Pad.SensY") * k)
		out += Vector2.new(yaw, Settings.Get("Pad.InvertY") and -pitch or pitch)
	end

	if touchLook.Magnitude > 0 then
		local k = Settings.Get("Touch.Sens") * 0.00045 * zoom * (ads and Settings.Get("Touch.AdsMult") or 1) * assist
		local d = touchLook * k
		out += Settings.Get("Touch.InvertY") and Vector2.new(d.X, -d.Y) or d
		touchLook = Vector2.zero
	end
	return out
end

-- ---------------------------------------------------------------- vibration
function InputMap.Rumble(power, duration)
	local scale = Settings.Get("Pad.Rumble") / 100
	if scale <= 0 or InputMap.Device ~= "PAD" then return end
	pcall(function()
		if not HapticService:IsMotorSupported(gamepad, Enum.VibrationMotor.Large) then return end
		HapticService:SetMotor(gamepad, Enum.VibrationMotor.Large, math.clamp(power * scale, 0, 1))
		task.delay(duration, function()
			pcall(function() HapticService:SetMotor(gamepad, Enum.VibrationMotor.Large, 0) end)
		end)
	end)
end

return InputMap
