local pi, pi2 = math.pi, math.pi*2
local cos, sin = math.cos, math.sin
local floor = math.floor
local sqrt = math.sqrt
local dot = vector.dot
local unit = vector.normalize
local magnitude = vector.magnitude

local PartCache = {}
PartCache.__index = PartCache

export type PartCache = typeof(setmetatable(
	{} :: {
		chached: {BasePart},
		used: {BasePart},
		
		createPart: () -> BasePart
	},
	{} :: typeof(PartCache)
))

function PartCache.PutPart(self: PartCache,
	part: BasePart, storageName: "used" | "chached")
	
	local storage = self[storageName]
	
	local index = #storage + 1
	storage[index] = part
	
	part.Destroying:Once(function()
		table.remove(storage, index)
	end)
end

function PartCache.OpenPart(self: PartCache): BasePart?
	if #self.chached == 0 then return end
	
	local part = table.remove(self.chached)
	self:PutPart(part, "used")
	part.Transparency = 0

	return part
end

function PartCache.ChachePart(self: PartCache): BasePart?
	if #self.used == 0 then return end
	
	local part = table.remove(self.used)
	self:PutPart(part, "chached")
	part.Transparency = 1
	
	return part
end

function PartCache.RemoveParts(self: PartCache, 
	amount: number, handler: ((BasePart) -> ())?)
	
	local startIndex = #self.used - amount
	
	for i = 1, amount do
		local part = self.used[startIndex+i]
		self:ChachePart(part)
		
		if handler then handler(part) end
	end
end

function PartCache.RemoveAllParts(
	self: PartCache, handler: ((BasePart) -> ())?)

	self:RemoveParts(#self.used, handler)
end

function PartCache.GetUsedParts(self: PartCache): {BasePart}
	return self.used
end

function PartCache.GetChachedParts(self: PartCache): {BasePart}
	return self.chached
end

function PartCache.HasChach(self: PartCache): boolean
	return #self.chached > 0
end

function PartCache.CreatePart(self: PartCache): BasePart
	local part = self.createPart()
	self:PutPart(part, "used")
	
	return part
end

function PartCache.GetNewPart(self: PartCache): BasePart
	if not self:HasChach() then
		return self:CreatePart()
	end
	
	return self:OpenPart()
end

function PartCache.GetPart(self: PartCache,
	index: number): BasePart
	
	if index > 0 and #self.used >= index then
		return self.used[index]
	end
	
	if self:HasChach() then
		return self:OpenPart()
	end
	
	return self:CreatePart()
end

PartCache.new = function(
	partCreator: (() -> BasePart)?): PartCache
	
	local self = {
		chached = {}, used = {},
		
		createPart = partCreator or function()
			return Instance.new("Part", workspace) 
		end
	}
	
	return setmetatable(self, PartCache)
end

local function forEachCircle(radius: number, segments: number,
	handler: (number, number, number, number, number) -> ())

	local lastX, lastZ = radius, 0

	for i = 1, segments do
		local theta = i / segments * pi2

		local x = radius * cos(theta)
		local z = radius * sin(theta)

		handler(x, z, lastX, lastZ, i)
		lastX, lastZ = x, z
	end
end

local Controller = {}
Controller.__index = Controller

export type Brush = typeof(setmetatable(
	{} :: {
		color: Color3,
		segmentSize: Vector3,
		startInput: Vector3?,
		currentSegment: Part?,
		lastSegment: Part?,

		segments: PartCache,
		dashes: {number},
	},
	{} :: typeof(Controller)
))

local Figure = setmetatable({}, {__index = PartCache})
Figure.__index = Figure

export type Figure = typeof(setmetatable(
	{} :: typeof(PartCache.new()) & {
		brush: Brush?
	},
	{} :: typeof(Figure)
))

function Figure.FinishFigure(self: Figure)
	for i, p in self:GetUsedParts() do
		self.brush.segments:PutPart(p, "used")
	end
	
	self.brush:FinishCurrentDash()
	table.clear(self.used)
end

Figure.new = function(brush: Brush): Figure
	local self = PartCache.new(function()
		return brush:CreateSegment()
	end)
	self.brush = brush
	
	return setmetatable(self, Figure)
end

local Circle = setmetatable({}, {__index = Figure})
Circle.__index = Circle

export type Circle = typeof(setmetatable(
	{} :: typeof(Figure.new()) & {
		startInput: Vector3?,
		lastSegments: number
	},
	{} :: typeof(Circle)
))

function Circle.UpdateCircle(self: Circle, inputPos: Vector3)
	if not self.startInput then
		self.startInput = inputPos
	end
	
	local brush = self.brush
	local offset = inputPos - self.startInput
	local diameter = magnitude(offset)
	local radius = diameter/2
	local pivot = CFrame.lookAlong(self.startInput + offset/2, offset/diameter)
	local segments = floor(pi2*radius/brush.segmentSize.Z)
	local lastSegment: Part? = nil
	
	local extraSegments = self.lastSegments - segments
	if extraSegments > 0 then self:RemoveParts(extraSegments) end
	
	forEachCircle(radius, segments, function(x, z, lx, lz, i)
		local v1 = pivot * Vector3.new(x, 0, z)
		local cframe, size

		if lastSegment then
			cframe, size = brush:DrawLineRedardingSegment(lastSegment, v1, pivot.UpVector)
		else
			local v0 = pivot * Vector3.new(lx, 0, lz)
			cframe, size = brush:DrawLine(v0, v1, pivot.UpVector)
		end

		if not (cframe and size) then return end

		local segment = self:GetPart(i)
		segment.CFrame, segment.Size = cframe, size
		
		lastSegment = segment
	end)
	
	self.lastSegments = segments
end

Circle.new = function(brush: Brush): Circle
	local self = Figure.new(brush)
	self.lastSegments = 0

	return setmetatable(self, Circle)
end

function Controller.InputDraw(self: Brush, inputPos: Vector3)
	if not self.currentSegment then
		self.currentSegment = self:GetNextSegment(workspace)
	end

	if not self.lastSegment then
		if not self.startInput then
			self.startInput = inputPos
		end

		local cframe, size = self:DrawLine(self.startInput, inputPos)
		if not (cframe and size) then return end

		self.currentSegment.CFrame = cframe
		self.currentSegment.Size = size

		if size.Z >= self.segmentSize.Z then
			self.lastSegment = self.currentSegment
			self.currentSegment = nil
		end

		return
	end

	local cframe, size = self:DrawLineRedardingSegment(
		self.lastSegment, inputPos)

	self.currentSegment.CFrame = cframe
	self.currentSegment.Size = size

	if size.Z >= self.segmentSize.Z then
		self.lastSegment = self.currentSegment
		self.currentSegment = nil
	end
end

function Controller.DrawLine(self: Brush, startPos: Vector3,
	endPos: Vector3, upVec: Vector3?): (CFrame?, Vector3?)
	
	local dir = endPos - startPos
	local mag = dot(dir, dir)

	if mag == 0 then return end; mag = sqrt(mag)

	local lineCframe = CFrame.lookAlong(startPos + dir / 2, dir/mag, upVec or Vector3.yAxis)
	local lineSize = Vector3.new(self.segmentSize.X, self.segmentSize.Y, mag)

	return lineCframe, lineSize
end

function Controller.DrawLineRedardingSegment(self: Brush,
	segment: Part, endPos: Vector3, upVec: Vector3?): (CFrame, Vector3)

	local front = segment.CFrame * Vector3.new(0, 0, -segment.Size.Z/2)
	local dir = endPos - front
	
	local rotation = CFrame.lookAlong(front, dir, upVec or Vector3.yAxis).Rotation
	
	local scalar = dot(segment.CFrame.RightVector, dir)
	scalar = if scalar > 0 then 1 else -1

	local origin = segment.CFrame * Vector3.new(-scalar * self.segmentSize.X/2, 0, -segment.Size.Z/2)

	local length = magnitude(origin - (rotation + endPos) *
		Vector3.new(-scalar * self.segmentSize.X / 2, 0, 0)
	)

	local lineCframe = (rotation + origin) * CFrame.new(scalar * self.segmentSize.X/2, 0, -length / 2)
	local lineSize = Vector3.new(self.segmentSize.X, self.segmentSize.Y, length)

	return lineCframe, lineSize
end

function Controller.CreateCircle(self: Brush): Circle
	return Circle.new(self)
end

function Controller.FinishCurrentDash(self: Brush)
	local index = #self.dashes+1
	local dash = #self.segments:GetUsedParts()
	local lastDash = self.dashes[index-1]
	
	if lastDash and lastDash == dash then return end
	
	self.dashes[index] = dash
	self.lastSegment = nil
	self.currentSegment = nil
	self.startInput = nil
end

function Controller.CreateSegment(self: Brush): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.Color = self.color
	part.CanCollide = false
	part.CastShadow = false
	part.Parent = workspace
	
	return part
end

function Controller.GetNextSegment(self: Brush): Part
	return self.segments:GetNewPart()
end

function Controller.Undo(self: Brush)
	self:RemoveCurrentDash()
end

function Controller.GetIndexOfSegment(self: Brush, segment: Part): number?
	return table.find(self.segments:GetUsedParts(), segment)
end

function Controller.GetNextSegmentFromIndex(self: Brush, index: number): Part?
	return self.segments:GetUsedParts()[index]
end

function Controller.RemoveCurrentDash(self: Brush)
	local index = #self.dashes
	
	local dashMin = self.dashes[index-1] or 0
	local dashMax = self.dashes[index]
	
	if not (dashMin and dashMax) then return end
	self.segments:RemoveParts(dashMax - dashMin)

	self.dashes[index] = nil
end

function Controller.SetColor(self: Brush, color: Color3?)
	self.color = color or Color3.new(1, 1, 1)
end

function Controller.SetWidth(self: Brush, value: number)
	value = math.clamp(value, 0, 1)
	self.segmentSize *= Vector3.new(math.lerp(0.5, 1, value)/self.segmentSize.X,1,1)
end

function Controller.SetHeight(self: Brush, value: number)
	value = math.clamp(value, 0, 1)
	self.segmentSize *= Vector3.new(1,math.lerp(0.5, 1, value)/self.segmentSize.Y,1)
end

function Controller.SetResolution(self: Brush, value: number)
	value = math.clamp(value, 0, 1)
	self.segmentSize *= Vector3.new(1,1,math.lerp(15, 2, value)/self.segmentSize.Z)
end

Controller.new = function(): Brush
	local self = {
		color = Color3.new(1, 1, 1),
		segmentSize = Vector3.new(0.75, 0.5, 2),

		dashes = {},
	}
	
	self.segments = PartCache.new(function()
		return self:CreateSegment()
	end)
	
	return setmetatable(self, Controller)
end

return Controller
