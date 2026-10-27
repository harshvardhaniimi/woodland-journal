-- Sleep and wake from inside a book, mirroring KOReader's suspend sequence:
-- screensaver shown and Suspend broadcast; then closed and Resume broadcast.
local UIManager = require("ui/uimanager")
local Event = require("ui/event")
local Device = require("device")
local logger = require("logger")
local function reader() local R = package.loaded["apps/reader/readerui"]; return R and R.instance end
local function suspend()
    local Screensaver = require("ui/screensaver")
    Screensaver:setup()
    Screensaver:show()
    Device.screen_saver_mode = true
    UIManager:broadcastEvent(Event:new("Suspend"))
end
local function resume()
    local Screensaver = require("ui/screensaver")
    Screensaver:close()
    Device.screen_saver_mode = false
    UIManager:broadcastEvent(Event:new("Resume"))
end
local function state(label)
    local r = reader()
    local top = UIManager._window_stack[#UIManager._window_stack].widget
    logger.info("woodland-check", label, "reader open:", r ~= nil, "top:", top.name or top.id or tostring(top._refreshImmediate ~= nil and "simpleui screen" or top))
end
-- Open the lowest book on the home page (Also reading, or the current book
-- when nothing else is in progress).
local function open_book()
    local w = rawget(_G, "WOODLAND_LAST")
    local best
    for _, t in ipairs(w and w.scene.targets or {}) do
        if t.file and (not best or t.y > best.y) then best = t end
    end
    if best then WOODLAND_TAP(best.file) else logger.warn("woodland-check", "no book on the home page") end
end
return {
    { lua=open_book, wait=6 },
    { lua=function() state("before sleep") end, wait=0.2 },
    { lua=suspend, wait=4 },
    { shot="z01-asleep", wait=0.3 },
    { lua=function() state("asleep") end, wait=65 }, -- across a minute boundary
    { shot="z02-asleep-after-minute", wait=0.3 },
    { lua=resume, wait=6 },
    { shot="z03-woken", wait=0.3 },
    { lua=function() state("woken") end, wait=0.3 },
    { lua=function()
        local DocSettings = require("docsettings")
        local f = rawget(_G, "WOODLAND_LAST") and WOODLAND_LAST.scene and nil
        local path = G_reader_settings:readSetting("lastfile")
        logger.info("woodland-check", "lastfile", path and path:match("[^/]+$"),
            "saved percent", path and DocSettings:open(path):readSetting("percent_finished"))
    end, wait=0.3 },
}
