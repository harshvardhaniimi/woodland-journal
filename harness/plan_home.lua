-- The home page through real taps: audit it, open the lowest book on the page
-- (Also reading), return home through the reader menu, open the library.
local UIManager = require("ui/uimanager")
local logger = require("logger")
local function reader() local R = package.loaded["apps/reader/readerui"]; return R and R.instance end
local function close_reader()
    local r = reader()
    local items = r and r.menu and r.menu.menu_items
    if not (items and items.filemanager) and r and r.menu and r.menu.setUpdateItemTable then
        pcall(r.menu.setUpdateItemTable, r.menu)
        items = r.menu.menu_items
    end
    if items and items.filemanager then items.filemanager.callback()
    else UIManager:sendEvent(require("ui/event"):new("Home")) end
end
local function tap_lowest_book()
    local w = rawget(_G, "WOODLAND_LAST")
    local best
    for _, t in ipairs(w and w.scene.targets or {}) do
        if t.file and (not best or t.y > best.y) then best = t end
    end
    if not best then logger.info("woodland-check", "no book on the home page"); return end
    WOODLAND_TAP(best.file)
end
return {
    { lua=function() WOODLAND_LOG_STATE("start") end, wait=0.3 },
    { shot="h01-home", wait=0.5 },
    { lua=function() WOODLAND_AUDIT("home") end, wait=0.3 },
    { lua=tap_lowest_book, wait=6 },
    { lua=function()
        local r = reader()
        logger.info("woodland-check", "reader open:", r ~= nil, r and r.document and r.document.file:match("[^/]+$"))
    end, wait=0.3 },
    { shot="h02-book-open", wait=0.3 },
    { lua=close_reader, wait=5 },
    { shot="h03-home-after-close", wait=0.3 },
    { lua=function() WOODLAND_AUDIT("home after close") end, wait=0.3 },
    { lua=function() WOODLAND_TAP("library") end, wait=4 },
    { shot="h04-library", wait=0.3 },
}
