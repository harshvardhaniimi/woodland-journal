-- Goodreads off: the home page shows "Goodreads not available", tapping it
-- explains how to turn it on, and no Goodreads page is reachable.
local UIManager = require("ui/uimanager")
local logger = require("logger")
return {
    { lua=function() WOODLAND_LOG_STATE("goodreads off") end, wait=0.3 },
    { shot="n01-home", wait=0.5 },
    { lua=function() WOODLAND_AUDIT("home without goodreads") end, wait=0.3 },
    { lua=function() WOODLAND_TAP("goodreads_off") end, wait=2 },
    { shot="n02-explanation", wait=0.3 },
    { lua=function() WOODLAND_CLOSE_TOP() end, wait=1.5 },
    { swipe="west", wait=3 },
    { lua=function()
        local w = rawget(_G, "WOODLAND_LAST")
        local home
        for i = #UIManager._window_stack, 1, -1 do
            local widget = UIManager._window_stack[i].widget
            if widget._refreshImmediate then home = widget; break end
        end
        logger.info("woodland-check", "after swipe: page", home and home._current_page, "of", home and home._total_pages,
            "last woodland scene", w and (w.scene.height .. " high, " .. #w.scene.targets .. " targets"))
    end, wait=0.3 },
    { shot="n03-after-swipe", wait=0.3 },
}
