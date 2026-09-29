--[[
    Hood Customs — Camlock + Silent Aim
    Re-inject anytime: unloads the previous instance and applies this Settings table.
]]

---@diagnostic disable: undefined-global
local _getgenv = getgenv
local ENV = (type(_getgenv) == "function" and _getgenv()) or (type(_getgenv) == "table" and _getgenv) or _G

if type(ENV.HC_Unload) == "function" then
    pcall(ENV.HC_Unload)
end

local InstanceId = (tonumber(ENV.HC_InstanceId) or 0) + 1
ENV.HC_InstanceId = InstanceId

local function Alive()
    return ENV.HC_InstanceId == InstanceId
end

-- Force fresh settings on re-inject, but allow runtime changes
if not getgenv().bossmen then
    getgenv().bossmen = {}
end

local DefaultSettings = {
    Camlock = {
        Enabled = true,
        Keybind = "c",
        Hold = false,
        FOV = 200,
        DrawFOV = false,
        FOVColor = Color3.fromRGB(80, 180, 255),
        HitPart = "Head",
        Smoothness = true,
        SmoothnessX = 0.1,
        SmoothnessY = 0.4,
        PredictionX = 0.12,
        PredictionY = 0.11,
        StickyAim = true,
        WallCheck = true,
        FriendCheck = false,
        KOCheck = true,
        ClosestPoint = false,
        AutoShoot = false,
        KillDelay = 0.5,
        Visuals = {
            Highlight = true,
            HighlightColor = Color3.fromRGB(255, 255, 255),
        },
    },

    SilentAim = {
        Enabled = true,
        Method = "TargetAim",
        FOV = 99,
        DrawFOV = false,
        FOVColor = Color3.fromRGB(255, 0, 0),
        HitPart = "Head",
        Prediction = 0,
        WallCheck = true,
        FriendCheck = true,
        KOCheck = true,
        ClosestPoint = false,
        AntiAimViewer = true,
        HitChance = true,
        HitChanceInAir = 50,
        HitChanceOnGround = 100,
    },

    Misc = {
        Macro = {
            Enabled = true,
            Keybind = "q",
        },
    },
    
    SkinChanger = {
        Enabled = true,
        Skins = {
            ["DoubleBarrel"] = "Crimson Fangs",
            ["Revolver"] = "Poseidon",
            ["TacticalShotgun"] = "Crimson Fangs",
            ["SMG"] = "Ascension",
            ["Shotgun"] = "Ascension",
        },
        Special = {
            ["Knife"] = "Beta",
        },
    },
}

-- Merge defaults with existing settings (preserves runtime changes)
for category, settings in pairs(DefaultSettings) do
    if not getgenv().bossmen[category] then
        getgenv().bossmen[category] = settings
    else
        for key, value in pairs(settings) do
            if getgenv().bossmen[category][key] == nil then
                getgenv().bossmen[category][key] = value
            end
        end
    end
end

ENV.HC = getgenv().bossmen

------------------------------------------------------------------
-- Services
------------------------------------------------------------------
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer
local Mouse = LocalPlayer:GetMouse()
local Camera = workspace.CurrentCamera

local WorkspaceRaycast = nil
pcall(function()
    if type(clonefunction) == "function" then
        WorkspaceRaycast = clonefunction(workspace.Raycast)
    else
        WorkspaceRaycast = workspace.Raycast
    end
end)

ENV.HC_Aim = ENV.HC_Aim or { Part = nil, Pos = nil }
ENV.HC_Aim.Part = nil
ENV.HC_Aim.Pos = nil
ENV.HC_RealMouse = ENV.HC_RealMouse or { Pos = Vector3.zero, Target = nil }
ENV.HC_RealMouse.Pos = Vector3.zero
ENV.HC_RealMouse.Target = nil
ENV.HC_Mouse = Mouse

local Connections = {}
local Drawings = {}

local function Track(c)
    Connections[#Connections + 1] = c
    return c
end

local function TrackDrawing(o)
    Drawings[#Drawings + 1] = o
    return o
end

local function Unload()
    for _, c in ipairs(Connections) do
        pcall(function() c:Disconnect() end)
    end
    table.clear(Connections)
    for _, o in ipairs(Drawings) do
        pcall(function()
            o.Visible = false
            if o.Remove then o:Remove() elseif o.Destroy then o:Destroy() end
        end)
    end
    table.clear(Drawings)
    pcall(function()
        if CamHighlight then
            CamHighlight.Adornee = nil
            CamHighlight:Destroy()
        end
    end)
    if ENV.HC_Aim then
        ENV.HC_Aim.Part = nil
        ENV.HC_Aim.Pos = nil
    end
    if ENV.HC_RealMouse then
        ENV.HC_RealMouse.Pos = Vector3.zero
        ENV.HC_RealMouse.Target = nil
    end
    pcall(function()
        RunService:UnbindFromRenderStep("HC_AntiAimViewer_RealMouse")
        RunService:UnbindFromRenderStep("HC_AntiAimViewer_Override")
    end)
    if ENV.HC_InstanceId == InstanceId then
        ENV.HC_InstanceId = InstanceId + 0.5
    end
end

ENV.HC_Unload = Unload

Track(workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
    if Alive() then Camera = workspace.CurrentCamera end
end))

------------------------------------------------------------------
-- State
------------------------------------------------------------------
local CamLockedPlayer = nil
local CamAimPos = nil
local CamlockHolding = false
local LastSilentName = nil
local LastKillTime = 0

local SilentCircle = TrackDrawing(Drawing.new("Circle"))
SilentCircle.Thickness = 1
SilentCircle.NumSides = 64
SilentCircle.Filled = false
SilentCircle.Visible = false

local CamCircle = TrackDrawing(Drawing.new("Circle"))
CamCircle.Thickness = 1
CamCircle.NumSides = 64
CamCircle.Filled = false
CamCircle.Visible = false

local CamHighlight = Instance.new("Highlight")
CamHighlight.Parent = game:GetService("CoreGui")
CamHighlight.FillTransparency = 1
CamHighlight.OutlineTransparency = 0
CamHighlight.OutlineColor = Color3.fromRGB(255, 255, 255)
CamHighlight.Adornee = nil
CamHighlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop

local BODY_PARTS = {
    "Head", "HumanoidRootPart", "UpperTorso", "LowerTorso", "Torso",
    "LeftUpperArm", "RightUpperArm", "LeftLowerArm", "RightLowerArm",
    "LeftHand", "RightHand", "Left Arm", "Right Arm",
    "LeftUpperLeg", "RightUpperLeg", "LeftLowerLeg", "RightLowerLeg",
    "LeftFoot", "RightFoot", "Left Leg", "Right Leg",
}

------------------------------------------------------------------
-- Mouse / prediction / checks
------------------------------------------------------------------
local function Cfg()
    return ENV.HC
end

local function GetMouseScreen()
    local ok, pos = pcall(function() return UserInputService:GetMouseLocation() end)
    if ok and typeof(pos) == "Vector2" then return pos end
    return Vector2.new(Mouse.X, Mouse.Y)
end

local function GetMouseViewport()
    return Vector2.new(Mouse.X, Mouse.Y)
end

-- True world point under the cursor (never silent target). Used by Anti Aim Viewer.
local function RefreshRealMouse()
    local Store = ENV.HC_RealMouse
    if not Store then
        Store = { Pos = Vector3.zero, Target = nil }
        ENV.HC_RealMouse = Store
    end

    local Cam = workspace.CurrentCamera or Camera
    if not Cam then
        return Store.Pos
    end

    -- Mouse.X/Y + ScreenPointToRay (same as working AAV scripts — not Viewport/GuiInset mix)
    local UnitRay = Cam:ScreenPointToRay(Mouse.X, Mouse.Y)

    local Params = RaycastParams.new()
    Params.FilterType = Enum.RaycastFilterType.Exclude
    Params.FilterDescendantsInstances = {
        LocalPlayer.Character,
        workspace:FindFirstChild("Ignored"),
        Cam,
    }
    Params.IgnoreWater = true

    local Dir = UnitRay.Direction * 1000
    local Result
    if WorkspaceRaycast then
        Result = WorkspaceRaycast(workspace, UnitRay.Origin, Dir, Params)
    else
        Result = workspace:Raycast(UnitRay.Origin, Dir, Params)
    end

    if Result then
        Store.Pos = Result.Position
        Store.Target = Result.Instance
    else
        Store.Pos = UnitRay.Origin + Dir
        Store.Target = nil
    end
    Store.Origin = UnitRay.Origin
    Store.Direction = UnitRay.Direction
    return Store.Pos
end

ENV.HC_RefreshRealMouse = RefreshRealMouse

local function KeyCodeFromName(name)
    return Enum.KeyCode[string.upper(tostring(name or ""))]
end

local function PredictPosition(Part, Section, Mode)
    if not Part then return nil end
    local Vel = Part.AssemblyLinearVelocity or Part.Velocity or Vector3.zero
    if Mode == "camlock" then
        local PX = tonumber(Section.PredictionX) or 0
        local PY = tonumber(Section.PredictionY) or 0
        if PX == 0 and PY == 0 then return Part.Position end
        return Part.Position + Vector3.new(Vel.X * PX, Vel.Y * PY, Vel.Z * PX)
    end
    local P = tonumber(Section.Prediction) or 0
    if P == 0 then return Part.Position end
    return Part.Position + Vel * P
end

local function IsFriendly(Player)
    if Player == LocalPlayer then return true end
    local ok, v = pcall(function() return LocalPlayer:IsFriendsWith(Player.UserId) end)
    return ok and v == true
end

local function IsKO(Character, Humanoid)
    if not Character or not Humanoid then return true end
    local BodyEffects = Character:FindFirstChild("BodyEffects")
    if BodyEffects then
        local KO = BodyEffects:FindFirstChild("K.O") or BodyEffects:FindFirstChild("KO")
        if KO and KO:IsA("BoolValue") and KO.Value then return true end
    end
    -- only treat as KO via health if BodyEffects missing (Da Hood knocked ~ <14)
    if not BodyEffects and Humanoid.Health > 0 and Humanoid.Health < 5 then
        return true
    end
    return false
end

-- Ray from camera → target. Ignores non-collidable / see-through junk so LOS isn't flaky.
local function IsBehindWall(TargetPart)
    if not TargetPart or not Camera then return true end
    local Char = LocalPlayer.Character
    local Origin = Camera.CFrame.Position
    local Goal = TargetPart.Position
    local Delta = Goal - Origin
    local Dist = Delta.Magnitude
    if Dist < 2 then return false end

    local Params = RaycastParams.new()
    Params.FilterType = Enum.RaycastFilterType.Exclude
    Params.FilterDescendantsInstances = { Char, TargetPart.Parent }
    Params.IgnoreWater = true

    local Dir = Delta.Unit * (Dist - 1)
    local Hit
    if WorkspaceRaycast then
        Hit = WorkspaceRaycast(workspace, Origin, Dir, Params)
    else
        Hit = workspace:Raycast(Origin, Dir, Params)
    end
    if not Hit or not Hit.Instance then return false end
    -- treat non-solid / invisible as not blocking
    if Hit.Instance.CanCollide == false then return false end
    if Hit.Instance.Transparency >= 0.9 then return false end
    return true
end

-- True if head OR torso OR HRP has clear LOS (stops silent flickering off every frame)
local function HasLineOfSight(Character)
    if not Character then return false end
    local Parts = {
        Character:FindFirstChild("Head"),
        Character:FindFirstChild("UpperTorso") or Character:FindFirstChild("Torso"),
        Character:FindFirstChild("HumanoidRootPart"),
    }
    for _, Part in ipairs(Parts) do
        if Part and not IsBehindWall(Part) then
            return true
        end
    end
    return false
end

local function BasicValid(Player, Section)
    if not Player or Player == LocalPlayer then return false end
    local Character = Player.Character
    if not Character then return false end
    local Humanoid = Character:FindFirstChildOfClass("Humanoid")
    local Root = Character:FindFirstChild("HumanoidRootPart") or Character:FindFirstChild("Head")
    if not Humanoid or not Root or Humanoid.Health <= 0 then return false end
    if Section.FriendCheck and IsFriendly(Player) then return false end
    if Section.KOCheck and IsKO(Character, Humanoid) then return false end
    return true, Character, Humanoid, Root
end

local function GetHitPart(Character, Name)
    if not Character then return nil end
    return Character:FindFirstChild(Name)
        or Character:FindFirstChild("Head")
        or Character:FindFirstChild("HumanoidRootPart")
end

-- Closest *body part center* to mouse (no surface math — that was aiming into walls)
local function GetClosestBodyPart(Character, MousePos)
    local Best, BestDist = nil, math.huge
    for _, Name in ipairs(BODY_PARTS) do
        local Part = Character:FindFirstChild(Name)
        if Part and Part:IsA("BasePart") then
            local Screen, OnScreen = Camera:WorldToViewportPoint(Part.Position)
            if OnScreen and Screen.Z > 0 then
                local Dist = (MousePos - Vector2.new(Screen.X, Screen.Y)).Magnitude
                if Dist < BestDist then
                    BestDist = Dist
                    Best = Part
                end
            end
        end
    end
    return Best
end

local function GetAimPartAndPos(Character, Section, MousePos, Mode)
    local Part
    if Section.ClosestPoint then
        Part = GetClosestBodyPart(Character, MousePos)
    end
    Part = Part or GetHitPart(Character, Section.HitPart)
    if not Part then return nil, nil end
    return Part, PredictPosition(Part, Section, Mode)
end

--[[
    Closest PLAYER to mouse within FOV.
    Independent for silent + camlock (never shares lock state).
    Opts.SkipWall — force ignore walls (default: respect Section.WallCheck)
]]
local function GetClosestPlayerToMouse(Section, Opts)
    Opts = Opts or {}
    if not Camera or not Section then return nil end

    local MousePos = GetMouseViewport()
    local MaxFov = Opts.IgnoreFOV and math.huge or (tonumber(Section.FOV) or 100)
    local BestPlayer, BestDist = nil, MaxFov
    local UseWall = Section.WallCheck and not Opts.SkipWall

    for _, Player in ipairs(Players:GetPlayers()) do
        local ok, Character, _, Root = BasicValid(Player, Section)
        if ok then
            local Head = Character:FindFirstChild("Head") or Root
            local Screen, OnScreen = Camera:WorldToViewportPoint(Head.Position)
            if OnScreen and Screen.Z > 0 then
                local Dist = (MousePos - Vector2.new(Screen.X, Screen.Y)).Magnitude
                if Dist < BestDist then
                    if not UseWall or HasLineOfSight(Character) then
                        BestDist = Dist
                        BestPlayer = Player
                    end
                end
            end
        end
    end

    return BestPlayer, BestDist
end

local function GetTargetAim(Section, Mode, Opts)
    local Player = GetClosestPlayerToMouse(Section, Opts)
    if not Player or not Player.Character then return nil, nil, nil end
    local Part, Aim = GetAimPartAndPos(Player.Character, Section, GetMouseViewport(), Mode)
    if not Part or not Aim then return nil, nil, nil end
    return Player, Part, Aim
end

local function ClearCamLock()
    CamLockedPlayer = nil
    CamAimPos = nil
end

local function GetAimForLockedPlayer(Player, Section, Mode)
    if not Player or not Player.Parent then return nil, nil end
    local ok, Character = BasicValid(Player, Section)
    if not ok then return nil, nil end
    -- sticky: keep tracking even through walls once locked; lock-on itself used wallcheck
    return GetAimPartAndPos(Character, Section, GetMouseViewport(), Mode)
end

------------------------------------------------------------------
-- Silent hooks (once per session) — Shoot only, no FireServer hookfunction
------------------------------------------------------------------
local function SetSilentAimCache(Part, Pos)
    if ENV.HC_Aim then
        ENV.HC_Aim.Part = Part
        ENV.HC_Aim.Pos = Pos
    end
end


local function RewriteMousePosUpdate(Args)
    local HC = ENV.HC
    local Silent = HC and HC.SilentAim
    if not Silent or not Silent.AntiAimViewer then return false end

    local RealPos = RefreshRealMouse()
    if typeof(RealPos) ~= "Vector3" then return false end

    local Store = ENV.HC_RealMouse
    local HitPart = Store and Store.Target
    if HitPart and not HitPart:IsA("BasePart") then
        HitPart = nil
    end

    local Velocity = Vector3.zero
    if HitPart then
        local Root = HitPart.AssemblyRootPart
        if Root then
            Velocity = Root.AssemblyLinearVelocity
        end
    end

    _G.MOUSE_POSITION = RealPos

    local A2 = Args[2]
    local T2 = typeof(A2)

    -- Keep whatever format the game already uses — only swap the position
    if T2 == "Vector3" then
        Args[2] = RealPos
        if Args[3] ~= nil then Args[3] = RealPos end
        if Args[4] ~= nil then Args[4] = Velocity end
        return true
    end

    if T2 == "CFrame" then
        Args[2] = CFrame.new(RealPos)
        if Args[3] ~= nil then Args[3] = RealPos end
        return true
    end

    if T2 == "table" then
        if HitPart then
            A2.thePart = HitPart
            A2.theOffset = HitPart.CFrame:PointToObjectSpace(RealPos)
        else
            A2.thePart = nil
            A2.theOffset = nil
        end
        if A2.Position ~= nil then A2.Position = RealPos end
        if A2.Hit ~= nil then A2.Hit = RealPos end
        if A2.p ~= nil then A2.p = RealPos end
        Args[2] = A2
        Args[3] = RealPos
        Args[4] = Velocity
        return true
    end

    -- Unknown / nil — send plain world pos (most MainEvent MousePosUpdate variants)
    Args[2] = RealPos
    Args[3] = RealPos
    Args[4] = Velocity
    return true
end

local function RewriteShootArgs(Args)
    local HC = ENV.HC
    local AimStore = ENV.HC_Aim
    if not HC or not HC.SilentAim then return false end

    local Silent = HC.SilentAim
    local EventName = Args[1]
    if typeof(EventName) ~= "string" then return false end
    local Lower = string.lower(EventName)

    -- Anti Aim Viewer: force MousePosUpdate to REAL crosshair (never silent target)
    if (EventName == "MousePosUpdate" or Lower == "mouseposupdate") and Silent.AntiAimViewer then
        return RewriteMousePosUpdate(Args)
    end

    if not Silent.Enabled then return false end
    if not AimStore or not AimStore.Pos then return false end
    if AimStore.Part and not AimStore.Part.Parent then return false end

    local Aim = AimStore.Pos

    -- Shoot packet only — this is what actually hits
    if EventName == "Shoot" or Lower == "shoot" then
        local Data = Args[2]
        if typeof(Data) == "table" then
            Data.AIM = Aim
            if Data.Aim ~= nil then Data.Aim = Aim end
            return true
        elseif typeof(Data) == "Vector3" then
            Args[2] = Aim
            return true
        elseif typeof(Data) == "CFrame" then
            Args[2] = CFrame.new(Aim)
            return true
        end
        return false
    end

    -- Without AAV: also rewrite mouse sync remotes to silent target (blatant)
    -- With AAV: leave mouse remotes alone so aim viewers see real look direction
    if not Silent.AntiAimViewer and string.find(Lower, "mouse", 1, true) then
        if typeof(Args[2]) == "Vector3" then
            Args[2] = Aim
            return true
        elseif typeof(Args[2]) == "CFrame" then
            Args[2] = CFrame.new(Aim)
            return true
        end
    end

    return false
end

ENV.HC_RewriteShoot = RewriteShootArgs
ENV.HC_RewriteMousePos = RewriteMousePosUpdate

-- Mouse.Hit must stay spoofed for silent to redirect bullets (local only).
-- AntiAimViewer only fakes MousePosUpdate for other players' aim viewers.
ENV.HC_ResolveMouseIndex = function(Key)
    local HC = ENV.HC
    local Silent = HC and HC.SilentAim
    if not Silent or not Silent.Enabled then
        return nil, false
    end
    local AimStore = ENV.HC_Aim
    if not AimStore or not AimStore.Pos then
        return nil, false
    end
    local Aim = AimStore.Pos
    if Key == "Hit" then
        return CFrame.new(Aim), true
    elseif Key == "Target" then
        return AimStore.Part, true
    elseif Key == "UnitRay" then
        local Origin = (workspace.CurrentCamera and workspace.CurrentCamera.CFrame.Position) or Aim
        return Ray.new(Origin, (Aim - Origin).Unit * 1000), true
    end
    return nil, false
end

-- Bump when hook body changes so reinject re-wraps
local HOOK_VERSION = 4
if not ENV.HC_HooksInstalled or ENV.HC_HookVersion ~= HOOK_VERSION then
    ENV.HC_HooksInstalled = true
    ENV.HC_HookVersion = HOOK_VERSION

    pcall(function()
        local OldNamecall
        OldNamecall = hookmetamethod(game, "__namecall", function(Self, ...)
            local Method = getnamecallmethod()
            if (Method == "FireServer" or Method == "InvokeServer")
                and not checkcaller()
                and typeof(Self) == "Instance"
            then
                local Count = select("#", ...)
                if Count >= 1 then
                    local Args = { ... }
                    local Rewrite = ENV.HC_RewriteShoot
                    if type(Rewrite) == "function" and Rewrite(Args) then
                        local OutCount = Count
                        if typeof(Args[1]) == "string" and string.lower(Args[1]) == "mouseposupdate" then
                            OutCount = math.max(Count, 4)
                        end
                        return OldNamecall(Self, unpack(Args, 1, OutCount))
                    end
                end
            end
            return OldNamecall(Self, ...)
        end)

    end)

    pcall(function()
        local OldIndex
        OldIndex = hookmetamethod(game, "__index", function(Self, Key)
            if (Key == "Hit" or Key == "Target" or Key == "UnitRay")
                and Self == ENV.HC_Mouse
                and not checkcaller()
            then
                local Resolver = ENV.HC_ResolveMouseIndex
                if type(Resolver) == "function" then
                    local Ok, Value, Handled = pcall(Resolver, Key)
                    if Ok and Handled then
                        return Value
                    end
                end
            end
            return OldIndex(Self, Key)
        end)

    end)
else

end

------------------------------------------------------------------
-- Anti Aim Viewer — keep _G.MOUSE_POSITION = live cursor every frame
------------------------------------------------------------------
pcall(function()
    RunService:UnbindFromRenderStep("HC_AntiAimViewer_RealMouse")
    RunService:UnbindFromRenderStep("HC_AntiAimViewer_Override")
end)

-- First: compute real world hit under cursor
RunService:BindToRenderStep("HC_AntiAimViewer_RealMouse", Enum.RenderPriority.First.Value, function()
    if not Alive() then return end
    RefreshRealMouse()
end)

-- Last: force game globals to real cursor (after anything that wrote silent Hit)
RunService:BindToRenderStep("HC_AntiAimViewer_Override", Enum.RenderPriority.Last.Value, function()
    if not Alive() then return end
    local HC = ENV.HC
    local Silent = HC and HC.SilentAim
    if not Silent or not Silent.AntiAimViewer then return end
    local Pos = RefreshRealMouse()
    if typeof(Pos) == "Vector3" then
        _G.MOUSE_POSITION = Pos
        pcall(function()
            rawset(_G, "MOUSE_POSITION", Pos)
        end)
    end
end)

------------------------------------------------------------------
-- Camlock + Misc input
------------------------------------------------------------------
Track(UserInputService.InputBegan:Connect(function(Input, GameProcessed)
    if not Alive() or GameProcessed then return end
    if Input.UserInputType ~= Enum.UserInputType.Keyboard then return end

    local HC = Cfg()
    if not HC then return end

    local C = HC.Camlock
    if C then
        local CamKey = KeyCodeFromName(C.Keybind)
        if CamKey and Input.KeyCode == CamKey then
            if C.Hold then
                CamlockHolding = true
                if C.StickyAim and not CamLockedPlayer then
                    -- respect WallCheck — won't lock people behind walls
                    CamLockedPlayer = GetClosestPlayerToMouse(C)
                    if CamLockedPlayer then
                    else
                    end
                end
            elseif C.StickyAim then
                if not C.Enabled then
                elseif CamLockedPlayer then
                    ClearCamLock()
                else
                    local killDelay = tonumber(C.KillDelay) or 0.5
                    if tick() - LastKillTime >= killDelay then
                        CamLockedPlayer = GetClosestPlayerToMouse(C)
                        if CamLockedPlayer then
                        else
                        end
                    end
                end
            else
                C.Enabled = not C.Enabled
                ClearCamLock()
            end
        end
    end

    local Misc = HC.Misc
    if Misc then
        local Macro = Misc.Macro
        if Macro and Macro.Enabled then
            local K = KeyCodeFromName(Macro.Keybind)
            if K and Input.KeyCode == K then
                getgenv().HC_MacroActive = true
                task.spawn(function()
                    local VIM = game:GetService("VirtualInputManager")
                    while getgenv().HC_MacroActive do
                        RunService.Heartbeat:Wait()
                        VIM:SendMouseWheelEvent("0.1", "0.1", true, game)
                        RunService.Heartbeat:Wait()
                        VIM:SendMouseWheelEvent("0.1", "0.1", false, game)
                        RunService.Heartbeat:Wait()
                    end
                end)
            end
        end
    end
end))

Track(UserInputService.InputEnded:Connect(function(Input)
    if not Alive() then return end
    if Input.UserInputType ~= Enum.UserInputType.Keyboard then return end
    
    local C = Cfg() and Cfg().Camlock
    if C then
        local CamKey = KeyCodeFromName(C.Keybind)
        if CamKey and Input.KeyCode == CamKey and C.Hold then
            CamlockHolding = false
            ClearCamLock()
        end
    end
    
    local Misc = Cfg() and Cfg().Misc
    if Misc and Misc.Macro and Misc.Macro.Enabled then
        local K = KeyCodeFromName(Misc.Macro.Keybind)
        if K and Input.KeyCode == K then
            getgenv().HC_MacroActive = false
        end
    end
end))

Track(Players.PlayerRemoving:Connect(function(Player)
    if CamLockedPlayer == Player then ClearCamLock() end
end))

Track(LocalPlayer.CharacterAdded:Connect(function()
    -- reset misc flags visually; speeds re-apply in loop if still enabled
    task.wait(0.5)
end))

------------------------------------------------------------------
-- Main loop
------------------------------------------------------------------
Track(RunService.RenderStepped:Connect(function(Dt)
    if not Alive() then return end
    local HC = Cfg()
    if not HC then return end

    local MouseScreen = GetMouseScreen()
    if not Camera then return end

    -- Keep real cursor world-pos fresh for AAV (independent of silent Hit spoof)
    local S = HC.SilentAim
    if S and S.AntiAimViewer then
        local Pos = RefreshRealMouse()
        if typeof(Pos) == "Vector3" then
            _G.MOUSE_POSITION = Pos
        end
    end

    -- Silent: Method determines target selection
    if S and S.Enabled then
        local Player, Part, Aim
        
        if S.Method == "TargetAim" then
            -- Use camlock's locked target
            if CamLockedPlayer and CamLockedPlayer.Character then
                Part, Aim = GetAimPartAndPos(CamLockedPlayer.Character, S, GetMouseViewport(), "silent")
                if Part and Aim then
                    Player = CamLockedPlayer
                end
            end
        else
            -- Normal: closest to mouse within FOV
            Player, Part, Aim = GetTargetAim(S, "silent")
        end
        
        if Player and Part and Aim then
            local shouldHit = true
            
            if S.HitChance then
                local targetChar = Player.Character
                local humanoid = targetChar and targetChar:FindFirstChildOfClass("Humanoid")
                
                if humanoid then
                    local isInAir = humanoid:GetState() == Enum.HumanoidStateType.Freefall or 
                                    humanoid:GetState() == Enum.HumanoidStateType.Flying
                    
                    local chance = isInAir and (tonumber(S.HitChanceInAir) or 100) or (tonumber(S.HitChanceOnGround) or 100)
                    local roll = math.random(1, 100)
                    
                    shouldHit = roll <= chance
                end
            end
            
            if shouldHit then
                SetSilentAimCache(Part, Aim)
            else
                SetSilentAimCache(nil, nil)
            end
        else
            SetSilentAimCache(nil, nil)
            LastSilentName = nil
        end
        SilentCircle.Visible = S.DrawFOV == true
        SilentCircle.Color = S.FOVColor or Color3.fromRGB(255, 0, 0)
        SilentCircle.Radius = S.FOV
        SilentCircle.Position = MouseScreen
    else
        SetSilentAimCache(nil, nil)
        LastSilentName = nil
        SilentCircle.Visible = false
    end

    -- Camlock (separate target system — sticky lock only)
    local C = HC.Camlock
    local CamActive = C and C.Enabled and (not C.Hold or CamlockHolding)
    if CamActive then
        if C.StickyAim then
            if CamLockedPlayer then
                if not CamLockedPlayer.Parent then
                    ClearCamLock()
                else
                    local Part, Aim = GetAimForLockedPlayer(CamLockedPlayer, C, "camlock")
                    if Part and Aim then
                        CamAimPos = Aim
                    else
                        local Char = CamLockedPlayer.Character
                        local Hum = Char and Char:FindFirstChildOfClass("Humanoid")
                        if not Char or not Hum or Hum.Health <= 0 or IsKO(Char, Hum) then
                            LastKillTime = tick()
                            ClearCamLock()
                        end
                    end
                end
            else
                CamAimPos = nil
            end
        else
            local _, _, Aim = GetTargetAim(C, "camlock")
            CamAimPos = Aim
        end

        CamCircle.Visible = C.DrawFOV == true
        CamCircle.Color = C.FOVColor or Color3.fromRGB(80, 180, 255)
        CamCircle.Radius = C.FOV
        CamCircle.Position = MouseScreen
        
        if C.Visuals and C.Visuals.Highlight and CamLockedPlayer and CamLockedPlayer.Character then
            CamHighlight.Adornee = CamLockedPlayer.Character
            CamHighlight.OutlineColor = C.Visuals.HighlightColor or Color3.fromRGB(255, 255, 255)
        else
            CamHighlight.Adornee = nil
        end

        if CamAimPos then
            -- AutoShoot: automatically click when target is visible (Revolver only, 190 studs max)
            if C.AutoShoot and CamLockedPlayer and CamLockedPlayer.Character then
                local myChar = LocalPlayer.Character
                local equippedTool = myChar and myChar:FindFirstChildOfClass("Tool")
                
                if equippedTool and equippedTool.Name == "[Revolver]" then
                    local myRoot = myChar:FindFirstChild("HumanoidRootPart")
                    local targetRoot = CamLockedPlayer.Character:FindFirstChild("HumanoidRootPart")
                    
                    if myRoot and targetRoot then
                        local distance = (myRoot.Position - targetRoot.Position).Magnitude
                        local screenPos, onScreen = Camera:WorldToViewportPoint(targetRoot.Position)
                        
                        if distance <= 190 and onScreen and screenPos.Z > 0 and not IsBehindWall(targetRoot) then
                            local VIM = game:GetService("VirtualInputManager")
                            VIM:SendMouseButtonEvent(0, 0, 0, true, game, 0)
                            task.wait()
                            VIM:SendMouseButtonEvent(0, 0, 0, false, game, 0)
                        end
                    end
                end
            end
            
            local CurrentCF = Camera.CFrame
            local Goal = CFrame.lookAt(CurrentCF.Position, CamAimPos)
            
            if not C.Smoothness then
                Camera.CFrame = Goal
            else
                local SmoothX = tonumber(C.SmoothnessX) or 0.2
                local SmoothY = tonumber(C.SmoothnessY) or 0.2
                
                local AvgSmooth = (SmoothX + SmoothY) / 2
                local AlphaX = math.clamp(SmoothX * (Dt * 60), 0, 1)
                local AlphaY = math.clamp(SmoothY * (Dt * 60), 0, 1)
                local Alpha = math.clamp(AvgSmooth * (Dt * 60), 0, 1)
                
                local CurrentLook = CurrentCF.LookVector
                local GoalLook = Goal.LookVector
                
                local NewLookX = CurrentLook.X + (GoalLook.X - CurrentLook.X) * AlphaX
                local NewLookY = CurrentLook.Y + (GoalLook.Y - CurrentLook.Y) * AlphaY
                local NewLookZ = CurrentLook.Z + (GoalLook.Z - CurrentLook.Z) * Alpha
                
                local NewLook = Vector3.new(NewLookX, NewLookY, NewLookZ).Unit
                
                Camera.CFrame = CFrame.lookAt(CurrentCF.Position, CurrentCF.Position + NewLook)
            end
        end
    else
        if not C or not C.StickyAim then ClearCamLock() end
        CamCircle.Visible = false
        CamHighlight.Adornee = nil
    end
end))


------------------------------------------------------------------
-- Skin Changer
------------------------------------------------------------------
local SKIN_CHANGER_PLACE_ID = "138995385694035"

if tostring(game.PlaceId) == SKIN_CHANGER_PLACE_ID then
    local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HandleMap = {
    DB_HANDLE = "DoubleBarrel",
    REV_HANDLE = "Revolver"
}

local function IsBasePart(x)
    return typeof(x) == "Instance" and x:IsA("BasePart")
end

local function EnsurePrimaryPart(model)
    if model and model:IsA("Model") then
        if not IsBasePart(model.PrimaryPart) then
            local first = model:FindFirstChildWhichIsA("BasePart")
            if first then
                model.PrimaryPart = first
            end
        end
        return model.PrimaryPart
    end
end

local function PrepParts(model, isKnife)
    for _, part in ipairs(model:GetDescendants()) do
        if part:IsA("BasePart") then
            part.CanCollide = false
            part.Anchored = false
            part.Massless = true
            part.Transparency = math.clamp(part.Transparency, 0, 1)
        end
        if isKnife and part:IsA("MeshPart") then
            local sa = part:FindFirstChildOfClass("SurfaceAppearance")
            if sa then
                sa:Destroy()
            end
            if part.TextureID == "" then
                local name = part.Name:lower()
                if name:find("box") or name:find("cube") or name:find("part") or name:find("hit") then
                    part.Transparency = 1
                end
            end
        end
    end
end

local function WeldParts(a, b)
    if IsBasePart(a) and IsBasePart(b) then
        local weld = Instance.new("WeldConstraint")
        weld.Part0 = a
        weld.Part1 = b
        weld.Parent = a
        return weld
    end
end

local function GetWrapSkinModel(weaponName, skinName, timeout)
    timeout = timeout or 5
    local wraps = ReplicatedStorage:WaitForChild("Wraps", timeout)
    if not wraps then return nil end
    local folder = wraps:WaitForChild("[" .. weaponName .. "]", timeout)
    if not folder then return nil end
    if not skinName or skinName == "" then return nil end
    return folder:WaitForChild(skinName, timeout)
end

local function ApplyModelOnHolder(holder, skinModel)
    if not holder or not skinModel then return end
    local handle = holder:FindFirstChild("Handle")
    if not IsBasePart(handle) then return end
    local old = holder:FindFirstChild("SkinModel")
    if old then old:Destroy() end
    local clone = skinModel:Clone()
    clone.Name = "SkinModel"
    local primaryPart = EnsurePrimaryPart(clone)
    if not IsBasePart(primaryPart) then return end
    local isKnife = holder.Name:find("Knife") and true or false
    PrepParts(clone, isKnife)
    clone.Parent = holder
    clone:PivotTo(handle.CFrame)
    for _, part in ipairs(clone:GetDescendants()) do
        if part:IsA("BasePart") then
            WeldParts(handle, part)
        end
    end
    handle.Transparency = 1
end

local function ApplyToolSkin(tool)
    local HC = Cfg()
    if not HC or not HC.SkinChanger or not HC.SkinChanger.Enabled then return end
    if not tool or not tool:IsA("Tool") then return end
    local weaponName = tool.Name:match("^%[(.+)%]$")
    if not weaponName then return end
    local skinName = HC.SkinChanger.Skins[weaponName]
    if not skinName or skinName == "" then return end
    local skinModel = GetWrapSkinModel(weaponName, skinName, 5)
    if skinModel then
        ApplyModelOnHolder(tool, skinModel)
    end
end

local function ApplyKnifeSkin(tool)
    local HC = Cfg()
    if not HC or not HC.SkinChanger or not HC.SkinChanger.Enabled then return end
    if not tool or not tool:IsA("Tool") then return end
    if tool.Name ~= "[Knife]" then return end
    local knifeSkin = HC.SkinChanger.Special and HC.SkinChanger.Special["Knife"]
    if not knifeSkin or knifeSkin == "" then return end
    local knives = ReplicatedStorage:FindFirstChild("Knives")
    if not knives then return end
    local skinModel = knives:FindFirstChild(knifeSkin)
    if skinModel then
        ApplyModelOnHolder(tool, skinModel)
    end
end

local function ApplyHandleSkin(character, handleFolderName)
    local HC = Cfg()
    if not HC or not HC.SkinChanger or not HC.SkinChanger.Enabled then return end
    local weaponName = HandleMap[handleFolderName]
    if not weaponName then return end
    local skinName = HC.SkinChanger.Skins[weaponName]
    if not skinName or skinName == "" then return end
    local handleFolder = character:FindFirstChild(handleFolderName)
    if not handleFolder then return end
    local skinModel = GetWrapSkinModel(weaponName, skinName, 5)
    if skinModel then
        ApplyModelOnHolder(handleFolder, skinModel)
    end
end

local function ApplyAllSkins(character)
    local HC = Cfg()
    if not HC or not HC.SkinChanger or not HC.SkinChanger.Enabled then return end
    for _, tool in ipairs(character:GetChildren()) do
        if tool:IsA("Tool") then
            ApplyToolSkin(tool)
            ApplyKnifeSkin(tool)
        end
    end
    for handleFolderName, _ in pairs(HandleMap) do
        ApplyHandleSkin(character, handleFolderName)
    end
end

local function ConnectCharacter(character)
    Track(character.ChildAdded:Connect(function(child)
        if not Alive() then return end
        if child:IsA("Tool") then
            ApplyToolSkin(child)
            ApplyKnifeSkin(child)
        elseif HandleMap[child.Name] then
            task.defer(function()
                ApplyHandleSkin(character, child.Name)
            end)
        end
    end))
    ApplyAllSkins(character)
end

Track(LocalPlayer.CharacterAdded:Connect(function(char)
    if Alive() then
        ConnectCharacter(char)
    end
end))

if LocalPlayer.Character then
    ConnectCharacter(LocalPlayer.Character)
end

end -- End of PlaceId check for skin changer
