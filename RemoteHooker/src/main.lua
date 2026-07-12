local network = require("src/network")
local ui = require("src/ui")

if setthreadidentity then
    pcall(setthreadidentity, 2)
end

ui.init({
    onClose = network.shutdown,
})

local ok, err = network.init(ui.addPacket)
if ok then
    print("[Main] RemoteHooker loaded successfully!")
else
    warn("[Main] RemoteHooker loaded without capture:", err)
end
