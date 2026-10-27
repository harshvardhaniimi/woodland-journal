-- Widget.colourRefresh without KOReader: stub the modules the widget requires
-- at load time, then exercise the refresh decision.
-- Usage: luajit test_colour_refresh.lua <repo-dir>
local stub = setmetatable({}, { __index = function() return function() end end })
package.preload["device"] = function() return { screen = { scaleBySize = function(_, n) return n end } } end
for _, name in ipairs{ "ffi/blitbuffer", "ui/font", "ui/geometry", "ui/gesturerange", "ui/widget/textwidget",
        "ui/widget/textboxwidget", "logger" } do
    package.preload[name] = function() return stub end
end
package.preload["gettext"] = function() return function(s) return s end end
package.preload["ui/widget/container/inputcontainer"] = function() return { extend = function(_, t) return t end } end
package.path = arg[1] .. "/woodland.koplugin/?.lua;" .. package.path
local Widget = require("woodland_journal/widget")
local dash = { x=18, y=94, w=1228, h=1472 }
local function run(stack)
    local mode, region, dither = Widget.colourRefresh(dash, { _refresh_stack = stack })()
    return mode, dither
end
local checks, failures = 0, 0
local function expect(label, got, want)
    checks = checks + 1
    if got ~= want then failures = failures + 1; print("FAIL", label, got, want) end
end
expect("status-bar clock tick only", run({ { region = { x=0, y=0, w=1264, h=90 } } }), nil)
expect("bar edge touching dashboard", run({ { region = { x=0, y=0, w=1264, h=94 } } }), nil)
expect("full-screen show", run({ { region = { x=0, y=0, w=1264, h=1680 } } }), "[partial]")
local _, d = run({ { region = { x=300, y=600, w=600, h=300 } } })
expect("dialog closing over dashboard", run({ { region = { x=300, y=600, w=600, h=300 } } }), "[partial]")
expect("dither requested", d, true)
expect("bottom bar only", run({ { region = { x=0, y=1570, w=1264, h=110 } } }), nil)
expect("nothing queued", run({}), nil)
expect("unknown UIManager internals", select(1, Widget.colourRefresh(dash, {})()), "[partial]")
local function first(stack) return Widget.colourRefresh(dash, { _refresh_stack = stack }, true)() end
expect("first paint of a new dashboard flashes", first({ { region = { x=0, y=0, w=1264, h=1680 } } }), "full")
expect("first paint still skips clock-only ticks", first({ { region = { x=0, y=0, w=1264, h=90 } } }), nil)
expect("first paint dithers", select(3, first({ { region = { x=0, y=0, w=1264, h=1680 } } })), true)
print(string.format("%s colour refresh: %d checks, %d failures", failures == 0 and "PASS" or "FAIL", checks, failures))
os.exit(failures == 0 and 0 or 1)
