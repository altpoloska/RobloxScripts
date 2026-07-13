-- Сопоставляет живые UUID юнитов (меняются каждый забег) с портативным
-- идентификатором вида "Имя - N" (N -- какой по счёту юнит этого имени).
local UnitRegistry = {}
UnitRegistry.__index = UnitRegistry

function UnitRegistry.new()
	local self = setmetatable({}, UnitRegistry)
	self._counts = {} -- [unitName] = сколько поставлено
	self._byUuid = {} -- [uuid]  = "Имя - N"
	self._byLabel = {} -- ["Имя - N"] = uuid
	return self
end

-- Регистрирует поставленный юнит, возвращает его label "Имя - N".
function UnitRegistry:Register(unitName, uuid)
	local n = (self._counts[unitName] or 0) + 1
	self._counts[unitName] = n
	local label = string.format("%s - %d", unitName, n)
	self._byLabel[label] = uuid
	if uuid ~= nil then
		self._byUuid[uuid] = label
	end
	return label, n
end

-- uuid -> "Имя - N" (при записи)
function UnitRegistry:Resolve(uuid)
	return self._byUuid[uuid]
end

-- "Имя - N" -> актуальный uuid (при воспроизведении)
function UnitRegistry:ResolveLabel(label)
	return self._byLabel[label]
end

function UnitRegistry:Reset()
	self._counts = {}
	self._byUuid = {}
	self._byLabel = {}
end

return UnitRegistry
