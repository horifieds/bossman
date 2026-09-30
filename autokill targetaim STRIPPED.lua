--[[
    AutoKill TargetAim - STRIPPED VERSION
    Only the raw TargetAim function + required hooks
]]

local ENV = getgenv()

-- Services
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer
local Mouse = LocalPlayer:GetMouse()
local Camera = workspace.CurrentCamera

-- Aim cache
ENV.HC_Aim = ENV.HC_Aim or { Part = nil, Pos = nil }
ENV.HC_Mouse = Mouse

-- AutoKill target (set by your AutoKill system)
-- _G.autokill = { active = bool, target = Player }

local function SetSilentAimCache(Part, Pos)
    if ENV.HC_Aim then
        ENV.HC_Aim.Part = Part
        ENV.HC_Aim.Pos = Pos
    end
end

-- Get predicted position
local function PredictPosition(Part, Prediction)
    if not Part then return nil end
    local Vel = Part.AssemblyLinearVelocity or Part.Velocity or Vector3.zero
    local P = tonumber(Prediction) or 0
    if P == 0 then return Part.Position end
    return Part.Position + Vel * P
end

-- Get hit part from character
local function GetHitPart(Character, HitPartName)
    if not Character then return nil end
    return Character:FindFirstChild(HitPartName)
        or Character:FindFirstChild("Head")
        or Character:FindFirstChild("HumanoidRootPart")
end

-- Rewrite shoot packet to aim at AutoKill target
local function RewriteShootArgs(Args)
    local AimStore = ENV.HC_Aim
    if not AimStore or not AimStore.Pos then return false end
    if AimStore.Part and not AimStore.Part.Parent then return false end

    local EventName = Args[1]
    if typeof(EventName) ~= "string" then return false end
    local Lower = string.lower(EventName)

    local Aim = AimStore.Pos

    -- Shoot packet only
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

    return false
end

ENV.HC_RewriteShoot = RewriteShootArgs

-- Mouse.Hit spoofing resolver
ENV.HC_ResolveMouseIndex = function(Key)
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

-- Install hooks (only once)
if not ENV.HC_HooksInstalled_AutoKill then
    ENV.HC_HooksInstalled_AutoKill = true

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
                        return OldNamecall(Self, unpack(Args, 1, Count))
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
end

-- Main TargetAim loop: updates HC_Aim cache to AutoKill target's head
RunService.RenderStepped:Connect(function()
    -- Check if AutoKill is active and has a target
    if not _G.autokill or not _G.autokill.active or not _G.autokill.target then
        SetSilentAimCache(nil, nil)
        return
    end

    local target = _G.autokill.target
    if not target or not target.Character then
        SetSilentAimCache(nil, nil)
        return
    end

    -- Always aim at HEAD with 0 prediction
    local head = GetHitPart(target.Character, "Head")
    if head then
        local predictedPos = PredictPosition(head, 0)
        SetSilentAimCache(head, predictedPos)
    else
        SetSilentAimCache(nil, nil)
    end
end)

print("[AutoKill TargetAim] Loaded - stripped version")
