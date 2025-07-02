--!nolint
local Raritys = {}

-- Stored rarities in a specific order. This is crucial for the weighted chance algorithm.
local ORDERED_RARITIES = {
	{Name = "Common",    Chance = 60},
	{Name = "Uncommon",  Chance = 25},
	{Name = "Rare",      Chance = 9},
	{Name = "Epic",      Chance = 3.5},
	{Name = "Legendary", Chance = 1.2},
	{Name = "Mythical",  Chance = 0.5},
	{Name = "Divine",    Chance = 0.15},
	{Name = "Unique",    Chance = 0.05}
}

function Raritys.GetRandomRarity(availableRarities)
	local totalWeight = 0
	local validRarities = {}

	-- Step 1: Filter the master list to include only available rarities and calculate their total combined chance.
	for _, rarityData in ipairs(ORDERED_RARITIES) do
		if availableRarities[rarityData.Name] then
			table.insert(validRarities, rarityData)
			totalWeight += rarityData.Chance
		end
	end

	if totalWeight == 0 then return nil end

	-- Step 2: Pick a random number within the range of the total available weight.
	local randomValue = math.random() * totalWeight

	-- Step 3: Iterate through the valid rarities, subtracting their chance until the random value is less than the current rarity's chance.
	for _, rarityData in ipairs(validRarities) do
		if randomValue < rarityData.Chance then
			return rarityData.Name
		else
			randomValue -= rarityData.Chance
		end
	end

	-- Fallback in the rare case of floating point inaccuracies.
	return validRarities[#validRarities] and validRarities[#validRarities].Name
end

return Raritys