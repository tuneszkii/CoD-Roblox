-- Settings: the single source of truth for every player option.
-- The schema below drives the settings menu, the defaults and the server-side validation, so adding an option = adding one entry.
-- Pure data + logic at the top (safe to require on the server for validation); client-only appliers live at the bottom.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local SoundService = game:GetService("SoundService")
local UserInputService = game:GetService("UserInputService")

local Settings = {}

-- ================================================================ rebindable actions
-- Codes:  "K:<KeyCode>" keyboard   "M:<1|2|3>" mouse button   "W:<Up|Down>" mouse wheel   "G:<KeyCode>" gamepad button
-- KBM / PAD = default bindings (max 2 slots). Always = still works while a menu is open. PadHidden / KbmHidden = not shown in that device's list.
Settings.Actions = {
	{ Id = "MoveForward", Label = "Move forward", Group = "MOVEMENT", KBM = { "K:W" }, PadHidden = true },
	{ Id = "MoveBack", Label = "Move back", Group = "MOVEMENT", KBM = { "K:S" }, PadHidden = true },
	{ Id = "MoveLeft", Label = "Move left", Group = "MOVEMENT", KBM = { "K:A" }, PadHidden = true },
	{ Id = "MoveRight", Label = "Move right", Group = "MOVEMENT", KBM = { "K:D" }, PadHidden = true },
	{ Id = "Jump", Label = "Jump", Group = "MOVEMENT", KBM = { "K:Space" }, PAD = { "G:ButtonA" } },
	{ Id = "Crouch", Label = "Crouch / slide (again = cancel, hold = prone)", Group = "MOVEMENT", KBM = { "K:C", "K:LeftControl" }, PAD = { "G:ButtonB" } },
	{ Id = "Prone", Label = "Prone / dive / drop shot", Group = "MOVEMENT", KBM = { "K:P" } }, -- controller: hold Crouch
	{ Id = "Sprint", Label = "Sprint (double tap = tactical)", Group = "MOVEMENT", KBM = { "K:LeftShift" }, PAD = { "G:ButtonL3" } },

	{ Id = "Fire", Label = "Fire", Group = "COMBAT", KBM = { "M:1" }, PAD = { "G:ButtonR2" } },
	{ Id = "Aim", Label = "Aim down sights", Group = "COMBAT", KBM = { "M:2" }, PAD = { "G:ButtonL2" } },
	{ Id = "Reload", Label = "Reload", Group = "COMBAT", KBM = { "K:R" }, PAD = { "G:ButtonX" } },
	{ Id = "FireMode", Label = "Switch fire mode (auto / semi)", Group = "COMBAT", KBM = { "K:T" }, PadHidden = true },
	{ Id = "SwitchWeapon", Label = "Switch weapon", Group = "COMBAT", KBM = { "W:Up", "W:Down" }, PAD = { "G:ButtonY" } },
	{ Id = "Weapon1", Label = "Primary weapon", Group = "COMBAT", KBM = { "K:One" }, PadHidden = true },
	{ Id = "Weapon2", Label = "Secondary weapon", Group = "COMBAT", KBM = { "K:Two" }, PadHidden = true },
	{ Id = "Melee", Label = "Quick melee", Group = "COMBAT", KBM = { "K:V" }, PAD = { "G:ButtonR3" } },
	{ Id = "HoldBreath", Label = "Hold breath (scoped)", Group = "COMBAT", KBM = { "K:LeftShift" }, PAD = { "G:ButtonL3" } },
	{ Id = "PeekLeft", Label = "Peek left (while aiming)", Group = "COMBAT", KBM = { "K:Q" }, PadHidden = true },
	{ Id = "PeekRight", Label = "Peek right (while aiming)", Group = "COMBAT", KBM = { "K:E" }, PadHidden = true },

	{ Id = "Lethal", Label = "Lethal equipment", Group = "EQUIPMENT", KBM = { "K:G" }, PAD = { "G:ButtonR1" } },
	{ Id = "Tactical", Label = "Tactical equipment", Group = "EQUIPMENT", KBM = { "K:Q" }, PAD = { "G:ButtonL1" } },
	{ Id = "Plate", Label = "Armor plate", Group = "EQUIPMENT", KBM = { "K:X" }, PAD = { "G:DPadDown" } },
	{ Id = "Detonate", Label = "Detonate C4", Group = "EQUIPMENT", KBM = { "K:H" }, PAD = { "G:DPadRight" } },
	{ Id = "Interact", Label = "Interact / revive / climb", Group = "EQUIPMENT", KBM = { "K:E" }, PAD = { "G:ButtonX" } },

	{ Id = "Streak1", Label = "Kill streak 1", Group = "KILL STREAKS", KBM = { "K:Three" }, PadHidden = true },
	{ Id = "Streak2", Label = "Kill streak 2", Group = "KILL STREAKS", KBM = { "K:Four" }, PadHidden = true },
	{ Id = "Streak3", Label = "Kill streak 3", Group = "KILL STREAKS", KBM = { "K:Five" }, PadHidden = true },
	{ Id = "StreakNext", Label = "Use next ready kill streak", Group = "KILL STREAKS", KBM = { "K:Z" }, PAD = { "G:DPadUp" } },

	{ Id = "Loadout", Label = "Armory (classes, guns, perks)", Group = "INTERFACE", KBM = { "K:L" }, PAD = { "G:DPadLeft" }, Always = true },
	{ Id = "Menu", Label = "Main menu", Group = "INTERFACE", KBM = { "K:M" }, PAD = { "G:ButtonSelect" }, Always = true },
	{ Id = "Emote", Label = "Emote wheel", Group = "INTERFACE", KBM = { "K:B" }, PadHidden = true, Always = true },
	{ Id = "Scoreboard", Label = "Scoreboard (hold)", Group = "INTERFACE", KBM = { "K:Tab" }, PadHidden = true },
	{ Id = "Map", Label = "Full map (toggle)", Group = "INTERFACE", KBM = { "K:N" }, PadHidden = true },
}
Settings.ActionGroups = { "MOVEMENT", "COMBAT", "EQUIPMENT", "KILL STREAKS", "INTERFACE" }

-- these pairs are allowed to share a button (same as the real thing: reload / use, sprint / hold breath)
-- peek left / right share Q / E with tactical / interact: while you aim the key peeks, otherwise it keeps its normal job
local EXEMPT = {
	Sprint = { HoldBreath = true }, HoldBreath = { Sprint = true },
	Reload = { Interact = true }, Interact = { Reload = true, PeekRight = true },
	Tactical = { PeekLeft = true }, PeekLeft = { Tactical = true }, PeekRight = { Interact = true },
}

-- controller button presets: overlays on top of the default PAD bindings
Settings.PadPresetNames = { "Default", "Bumper Jumper", "Tactical" }
Settings.PadPresets = {
	Default = {},
	["Bumper Jumper"] = { Jump = { "G:ButtonL1" }, Tactical = { "G:ButtonA" } },
	Tactical = { Melee = { "G:ButtonB" }, Crouch = { "G:ButtonR3" } },
}

-- ================================================================ mobile layout defaults
-- X / Y = centre of the button as a fraction of the screen, S = size multiplier (1 = 10% of screen height), V = visible by default.
-- Action = the InputMap action the button presses. Kind = "Stick" / "Toggle" (sprint lock) / nil (plain hold button).
Settings.TouchButtons = {
	{ Id = "Stick", Label = "MOVE", Kind = "Stick", X = 0.13, Y = 0.70, S = 1.5, V = true },
	{ Id = "Fire", Label = "FIRE", Action = "Fire", X = 0.88, Y = 0.58, S = 1.25, V = true },
	{ Id = "Aim", Label = "AIM", Action = "Aim", X = 0.77, Y = 0.44, S = 0.95, V = true },
	{ Id = "Jump", Label = "JUMP", Action = "Jump", X = 0.94, Y = 0.82, S = 0.95, V = true },
	{ Id = "Crouch", Label = "CROUCH", Action = "Crouch", X = 0.83, Y = 0.82, S = 0.85, V = true },
	{ Id = "Prone", Label = "PRONE", Action = "Prone", X = 0.83, Y = 0.93, S = 0.7, V = true },
	{ Id = "Reload", Label = "RELOAD", Action = "Reload", X = 0.72, Y = 0.72, S = 0.8, V = true },
	{ Id = "Switch", Label = "SWAP", Action = "SwitchWeapon", X = 0.66, Y = 0.55, S = 0.7, V = true },
	{ Id = "FireMode", Label = "MODE", Action = "FireMode", X = 0.82, Y = 0.27, S = 0.65, V = true },
	{ Id = "Melee", Label = "MELEE", Action = "Melee", X = 0.94, Y = 0.40, S = 0.7, V = true },
	{ Id = "Lethal", Label = "LETHAL", Action = "Lethal", X = 0.27, Y = 0.82, S = 0.75, V = true },
	{ Id = "Tactical", Label = "TACT", Action = "Tactical", X = 0.34, Y = 0.68, S = 0.75, V = true },
	{ Id = "Plate", Label = "PLATE", Action = "Plate", X = 0.06, Y = 0.36, S = 0.7, V = true },
	{ Id = "Interact", Label = "USE", Action = "Interact", X = 0.62, Y = 0.40, S = 0.7, V = true },
	{ Id = "Detonate", Label = "C4", Action = "Detonate", X = 0.06, Y = 0.48, S = 0.65, V = true },
	{ Id = "Streak", Label = "STREAK", Action = "StreakNext", X = 0.06, Y = 0.24, S = 0.7, V = true },
	{ Id = "SprintLock", Label = "SPRINT", Kind = "Toggle", Action = "Sprint", X = 0.22, Y = 0.50, S = 0.75, V = true },
	{ Id = "FireLeft", Label = "FIRE", Action = "Fire", X = 0.20, Y = 0.34, S = 1.0, V = false },
	{ Id = "Menu", Label = "MENU", Action = "Menu", X = 0.95, Y = 0.07, S = 0.6, V = true },
	{ Id = "Emote", Label = "EMOTE", Action = "Emote", X = 0.06, Y = 0.11, S = 0.65, V = true },
	{ Id = "Scores", Label = "SCORES", Action = "Scoreboard", X = 0.95, Y = 0.19, S = 0.6, V = true },
	{ Id = "FullMap", Label = "MAP", Action = "Map", X = 0.95, Y = 0.30, S = 0.6, V = true },
}

-- ================================================================ options schema
-- Types: Header, Slider (Min Max Step Suffix), Toggle, Choice (Options), Action (Id: handled by the menu), Binds (keybind list for Device)
local function H(label) return { Type = "Header", Label = label } end

Settings.Pages = {
	{ Id = "Graphics", Title = "GRAPHICS", Entries = {
		H("DISPLAY"),
		{ Key = "Graphics.Quality", Type = "Choice", Label = "Quality level", Desc = "Roblox render quality. Auto lets Roblox decide.", Options = { "Auto", "Low", "Medium", "High", "Ultra" }, Default = "Auto" },
		{ Key = "Graphics.Fov", Type = "Slider", Label = "Field of view", Desc = "Hip-fire field of view. Aiming zooms from this value.", Min = 60, Max = 120, Step = 1, Default = 80, Suffix = "°" },
		{ Key = "Graphics.Brightness", Type = "Slider", Label = "Brightness", Min = -30, Max = 30, Step = 1, Default = 0 },
		{ Key = "Graphics.Contrast", Type = "Slider", Label = "Contrast", Min = -30, Max = 30, Step = 1, Default = 0 },
		H("EFFECTS"),
		{ Key = "Graphics.Shadows", Type = "Toggle", Label = "Shadows", Default = true },
		{ Key = "Graphics.Bloom", Type = "Toggle", Label = "Bloom", Default = true },
		{ Key = "Graphics.SunRays", Type = "Toggle", Label = "Sun rays", Default = true },
		{ Key = "Graphics.DepthOfField", Type = "Toggle", Label = "Depth of field", Default = true },
		H("MOTION"),
		{ Key = "Graphics.HeadBob", Type = "Slider", Label = "Weapon / head bob", Min = 0, Max = 100, Step = 5, Default = 100, Suffix = "%" },
		{ Key = "Graphics.CameraShake", Type = "Slider", Label = "Camera shake", Min = 0, Max = 100, Step = 5, Default = 100, Suffix = "%" },
		H("PERFORMANCE"),
		{ Key = "Graphics.ShowFps", Type = "Toggle", Label = "Show FPS", Default = false },
		{ Key = "Graphics.ShowPing", Type = "Toggle", Label = "Show ping", Default = false },
	} },
	{ Id = "Controls", Title = "KEYBOARD & MOUSE", Entries = {
		H("SENSITIVITY"),
		{ Key = "Mouse.Sens", Type = "Slider", Label = "Mouse sensitivity", Min = 1, Max = 30, Step = 0.5, Default = 10 },
		{ Key = "Mouse.AdsMult", Type = "Slider", Label = "Aim down sights multiplier", Desc = "On top of the automatic zoom scaling.", Min = 0.1, Max = 2, Step = 0.05, Default = 1 },
		{ Key = "Mouse.InvertY", Type = "Toggle", Label = "Invert vertical look", Default = false },
	} },
	{ Id = "Keybinds", Title = "KEYBINDS", Entries = {
		{ Type = "Binds" },
	} },
	{ Id = "Controller", Title = "CONTROLLER", Entries = {
		H("LAYOUT"),
		{ Key = "Pad.Preset", Type = "Choice", Label = "Button layout", Desc = "Picking a preset replaces your controller binds.", Options = Settings.PadPresetNames, Default = "Default" },
		{ Key = "Pad.Layout", Type = "Choice", Label = "Stick layout", Options = { "Default", "Southpaw" }, Default = "Default" },
		H("SENSITIVITY"),
		{ Key = "Pad.SensX", Type = "Slider", Label = "Horizontal sensitivity", Min = 1, Max = 20, Step = 0.5, Default = 8 },
		{ Key = "Pad.SensY", Type = "Slider", Label = "Vertical sensitivity", Min = 1, Max = 20, Step = 0.5, Default = 8 },
		{ Key = "Pad.AdsMult", Type = "Slider", Label = "Aim down sights multiplier", Min = 0.1, Max = 2, Step = 0.05, Default = 1 },
		{ Key = "Pad.Curve", Type = "Choice", Label = "Response curve", Desc = "Linear = 1:1. Precision = fine control near the centre.", Options = { "Linear", "Standard", "Precision" }, Default = "Standard" },
		{ Key = "Pad.InvertY", Type = "Toggle", Label = "Invert vertical look", Default = false },
		H("DEADZONES"),
		{ Key = "Pad.DeadzoneL", Type = "Slider", Label = "Left stick deadzone", Min = 0, Max = 40, Step = 1, Default = 10, Suffix = "%" },
		{ Key = "Pad.DeadzoneR", Type = "Slider", Label = "Right stick deadzone", Min = 0, Max = 40, Step = 1, Default = 10, Suffix = "%" },
		{ Key = "Pad.TriggerThreshold", Type = "Slider", Label = "Trigger pull point", Desc = "How far a trigger must be pulled to count.", Min = 5, Max = 80, Step = 1, Default = 30, Suffix = "%" },
		H("ASSIST & FEEDBACK"),
		{ Key = "Pad.AimAssist", Type = "Slider", Label = "Aim assist strength", Desc = "Slows your aim down when the crosshair is on an enemy.", Min = 0, Max = 100, Step = 5, Default = 60, Suffix = "%" },
		{ Key = "Pad.Rumble", Type = "Slider", Label = "Vibration", Min = 0, Max = 100, Step = 5, Default = 100, Suffix = "%" },
	} },
	{ Id = "Touch", Title = "MOBILE", Entries = {
		H("LOOK"),
		{ Key = "Touch.Sens", Type = "Slider", Label = "Look sensitivity", Min = 1, Max = 30, Step = 0.5, Default = 10 },
		{ Key = "Touch.AdsMult", Type = "Slider", Label = "Aim down sights multiplier", Min = 0.1, Max = 2, Step = 0.05, Default = 1 },
		{ Key = "Touch.InvertY", Type = "Toggle", Label = "Invert vertical look", Default = false },
		{ Key = "Touch.DragFire", Type = "Toggle", Label = "Aim while holding fire", Desc = "Slide the finger that is holding fire to keep aiming.", Default = true },
		H("MOVEMENT"),
		{ Key = "Touch.StickMode", Type = "Choice", Label = "Move stick", Desc = "Floating = the stick appears wherever you touch the left side.", Options = { "Fixed", "Floating" }, Default = "Fixed" },
		{ Key = "Touch.SprintPush", Type = "Toggle", Label = "Push stick fully to sprint", Default = true },
		H("BUTTONS"),
		{ Key = "Touch.Scale", Type = "Slider", Label = "Button size", Min = 60, Max = 150, Step = 5, Default = 100, Suffix = "%" },
		{ Key = "Touch.Opacity", Type = "Slider", Label = "Button opacity", Min = 20, Max = 100, Step = 5, Default = 70, Suffix = "%" },
		{ Type = "Action", Id = "TouchEditor", Label = "Customize touch layout", Desc = "Drag, resize, hide and fade every button.", Button = "OPEN EDITOR" },
	} },
	{ Id = "Interface", Title = "INTERFACE", Entries = {
		H("SCALE"),
		{ Key = "Interface.Scale", Type = "Slider", Label = "Menu scale", Min = 70, Max = 130, Step = 5, Default = 100, Suffix = "%" },
		{ Key = "Interface.HudScale", Type = "Slider", Label = "HUD scale", Min = 60, Max = 140, Step = 5, Default = 100, Suffix = "%" },
		{ Key = "Interface.Glyphs", Type = "Choice", Label = "Controller button names", Options = { "Xbox", "PlayStation" }, Default = "Xbox" },
		H("CROSSHAIR"),
		{ Key = "Interface.Crosshair", Type = "Toggle", Label = "Show crosshair", Default = true },
		{ Key = "Interface.CrossColor", Type = "Choice", Label = "Colour", Options = { "White", "Amber", "Green", "Cyan", "Red", "Pink" }, Default = "White" },
		{ Key = "Interface.CrossLength", Type = "Slider", Label = "Length", Min = 3, Max = 20, Step = 1, Default = 9 },
		{ Key = "Interface.CrossThickness", Type = "Slider", Label = "Thickness", Min = 1, Max = 6, Step = 1, Default = 2 },
		{ Key = "Interface.CrossDot", Type = "Toggle", Label = "Centre dot", Default = true },
		{ Key = "Interface.CrossOpacity", Type = "Slider", Label = "Opacity", Min = 20, Max = 100, Step = 5, Default = 100, Suffix = "%" },
		H("HUD"),
		{ Key = "Interface.Hitmarkers", Type = "Toggle", Label = "Hit markers", Default = true },
		{ Key = "Interface.Compass", Type = "Toggle", Label = "Compass", Default = true },
		{ Key = "Interface.Minimap", Type = "Toggle", Label = "Minimap", Desc = "Allies are always shown. Enemies show on a UAV sweep or briefly after an unsuppressed shot.", Default = true },
		{ Key = "Interface.MinimapSize", Type = "Slider", Label = "Minimap size", Min = 110, Max = 260, Step = 10, Default = 170, Suffix = "px" },
		{ Key = "Interface.MinimapRange", Type = "Slider", Label = "Minimap range", Min = 40, Max = 200, Step = 10, Default = 90, Suffix = " studs" },
	} },
	{ Id = "Audio", Title = "AUDIO", Entries = {
		H("VOLUME"),
		{ Key = "Audio.Master", Type = "Slider", Label = "Master", Min = 0, Max = 100, Step = 5, Default = 100, Suffix = "%" },
		{ Key = "Audio.Sfx", Type = "Slider", Label = "Effects", Min = 0, Max = 100, Step = 5, Default = 100, Suffix = "%" },
		{ Key = "Audio.Music", Type = "Slider", Label = "Music", Min = 0, Max = 100, Step = 5, Default = 60, Suffix = "%" },
		{ Key = "Audio.Voice", Type = "Slider", Label = "Dialogue", Min = 0, Max = 100, Step = 5, Default = 100, Suffix = "%" },
		{ Key = "Audio.Ui", Type = "Slider", Label = "Interface sounds", Min = 0, Max = 100, Step = 5, Default = 100, Suffix = "%" },
	} },
	{ Id = "Gameplay", Title = "GAMEPLAY", Entries = {
		H("INPUT BEHAVIOUR"),
		{ Key = "Gameplay.AdsMode", Type = "Choice", Label = "Aim down sights", Desc = "Toggle is recommended on touch.", Options = { "Hold", "Toggle" }, Default = "Hold" },
		{ Key = "Gameplay.CrouchMode", Type = "Choice", Label = "Crouch", Options = { "Toggle", "Hold" }, Default = "Toggle" },
		{ Key = "Gameplay.SprintMode", Type = "Choice", Label = "Sprint", Desc = "Auto sprints whenever you move forward.", Options = { "Hold", "Toggle", "Auto" }, Default = "Hold" },
	} },
}

local ENTRY = {}   -- Key -> entry
for _, page in Settings.Pages do
	for _, e in page.Entries do if e.Key then ENTRY[e.Key] = e end end
end
Settings.Entry = ENTRY

-- ================================================================ state
local values = {}
local binds = {}
local layout = {}  -- [id] = { X, Y, S, O, V } overrides (only what the player changed)
local listeners = {}
local TOUCH = {}
for _, t in Settings.TouchButtons do TOUCH[t.Id] = t end

local function defaultBindsFor(def)
	return {
		KBM = { def.KBM and def.KBM[1] or "", def.KBM and def.KBM[2] or "" },
		PAD = { def.PAD and def.PAD[1] or "", def.PAD and def.PAD[2] or "" },
	}
end

for key, e in ENTRY do values[key] = e.Default end
for _, a in Settings.Actions do binds[a.Id] = defaultBindsFor(a) end

-- ---------------------------------------------------------------- change notification
-- keys: every option key, plus "Binds" and "Layout" and "All" (after a load / reset)
function Settings.OnChanged(fn)
	local entry = { Fn = fn }
	table.insert(listeners, entry)
	return { Disconnect = function()
		local i = table.find(listeners, entry)
		if i then table.remove(listeners, i) end
	end }
end

local function notify(key, value)
	for _, l in table.clone(listeners) do task.spawn(l.Fn, key, value) end
end

local function markDirty()
	if Settings.OnDirty then Settings.OnDirty() end
end

-- ---------------------------------------------------------------- values
local function coerce(e, v)
	if e.Type == "Slider" then
		if type(v) ~= "number" or v ~= v then return false end
		local step = e.Step or 1
		v = math.clamp(math.floor((v - e.Min) / step + 0.5) * step + e.Min, e.Min, e.Max)
		return true, math.floor(v * 1000 + 0.5) / 1000
	elseif e.Type == "Toggle" then
		return type(v) == "boolean", v
	elseif e.Type == "Choice" then
		return type(v) == "string" and table.find(e.Options, v) ~= nil, v
	end
	return false
end

function Settings.Get(key)
	return values[key]
end

function Settings.Set(key, v)
	local e = ENTRY[key]
	if not e then return end
	local ok, clean = coerce(e, v)
	if not ok or clean == values[key] then return end
	values[key] = clean
	notify(key, clean)
	markDirty()
	if key == "Pad.Preset" then Settings.ApplyPadPreset(clean) end
end

function Settings.Default(key)
	return ENTRY[key] and ENTRY[key].Default
end

function Settings.ResetPage(pageId)
	for _, page in Settings.Pages do
		if page.Id == pageId then
			for _, e in page.Entries do
				if e.Key then Settings.Set(e.Key, e.Default) end
			end
		end
	end
end

-- ---------------------------------------------------------------- binds
function Settings.GetBinds() return binds end

function Settings.GetBind(action, device, slot)
	local b = binds[action]
	return b and b[device][slot] or ""
end

-- returns the id of the action that lost its button to this one (swapped), if any
function Settings.SetBind(action, device, slot, code)
	local b = binds[action]
	if not b or (slot ~= 1 and slot ~= 2) then return nil end
	local list = b[device]
	local old = list[slot]
	local conflict
	if code ~= "" then
		for _, def in Settings.Actions do
			if def.Id ~= action and not (EXEMPT[action] and EXEMPT[action][def.Id]) then
				local other = binds[def.Id][device]
				for i = 1, 2 do
					if other[i] == code then
						other[i] = old -- swap: the other action gets the button we just gave up
						conflict = def.Id
					end
				end
			end
		end
		if list[3 - slot] == code then list[3 - slot] = "" end
	end
	list[slot] = code
	notify("Binds")
	markDirty()
	return conflict
end

function Settings.ResetBinds(device)
	for _, a in Settings.Actions do
		binds[a.Id][device] = defaultBindsFor(a)[device]
	end
	notify("Binds")
	markDirty()
end

function Settings.ApplyPadPreset(name)
	local preset = Settings.PadPresets[name]
	if not preset then return end
	for _, a in Settings.Actions do binds[a.Id].PAD = defaultBindsFor(a).PAD end
	for action, codes in preset do
		if binds[action] then binds[action].PAD = { codes[1] or "", codes[2] or "" } end
	end
	notify("Binds")
	markDirty()
end

-- ---------------------------------------------------------------- touch layout
function Settings.GetLayout(id)
	local def, o = TOUCH[id], layout[id]
	if not def then return nil end
	local v = def.V
	if o and o.V ~= nil then v = o.V end
	return { X = o and o.X or def.X, Y = o and o.Y or def.Y, S = o and o.S or def.S, O = o and o.O or 1, V = v }
end

function Settings.SetLayout(id, patch)
	if not TOUCH[id] then return end
	local o = layout[id] or {}
	layout[id] = o
	for k, v in patch do o[k] = v end
	o.X, o.Y = math.clamp(o.X or TOUCH[id].X, 0, 1), math.clamp(o.Y or TOUCH[id].Y, 0, 1)
	if o.S then o.S = math.clamp(o.S, 0.5, 2.2) end
	if o.O then o.O = math.clamp(o.O, 0.1, 1) end
	notify("Layout", id)
	markDirty()
end

function Settings.ResetLayout(id)
	if id then layout[id] = nil else layout = {} end
	notify("Layout", id)
	markDirty()
end

function Settings.MirrorLayout()
	for _, t in Settings.TouchButtons do
		local cur = Settings.GetLayout(t.Id)
		local o = layout[t.Id] or {}
		layout[t.Id] = o
		o.X = 1 - cur.X
	end
	notify("Layout")
	markDirty()
end

function Settings.SnapshotLayout()
	local snap = {}
	for id, o in layout do snap[id] = table.clone(o) end
	return snap
end

function Settings.RestoreLayout(snap)
	layout = {}
	for id, o in snap do layout[id] = table.clone(o) end
	notify("Layout")
	markDirty()
end

-- ================================================================ serialization + validation (used by the server too)
local function validCode(code, device)
	if code == "" then return true end
	if type(code) ~= "string" or #code > 24 then return false end
	local kind, name = code:match("^(%a):(%w+)$")
	if not kind then return false end
	if device == "KBM" then
		if kind == "M" then return name == "1" or name == "2" or name == "3" end
		if kind == "W" then return name == "Up" or name == "Down" end
		if kind ~= "K" then return false end
	elseif kind ~= "G" then
		return false
	end
	return (pcall(function() return Enum.KeyCode[name] end))
end

function Settings.Sanitize(blob)
	local out = { V = {}, Binds = {}, Touch = {} }
	if type(blob) ~= "table" then return out end
	if type(blob.V) == "table" then
		for key, e in ENTRY do
			local v = blob.V[key]
			if v ~= nil then
				local ok, clean = coerce(e, v)
				if ok then out.V[key] = clean end
			end
		end
	end
	if type(blob.Binds) == "table" then
		for _, a in Settings.Actions do
			local b = blob.Binds[a.Id]
			if type(b) == "table" then
				local clean = {}
				for _, device in { "KBM", "PAD" } do
					local list = b[device]
					if type(list) == "table" then
						local pair = {}
						for i = 1, 2 do
							pair[i] = validCode(list[i] or "", device) and (list[i] or "") or ""
						end
						clean[device] = pair
					end
				end
				if clean.KBM and clean.PAD then out.Binds[a.Id] = clean end
			end
		end
	end
	if type(blob.Touch) == "table" then
		for _, t in Settings.TouchButtons do
			local o = blob.Touch[t.Id]
			if type(o) == "table" then
				local c = {}
				if type(o.X) == "number" and o.X == o.X then c.X = math.clamp(o.X, 0, 1) end
				if type(o.Y) == "number" and o.Y == o.Y then c.Y = math.clamp(o.Y, 0, 1) end
				if type(o.S) == "number" and o.S == o.S then c.S = math.clamp(o.S, 0.5, 2.2) end
				if type(o.O) == "number" and o.O == o.O then c.O = math.clamp(o.O, 0.1, 1) end
				if type(o.V) == "boolean" then c.V = o.V end
				out.Touch[t.Id] = c
			end
		end
	end
	return out
end

function Settings.Serialize()
	local blob = { V = table.clone(values), Binds = {}, Touch = {} }
	for id, b in binds do
		blob.Binds[id] = { KBM = table.clone(b.KBM), PAD = table.clone(b.PAD) }
	end
	for id, o in layout do blob.Touch[id] = table.clone(o) end
	return blob
end

function Settings.Load(blob)
	local clean = Settings.Sanitize(blob)
	for key, v in clean.V do values[key] = v end
	for id, b in clean.Binds do binds[id] = b end
	layout = clean.Touch
	notify("All")
end

function Settings.ResetAll()
	for key, e in ENTRY do values[key] = e.Default end
	for _, a in Settings.Actions do binds[a.Id] = defaultBindsFor(a) end
	layout = {}
	notify("All")
	markDirty()
end

-- ================================================================ client side: persistence + live appliers
local started = false
local loadedCbs = {}
Settings.Loaded = false
function Settings.Flush() end -- replaced by StartClient (sends any unsaved change right now)

-- UI scale helper: fit a design (refHeight tall) to the screen, clamped, times the player's own scale option.
function Settings.AutoScale(viewport, refHeight, minScale, maxScale)
	return math.clamp(viewport.Y / refHeight, minScale or 0.5, maxScale or 1.6)
end

function Settings.OnLoaded(fn)
	if Settings.Loaded then task.spawn(fn) else table.insert(loadedCbs, fn) end
end

local QUALITY = { Low = "Level03", Medium = "Level06", High = "Level10", Ultra = "Level15" }
local POST = { Bloom = "BloomEffect", SunRays = "SunRaysEffect", DepthOfField = "DepthOfFieldEffect" }
local postOriginal = setmetatable({}, { __mode = "k" })
local colorFx
local soundGroups

local function applyPost(name)
	local on = values["Graphics." .. name]
	for _, inst in Lighting:GetChildren() do
		if inst:IsA(POST[name]) then
			if postOriginal[inst] == nil then postOriginal[inst] = inst.Enabled end
			inst.Enabled = on and postOriginal[inst]
		end
	end
end

local function applyColor()
	if not colorFx or not colorFx.Parent then
		colorFx = Instance.new("ColorCorrectionEffect")
		colorFx.Name = "FPSSettingsColor"
		colorFx.Parent = Lighting
	end
	colorFx.Brightness = values["Graphics.Brightness"] / 100
	colorFx.Contrast = values["Graphics.Contrast"] / 100
end

local VOLUME = { ["Audio.Master"] = "Master", ["Audio.Sfx"] = "SFX", ["Audio.Music"] = "Music", ["Audio.Voice"] = "Voice", ["Audio.Ui"] = "UI" }

local function ensureSoundGroups()
	if soundGroups then return soundGroups end
	soundGroups = {}
	local master = SoundService:FindFirstChild("Master") or Instance.new("SoundGroup")
	master.Name, master.Parent = "Master", SoundService
	soundGroups.Master = master
	for _, n in { "SFX", "Music", "Voice", "UI" } do
		local g = master:FindFirstChild(n) or Instance.new("SoundGroup")
		g.Name, g.Parent = n, master
		soundGroups[n] = g
	end
	return soundGroups
end

-- Route any Sound through the volume sliders:  sound.SoundGroup = Settings.SoundGroup("SFX")   (SFX / Music / Voice / UI)
function Settings.SoundGroup(name)
	return ensureSoundGroups()[name]
end

local perf
local function updatePerf()
	local want = values["Graphics.ShowFps"] or values["Graphics.ShowPing"]
	if not want then
		if perf then perf.Gui.Enabled = false end
		return
	end
	if not perf then
		local gui = Instance.new("ScreenGui")
		gui.Name, gui.ResetOnSpawn, gui.IgnoreGuiInset, gui.DisplayOrder = "PerfOverlay", false, true, 200
		gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
		local lbl = Instance.new("TextLabel")
		lbl.BackgroundTransparency, lbl.AnchorPoint = 1, Vector2.new(1, 0)
		lbl.Position, lbl.Size = UDim2.new(1, -12, 0, 8), UDim2.fromOffset(200, 40)
		lbl.Font, lbl.TextSize, lbl.TextColor3 = Enum.Font.Code, 14, Color3.fromRGB(240, 242, 244)
		lbl.TextXAlignment, lbl.TextYAlignment = Enum.TextXAlignment.Right, Enum.TextYAlignment.Top
		lbl.TextStrokeTransparency = 0.5
		lbl.Text = ""
		lbl.Parent = gui
		perf = { Gui = gui, Label = lbl, Frames = 0, T = 0 }
		RunService.Heartbeat:Connect(function(dt)
			if not perf.Gui.Enabled then return end
			perf.Frames += 1
			perf.T += dt
			if perf.T >= 0.5 then
				local lines = {}
				if values["Graphics.ShowFps"] then table.insert(lines, ("FPS %d"):format(math.floor(perf.Frames / perf.T + 0.5))) end
				if values["Graphics.ShowPing"] then
					table.insert(lines, ("PING %d ms"):format(math.floor(Players.LocalPlayer:GetNetworkPing() * 1000 + 0.5)))
				end
				perf.Label.Text = table.concat(lines, "\n")
				perf.Frames, perf.T = 0, 0
			end
		end)
	end
	perf.Gui.Enabled = true
end

local function applyKey(key)
	if key == "Graphics.Quality" then
		pcall(function()
			local lvl = values[key]
			settings().Rendering.QualityLevel = lvl == "Auto" and Enum.QualityLevel.Automatic or Enum.QualityLevel[QUALITY[lvl]]
		end)
	elseif key == "Graphics.Shadows" then
		Lighting.GlobalShadows = values[key]
	elseif key == "Graphics.Bloom" or key == "Graphics.SunRays" or key == "Graphics.DepthOfField" then
		applyPost(key:sub(10))
	elseif key == "Graphics.Brightness" or key == "Graphics.Contrast" then
		applyColor()
	elseif key == "Graphics.ShowFps" or key == "Graphics.ShowPing" then
		updatePerf()
	elseif VOLUME[key] then
		ensureSoundGroups()[VOLUME[key]].Volume = values[key] / 100
	end
end

local APPLIED = { "Graphics.Quality", "Graphics.Shadows", "Graphics.Bloom", "Graphics.SunRays", "Graphics.DepthOfField",
	"Graphics.Brightness", "Graphics.ShowFps", "Graphics.ShowPing", "Audio.Master", "Audio.Sfx", "Audio.Music", "Audio.Voice", "Audio.Ui" }

local function applyAll()
	for _, key in APPLIED do applyKey(key) end
end

-- remotes = ReplicatedStorage.FPS.Remotes. Applies defaults immediately, then loads the saved options from the server in the background.
function Settings.StartClient(remotes)
	if started then return end
	started = true
	ensureSoundGroups()
	applyAll()
	Lighting.ChildAdded:Connect(function(inst)
		for name, class in POST do
			if inst:IsA(class) then task.defer(applyPost, name) end
		end
	end)
	Settings.OnChanged(function(key)
		if key == "All" then applyAll() else applyKey(key) end
	end)

	-- debounced save
	local pending = false
	local function send()
		pending = false
		remotes.SaveSettings:FireServer(Settings.Serialize())
	end
	function Settings.Flush()
		if pending then send() end
	end
	Settings.OnDirty = function()
		if not Settings.Loaded then return end -- never overwrite the saved options with defaults before they arrived
		if pending then return end
		pending = true
		task.delay(1.5, function()
			if pending then send() end
		end)
	end

	task.spawn(function()
		local data
		for _ = 1, 20 do
			local ok, res = pcall(function() return remotes.GetSettings:InvokeServer() end)
			if ok then
				data = res
				break
			end
			task.wait(0.5)
		end
		if type(data) == "table" then
			Settings.Load(data)
		elseif UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
			values["Gameplay.AdsMode"] = "Toggle" -- first launch on a phone: toggle aim is far easier on a touch screen
			notify("Gameplay.AdsMode", "Toggle")
		end
		Settings.Loaded = true
		for _, fn in loadedCbs do task.spawn(fn) end
		loadedCbs = {}
	end)
end

return Settings
