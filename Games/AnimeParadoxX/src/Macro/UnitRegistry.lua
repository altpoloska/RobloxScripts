local UnitRegistry = {}
UnitRegistry.__index = UnitRegistry

function UnitRegistry.new()
    return setmetatable({
        _counts = {},
        _byEntity = {},
        _byLabel = {},
        _pending = {},
    }, UnitRegistry)
end

function UnitRegistry:Reserve(unitName)
    assert(type(unitName) == "string" and unitName ~= "", "Invalid unit name")
    local number = (self._counts[unitName] or 0) + 1
    self._counts[unitName] = number
    local label = string.format("%s - %d", unitName, number)
    self._pending[label] = true
    return label
end

function UnitRegistry:Bind(label, entity)
    if type(label) ~= "string" or label == "" then return false, "Invalid unit label" end
    if typeof(entity) ~= "Instance" then return false, "Invalid unit entity" end

    local oldLabel = self._byEntity[entity]
    if oldLabel and oldLabel ~= label then return false, "Entity is already bound to " .. oldLabel end
    local oldEntity = self._byLabel[label]
    if oldEntity and oldEntity ~= entity then return false, "Label is already bound to another entity" end

    self._pending[label] = nil
    self._byEntity[entity] = label
    self._byLabel[label] = entity
    return true
end

function UnitRegistry:Resolve(entity) return self._byEntity[entity] end

function UnitRegistry:ResolveLabel(label)
    local entity = self._byLabel[label]
    if entity and entity.Parent then return entity end
    return nil
end

function UnitRegistry:WaitForLabel(entity, timeout)
    local deadline = os.clock() + (timeout or 2)
    repeat
        local label = self:Resolve(entity)
        if label then return label end
        task.wait()
    until os.clock() >= deadline
    return nil
end

function UnitRegistry:ReleaseEntity(entity)
    local label = self._byEntity[entity]
    if not label then return nil end
    self._byEntity[entity] = nil
    self._byLabel[label] = nil
    self._pending[label] = nil
    return label
end

function UnitRegistry:Reset()
    table.clear(self._counts)
    table.clear(self._byEntity)
    table.clear(self._byLabel)
    table.clear(self._pending)
end

return UnitRegistry
