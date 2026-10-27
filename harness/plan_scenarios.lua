-- Renders and audits every fixture scenario, then every daily quote.
local UIManager = require("ui/uimanager")
local function screen()
    for i = #UIManager._window_stack, 1, -1 do
        local w = UIManager._window_stack[i].widget
        if w._refreshImmediate then return w end
    end
end
local function show(name)
    return function()
        rawset(_G, "WOODLAND_SCENARIO", name)
        local s = screen()
        if s then s:_refreshImmediate(false) end
    end
end
local steps = { { shot="s00-real", wait=0.5 }, { lua=function() WOODLAND_AUDIT("real") end, wait=0.5 } }
for i, name in ipairs{ "employees", "long", "empty_week", "no_stats", "no_covers", "fresh", "finished", "with_time",
        "finished_alone", "finished_long" } do
    steps[#steps+1] = { lua=show(name), wait=2.5 }
    steps[#steps+1] = { shot=string.format("s%02d-%s", i, name), wait=0.5 }
    steps[#steps+1] = { lua=function() WOODLAND_AUDIT(name) end, wait=0.3 }
end
-- Thirteen consecutive days cover the whole quote rotation.
local Quotes
for day = 0, 12 do
    steps[#steps+1] = { lua=function()
        Quotes = Quotes or require("woodland_journal/quotes")
        rawset(_G, "WOODLAND_SCENARIO", "quote_day")
        rawset(_G, "WOODLAND_QUOTE_DAY", day)
        local s = screen()
        if s then s:_refreshImmediate(false) end
    end, wait=2 }
    steps[#steps+1] = { lua=function() WOODLAND_AUDIT("quote+" .. day) end, wait=0.2 }
    if day % 4 == 0 then steps[#steps+1] = { shot=string.format("q%02d", day), wait=0.3 } end
end
return steps
