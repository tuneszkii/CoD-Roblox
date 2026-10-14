-- CineCam: scripted camera shots (match intro flyover, death cam, spectating, end-of-match orbit).
-- A shot is  { Update = function(t, dt) -> CFrame, fov?, In = blend-in seconds, Out = blend-out seconds, ShowBody?, HideHud?, HideViewmodel? (default true) }.
-- It runs on top of the first-person rig: CameraRig sets the player's view every frame, then this blends towards the shot (weight 0..1),
-- so a shot fades in from, and back out to, whatever the player was looking at. With no live character the shot simply owns the camera.
--   CineCam.Play(shot)     start (replaces the current shot)
--   CineCam.Stop(seconds)  blend out
--   CineCam.OnChange(fn)   fn(on, shot): the shot now covers the view (weight > 0.5) / no longer does. FPSMain hides the gun + HUD there.
--   CineCam.IsRigActive    set by FPSMain: function() -> bool (is the first-person rig driving the camera?)
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local CineCam = {}
CineCam.IsRigActive = function() return false end

local shot, weight, wanted, startT = nil, 0, 0, 0
local covering = false
local listeners = {}

local function ease(x) return x * x * (3 - 2 * x) end

local function setCovering(on)
	if covering == on then return end
	covering = on
	for _, fn in table.clone(listeners) do task.spawn(fn, on, shot) end
end

local function finish()
	local cam = workspace.CurrentCamera
	setCovering(false)
	shot = nil
	weight, wanted = 0, 0
	if cam and not CineCam.IsRigActive() then -- hand the camera back to Roblox
		cam.CameraType = Enum.CameraType.Custom
		local char = Players.LocalPlayer.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if hum then cam.CameraSubject = hum end
	end
end

function CineCam.Play(def)
	shot = def -- a shot that is already on screen keeps its blend weight, so swapping shots does not drop back to the player's view
	startT = os.clock()
	wanted = 1
end

function CineCam.Stop(seconds)
	if not shot then return end
	if seconds then shot.Out = seconds end
	wanted = 0
end

function CineCam.IsPlaying() return shot ~= nil and wanted == 1 end
function CineCam.OnChange(fn) table.insert(listeners, fn) end

RunService:BindToRenderStep("FPS_Cine", Enum.RenderPriority.Camera.Value + 2, function(dt)
	if not shot then return end
	local cam = workspace.CurrentCamera
	if not cam then return end
	local seconds = wanted == 1 and (shot.In or 0.5) or (shot.Out or 0.5)
	local step = dt / math.max(seconds, 0.001)
	weight = math.clamp(weight + (wanted == 1 and step or -step), 0, 1)
	if wanted == 0 and weight <= 0 then
		finish()
		return
	end

	local ok, cf, fov = pcall(shot.Update, os.clock() - startT, dt)
	if not ok or typeof(cf) ~= "CFrame" then
		if not ok then warn("[CineCam] " .. tostring(cf)) end
		wanted = 0
		return
	end
	if cam.CameraType ~= Enum.CameraType.Scriptable then cam.CameraType = Enum.CameraType.Scriptable end
	local w = ease(weight)
	cam.CFrame = cam.CFrame:Lerp(cf, w)
	local target = fov or shot.fov or 70
	cam.FieldOfView += (target - cam.FieldOfView) * w
	setCovering(weight > 0.5)
end)

return CineCam
