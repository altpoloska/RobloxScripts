local settings = {
    ignoredPathPatterns = {},
    excludedNames = {},
    excludedPaths = {},
    blockedPaths = {},
    maxPackets = 500,
    maxPendingPackets = 250,
    captureCallingScript = true,
    -- Stack collection is expensive; enable only while diagnosing a call.
    captureTraceback = false,
}

local excludedPathCount = 0
local blockedPathCount = 0

local function safePath(remote)
    local ok, path = pcall(function() return remote:GetFullName() end)
    return ok and path or tostring(remote)
end

function settings.getRemoteState(remote)
    local name = remote.Name
    if settings.excludedNames[name] then
        return true, false, nil
    end

    -- Avoid GetFullName entirely while no path-based rule is configured.
    if excludedPathCount == 0
        and blockedPathCount == 0
        and #settings.ignoredPathPatterns == 0
    then
        return false, false, nil
    end

    local path = safePath(remote)
    local ignored = settings.excludedPaths[path] == true

    if not ignored then
        for _, pattern in ipairs(settings.ignoredPathPatterns) do
            local ok, matched = pcall(string.match, path, pattern)
            if ok and matched then
                ignored = true
                break
            end
        end
    end

    return ignored, settings.blockedPaths[path] == true, path
end

function settings.shouldIgnore(remote)
    local ignored = settings.getRemoteState(remote)
    return ignored
end

function settings.isBlocked(remote)
    local _, blocked = settings.getRemoteState(remote)
    return blocked
end

function settings.excludeName(name)
    settings.excludedNames[name] = true
end

function settings.excludePath(path)
    if not settings.excludedPaths[path] then
        excludedPathCount = excludedPathCount + 1
        settings.excludedPaths[path] = true
    end
end

function settings.setBlocked(path, value)
    local wasBlocked = settings.blockedPaths[path] == true
    local shouldBlock = value == true
    if wasBlocked ~= shouldBlock then
        blockedPathCount = blockedPathCount + (shouldBlock and 1 or -1)
        settings.blockedPaths[path] = shouldBlock and true or nil
    end
end

function settings.isPathBlocked(path) return settings.blockedPaths[path] == true end
function settings.resetExclusions()
    table.clear(settings.excludedNames)
    table.clear(settings.excludedPaths)
    excludedPathCount = 0
end
function settings.resetBlocks()
    table.clear(settings.blockedPaths)
    blockedPathCount = 0
end

return settings
