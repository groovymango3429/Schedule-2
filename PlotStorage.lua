local playersRemaining = Instance.new("NumberValue")
local PlotManager = require(script.Parent.PlotManager)
local PlotSpawnPool = require(script.Parent.PlotSpawnPool)
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PlotStore = DataStoreService:GetDataStore("PlotStore")
local placeableObjects = ReplicatedStorage.PlaceableObjects

type ObjectInfo = {
	Name: string,
	Cf: {number},
	StorageId: string?, -- <-- Added, optional for non-storage objects
}

local function serializePlot(plot: Model)
	local data = {}
	for _, object in plot.Objects:GetChildren() do
		local objectCF = plot:GetPivot():ToObjectSpace(object:GetPivot())
		local info: ObjectInfo = {
			Name = object.Name,
			Cf = table.pack(objectCF:GetComponents())
		}
		local storageId = object:GetAttribute("StorageId")
		if storageId then
			info.StorageId = storageId
		end
		table.insert(data, info)
	end
	return data
end

local PlotStorage = {}

function PlotStorage.Load(player: Player) 
	local success, data: {ObjectInfo} = pcall(function()
		return PlotStore:GetAsync(player.UserId)
	end)

	if not success then 
		warn(data)
		playersRemaining.Value += 1
		return 
	end
	if not Players:GetPlayerByUserId(player.UserId) then 
		return
	end

	local plot = PlotManager.SpawnPlot(player)
	if data then 
		for _, objectInfo in data do 
			local object = placeableObjects[objectInfo.Name]:Clone()
			local relativeCf = CFrame.new(table.unpack(objectInfo.Cf))
			object:PivotTo(plot:GetPivot():ToWorldSpace(relativeCf))
			if objectInfo.StorageId then
				object:SetAttribute("StorageId", objectInfo.StorageId)
			end
			object.Parent = plot.Objects 
		end
	end

	playersRemaining.Value += 1
end

function PlotStorage.Save(player: Player)
	local plot = PlotManager.GetPlot(player)
	if not plot or not plot:IsDescendantOf(workspace) then 
		playersRemaining.Value -= 1
		return 
	end

	local data = serializePlot(plot)
	plot:Destroy()
	PlotSpawnPool.Return(player)

	local success, errMsg = pcall(function()
		PlotStore:SetAsync(player.UserId, data)
	end)

	if not success then 
		warn(errMsg)
	end

	playersRemaining.Value -= 1
end

function PlotStorage.WaitForSave()
	while playersRemaining.Value > 0 do
		playersRemaining.Changed:Wait()
	end
end

return PlotStorage