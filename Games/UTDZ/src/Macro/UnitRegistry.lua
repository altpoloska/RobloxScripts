local UnitRegistry = {}
UnitRegistry.__index = UnitRegistry

function UnitRegistry.new()
    return setmetatable({
        _counts = {},
        _byUuid = {},
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

function UnitRegistry:Bind(label, uuid)
    if type(label) ~= "string" or label == "" then
        return false, "Invalid unit label"
    end
    if type(uuid) ~= "string" or uuid == "" then
        return false, "Invalid unit UUID"
    end

    local oldLabel = self._byUuid[uuid]
    if oldLabel and oldLabel ~= label then
        return false, "UUID is already bound to " .. oldLabel
    end

    local oldUuid = self._byLabel[label]
    if oldUuid and oldUuid ~= uuid then
        return false, "Label is already bound to another UUID"
    end

    self._pending[label] = nil
    self._byUuid[uuid] = label
    self._byLabel[label] = uuid
    return true
end

function UnitRegistry:Resolve(uuid)
    return self._byUuid[uuid]
end

function UnitRegistry:ResolveLabel(label)
    return self._byLabel[label]
end

function UnitRegistry:WaitForLabel(uuid, timeout)
    local deadline = os.clock() + (timeout or 2)
    repeat
        local label = self:Resolve(uuid)
        if label then return label end
        task.wait()
    until os.clock() >= deadline
    return nil
end

function UnitRegistry:Reset()
    table.clear(self._counts)
    table.clear(self._byUuid)
    table.clear(self._byLabel)
    table.clear(self._pending)
end

return UnitRegistry
