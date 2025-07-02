local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local RunService = game:GetService("RunService")

local MainFolder = ReplicatedStorage:WaitForChild("MainFolder")
local ModulesFolder = MainFolder:WaitForChild("Modules")
local NPCManager = require(ModulesFolder:WaitForChild("NPCManager"))
local ProfileStore = require(ModulesFolder:WaitForChild("ProfileStore"))

local ProfileTemplate = {
	Cash = 1000,
	OwnedNPCs = {},
}

local GameProfileStore = ProfileStore.New(
	"PlayerData_V1",
	ProfileTemplate
)

local Profiles = {}

local CollectionService = {}
local collectionData = {}

function CollectionService:FormatNumber(amount)
	local rounded = tostring(math.floor(amount))
	local formatted = rounded
	local k = 0
	while true do
		formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", "%1,%2")
		if k == 0 then
			break
		end
	end
	return formatted
end

function CollectionService:Start(player, standModel, npcRig, characterImportantFolder, initialAmount)
	initialAmount = initialAmount or 0
	local collectPart = standModel:FindFirstChild("Collect")
	if not (collectPart and collectPart:FindFirstChild("Text") and collectPart.Text:FindFirstChild("TextFrame")) then return end

	local billboardUI = collectPart.Text.TextFrame
	local amountLabel = billboardUI:WaitForChild("Amount")
	local perSec = tonumber(characterImportantFolder.PerSec.Value) or 0
	if perSec <= 0 then return end

	billboardUI.Enabled = true
	amountLabel.Text = self:FormatNumber(initialAmount) .. "$"

	local standId = standModel:GetFullName()
	collectionData[standId] = {
		amount = initialAmount,
		perSec = perSec,
		lastUpdate = os.time(),
		cap = tonumber(characterImportantFolder.OfflineCap.Value) or math.huge,
		amountLabel = amountLabel,
		collectPart = collectPart,
		touchConnection = nil
	}

	collectionData[standId].touchConnection = collectPart.Touched:Connect(function(hit)
		local p = Players:GetPlayerFromCharacter(hit.Parent)
		if p and p.UserId == player.UserId then
			local data = collectionData[standId]
			local profile = Profiles[p]
			if data and data.amount > 0 and profile then
				profile.Data.Cash += data.amount
				p.leaderstats.Cash.Value = profile.Data.Cash
				data.amount = 0
				data.lastUpdate = os.time()
				data.amountLabel.Text = self:FormatNumber(data.amount) .. "$"
			end
		end
	end)
end

function CollectionService:Stop(standModel)
	local standId = standModel:GetFullName()
	local data = collectionData[standId]
	if data then
		if data.touchConnection and data.touchConnection.Connected then
			data.touchConnection:Disconnect()
		end
		local collectPart = standModel:FindFirstChild("Collect")
		if collectPart and collectPart:FindFirstChild("Text") and collectPart.Text:FindFirstChild("TextFrame") then
			collectPart.Text.TextFrame.Enabled = false
		end
		collectionData[standId] = nil
	end
end

local function getBaseOwnedByPlayer(player)
	local basesFolder = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("Bases")
	if not basesFolder then return nil end

	for _, base in ipairs(basesFolder:GetChildren()) do
		local important = base:FindFirstChild("Important")
		if important and important:FindFirstChild("Owner") and important.Owner.Value == player.Name then
			return base
		end
	end
	return nil
end

local function onPlayerAdded(player)
	local profile = GameProfileStore:StartSessionAsync(`{player.UserId}`, {
		Cancel = function()
			return player.Parent ~= Players
		end,
	})

	if profile then
		profile:AddUserId(player.UserId)
		profile:Reconcile()

		profile.OnSessionEnd:Connect(function()
			Profiles[player] = nil
			player:Kick("Your data profile was loaded from another session. Please rejoin.")
		end)

		if player:IsDescendantOf(Players) then
			Profiles[player] = profile

			local leaderstats = Instance.new("Folder", player)
			leaderstats.Name = "leaderstats"
			local cash = Instance.new("IntValue", leaderstats)
			cash.Name = "Cash"
			cash.Value = profile.Data.Cash

			cash.Changed:Connect(function(newCashValue)
				if Profiles[player] then
					Profiles[player].Data.Cash = newCashValue
				end
			end)

			local playerBase
			local waitTime = 0
			repeat
				playerBase = getBaseOwnedByPlayer(player)
				if not playerBase then
					task.wait(1)
					waitTime = waitTime + 1
				end
			until playerBase or waitTime >= 20

			if not playerBase then
				warn("Could not find base for player " .. player.Name .. " after 20 seconds. NPCs will not be loaded.")
			else
				if profile.Data.OwnedNPCs then
					for standNum, npcData in pairs(profile.Data.OwnedNPCs) do
						local standModel = playerBase.Platforms:FindFirstChild("Stand" .. standNum)
						if standModel and npcData.NPCType then
							local timeOfflineInSeconds = os.time() - (npcData.LastUpdate or os.time())
							local offlineEarnings = math.min(
								timeOfflineInSeconds * (npcData.PerSec or 0),
								npcData.OfflineCap or math.huge
							)
							local initialAmount = (npcData.CollectedAmount or 0) + offlineEarnings

							task.spawn(function()
								NPCManager.setNPCOnStand(player, standModel, npcData.NPCType, initialAmount)
							end)
						end
					end
				end
			end

			player.CharacterAdded:Connect(function(character)
				local activeNpcs = workspace.WalkingOn.ActiveNPCs:GetChildren()
				for i = 1, #activeNpcs do
					local npcFolder = activeNpcs[i]
					if npcFolder and npcFolder:IsA("Folder") then
						NPCManager.addPurchaseGuiToWalkingNPC(player, npcFolder)
					end
				end
			end)
		else
			profile:EndSession()
		end
	else
		player:Kick("Could not load your data. Please try rejoining.")
	end
end

local function onPlayerRemoving(player)
	local profile = Profiles[player]
	if profile then
		local playerBase = getBaseOwnedByPlayer(player)
		if playerBase then
			local savedNPCs = {}
			for _, standModel in ipairs(playerBase.Platforms:GetChildren()) do
				if standModel:IsA("Model") and standModel:FindFirstChild("Important") then
					local important = standModel.Important
					if important.Equipped.Value and important.NPCName.Value ~= "" then
						local standId = standModel:GetFullName()
						local standData = collectionData[standId]
						local standNum = string.match(standModel.Name, "%d+")

						if standData and standNum then
							local npcType = important.NPCName.Value
							local rigFolder = ReplicatedStorage.MainFolder.Rigs:FindFirstChild(npcType)
							local offlineCap = rigFolder and rigFolder.Important:FindFirstChild("OfflineCap") and rigFolder.Important.OfflineCap.Value or math.huge

							savedNPCs[standNum] = {
								NPCType = npcType,
								CollectedAmount = standData.amount,
								PerSec = standData.perSec,
								LastUpdate = os.time(),
								OfflineCap = offlineCap
							}
						end
					end
				end
			end
			profile.Data.OwnedNPCs = savedNPCs
		end

		profile:EndSession()
		Profiles[player] = nil
	end
end

for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, player)
end
Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)

game:BindToClose(function()
	if RunService:IsStudio() then
		task.wait(2)
	end
	for _, player in ipairs(Players:GetPlayers()) do
		onPlayerRemoving(player)
	end
end)

local npcManagerDependencies = {
	startCollectionForStand = function(...) CollectionService:Start(...) end,
	cleanupCollectionForStand = function(...) CollectionService:Stop(...) end,
	getBaseOwnedByPlayer = getBaseOwnedByPlayer,
	formatNumber = function(...) return CollectionService:FormatNumber(...) end,
	getProfileCache = function() return Profiles end,
}
NPCManager.init(npcManagerDependencies)

task.spawn(function()
	while true do
		local deltaTime = task.wait(1)

		for standId, data in pairs(collectionData) do
			if not data.amountLabel.Parent then
				CollectionService:Stop(data.collectPart.Parent)
				continue
			end

			data.amount = data.amount + (data.perSec * deltaTime)

			data.amountLabel.Text = CollectionService:FormatNumber(data.amount) .. "$"
		end
	end
end)