-- UISound: named sound slots for the match / objective presentation. They are empty (silent) until you paste an asset id, like
-- Config.Weapons.*.Sounds.Fire.  UISound.Slots.Tick = "rbxassetid://123456"   then   UISound.Play("Tick")
local SoundService = game:GetService("SoundService")
local Settings = require(script.Parent.Settings)

local UISound = {}

UISound.Slots = {
	Intro = "",      -- match start card
	Tick = "",       -- each countdown number
	Fight = "",      -- countdown reached zero
	Victory = "", Defeat = "",
	Death = "", Respawn = "",
	Capture = "",    -- flag captured / hill secured (your team)
	Lost = "",       -- flag lost / enemy holds the hill
	Confirm = "", Deny = "",
	Warn = "",       -- flag under attack, nearing victory
	FireMode = "",   -- fire mode switch click (auto <-> semi)
}

function UISound.Play(slot, volume)
	local id = UISound.Slots[slot]
	if not id or id == "" then return end
	local s = Instance.new("Sound")
	s.SoundId, s.Volume = id, volume or 0.8
	local ok, group = pcall(Settings.SoundGroup, "UI")
	if ok and group then s.SoundGroup = group end
	s.Parent = SoundService
	s.Ended:Once(function() s:Destroy() end)
	s:Play()
	task.delay(12, function() if s.Parent then s:Destroy() end end)
end

return UISound
