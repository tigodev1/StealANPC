local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local player = Players.LocalPlayer

local remotes = ReplicatedStorage:WaitForChild("MainFolder", 3):WaitForChild("Remotes", 3)
local baseAssigned = remotes:WaitForChild("BaseAssigned", 3)

local assignedBaseName = nil
local MAX_RETRIES = 5
local RETRY_DELAY = 1 

local function updateBaseVisuals()
	local map = workspace:WaitForChild("Map", 3)
	local basesFolder = map and map:WaitForChild("Bases", 3)

	local retries = 0
	while not basesFolder and retries < MAX_RETRIES do
		wait(RETRY_DELAY)
		map = workspace:WaitForChild("Map", 3)
		basesFolder = map and map:WaitForChild("Bases", 3)
		retries = retries + 1
	end

	if not basesFolder then
		return
	end
	if not assignedBaseName then
		return
	end

	for _, base in ipairs(basesFolder:GetChildren()) do
		if base:IsA("Folder") and base.Name:match("^Base%d+") then
			local isOwner = (base.Name == assignedBaseName)
			local barriers = base:WaitForChild("Barriers", 3)
			local main = barriers and barriers:WaitForChild("Main", 3)
			local mainBarrier = main and main:WaitForChild("MainBarrier", 3)
			if mainBarrier then
				mainBarrier.CanCollide = not isOwner 
			else
			end
			local signs = base:WaitForChild("Signs", 3)
			local signsPart = signs and signs:WaitForChild("SignsPart", 3)
			local baseSign = signsPart and signsPart:WaitForChild("BaseSign", 3)
			local billboardGui = baseSign and baseSign:WaitForChild("BillboardGui", 3)
			local textLabel = billboardGui and billboardGui:WaitForChild("TextLabel", 3)
			if textLabel then
				textLabel.Visible = isOwner
			else
			end
		end
	end
end

baseAssigned.OnClientEvent:Connect(function(baseName)
	assignedBaseName = baseName
	updateBaseVisuals()
end)

local checkDuration = 30
local checkInterval = 5
local elapsed = 0

RunService.Heartbeat:Connect(function()
	if assignedBaseName and elapsed < checkDuration then
		updateBaseVisuals()
		elapsed = elapsed + checkInterval
	end
end)

updateBaseVisuals()