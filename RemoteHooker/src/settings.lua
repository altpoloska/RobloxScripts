local settings = {}

settings.ignoredPathPatterns = {}

settings.excludedNames = {}
settings.excludedPaths = {}

function settings.shouldIgnore(remote)
    local name = remote.Name
    local path = remote:GetFullName()
    if settings.excludedNames[name] then return true end
    if settings.excludedPaths[path] then return true end
    for _, pattern in ipairs(settings.ignoredPathPatterns) do
        if path:match(pattern) then return true end
    end
    return false
end

function settings.excludeName(name)
    settings.excludedNames[name] = true
end

function settings.excludePath(path)
    settings.excludedPaths[path] = true
end

function settings.resetExclusions()
    settings.excludedNames = {}
    settings.excludedPaths = {}
end

return settings
