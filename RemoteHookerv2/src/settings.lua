local settings = {
    ignoredPathPatterns = {},
    excludedNames = {},
    excludedPaths = {},
    blockedPaths = {},
    maxPackets = 500,
}

local function safePath(remote)
    local ok, path = pcall(function() return remote:GetFullName() end)
    return ok and path or tostring(remote)
end

function settings.shouldIgnore(remote)
    local name = remote.Name
    local path = safePath(remote)
    if settings.excludedNames[name] or settings.excludedPaths[path] then return true end
    for _, pattern in ipairs(settings.ignoredPathPatterns) do
        local ok, matched = pcall(string.match, path, pattern)
        if ok and matched then return true end
    end
    return false
end

function settings.isBlocked(remote)
    return settings.blockedPaths[safePath(remote)] == true
end

function settings.excludeName(name) settings.excludedNames[name] = true end
function settings.excludePath(path) settings.excludedPaths[path] = true end
function settings.setBlocked(path, value) settings.blockedPaths[path] = value and true or nil end
function settings.isPathBlocked(path) return settings.blockedPaths[path] == true end
function settings.resetExclusions()
    table.clear(settings.excludedNames)
    table.clear(settings.excludedPaths)
end
function settings.resetBlocks() table.clear(settings.blockedPaths) end

return settings
