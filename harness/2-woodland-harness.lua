-- Desktop emulator harness for Woodland Journal. Never install on the Kobo.
-- WOODLAND_PLAN names a Lua file returning steps; WOODLAND_OUT receives PNGs.
local plan_path = os.getenv("WOODLAND_PLAN")
if not plan_path then return end
local UIManager = require("ui/uimanager")
local Event = require("ui/event")
local Geom = require("ui/geometry")
local Device = require("device")
local logger = require("logger")
local out = os.getenv("WOODLAND_OUT") or "."
local loaded, steps = pcall(dofile, plan_path)
if not loaded then
    logger.warn("woodland-harness: plan failed", steps)
    steps = {}
end
local index = 0

-- Device and reader state for this run, applied before the home screen is
-- first built: WOODLAND_COLOR=0 renders as a black-and-white Kobo;
-- WOODLAND_GOODREADS_PROFILE sets (or "none" clears) the Goodreads profile;
-- first-run setup is marked done unless WOODLAND_TEST_SETUP=1.
do
    local colour = os.getenv("WOODLAND_COLOR")
    if colour == "0" then G_reader_settings:saveSetting("color_rendering", false)
    elseif colour == "1" then G_reader_settings:saveSetting("color_rendering", true) end
    local profile = os.getenv("WOODLAND_GOODREADS_PROFILE")
    if profile == "none" then G_reader_settings:delSetting("simpleui_woodland_goodreads_profile")
    elseif profile and profile ~= "" then G_reader_settings:saveSetting("simpleui_woodland_goodreads_profile", profile) end
    if os.getenv("WOODLAND_TEST_SETUP") == "1" then G_reader_settings:delSetting("simpleui_woodland_setup_done")
    else G_reader_settings:saveSetting("simpleui_woodland_setup_done", true) end
    logger.info("woodland-harness: device", Device.screen:getWidth(), Device.screen:getHeight(),
        "dpi", Device.screen:getDPI(), "colour", Device.screen:isColorEnabled(), "goodreads", tostring(profile))
end
-- Watchdog: never leave a headless emulator running.
UIManager:scheduleIn(tonumber(os.getenv("WOODLAND_TIMEOUT")) or 150, function()
    logger.warn("woodland-harness: watchdog quit")
    UIManager:quit()
end)

-- The desktop nightly warns about unreadable folders; v2026.07.1 on the Kobo
-- has no such dialog. Log the path and keep the dialog out of screenshots.
local FileChooser = require("ui/widget/filechooser")
local getPathList = FileChooser.getPathList
FileChooser.getPathList = function(self, path, ...)
    local readable = getPathList(self, path, ...)
    if not readable then logger.warn("woodland-harness: unreadable folder", path) end
    return readable
end
local refreshPath = FileChooser.refreshPath
FileChooser.refreshPath = function(self, ...)
    self.unreadable_path_warned = self.path
    return refreshPath(self, ...)
end

-- Optional fixture: a Lua file returning a table of named scenarios, each a
-- function(snapshot) -> snapshot. The plan selects one by setting the global
-- WOODLAND_SCENARIO and refreshing, so edge cases render through the real
-- widgets with SimpleUI's real layout.
local fixture_path = os.getenv("WOODLAND_FIXTURE")
if fixture_path and fixture_path ~= "" then
    local scenarios = dofile(fixture_path)
    local wrapped = false
    local orig_require = require
    local function wrap()
        if wrapped then return end
        wrapped = true -- set first: wrap must never recurse through the hook
        local ok, Data = pcall(orig_require, "woodland_journal/data")
        if not ok then wrapped = false; return end
        local snapshot = Data.snapshot
        Data.snapshot = function(...)
            local data, helpers = snapshot(...)
            local scenario = rawget(_G, "WOODLAND_SCENARIO")
            if scenario and scenarios[scenario] then data = scenarios[scenario](data) or data end
            return data, helpers
        end
        wrapped = true
    end
    local orig_require = require
    require = function(name, ...)
        local result = orig_require(name, ...)
        if name == "woodland_journal/data" then wrap() end
        return result
    end
end

-- Log the geometry SimpleUI gives each Woodland widget on its first paint.
do
    local orig_require = require
    local logged = {}
    require = function(name, ...)
        local result = orig_require(name, ...)
        if name == "woodland_journal/widget" and not result._harness_wrapped then
            result._harness_wrapped = true
            local paintTo = result.paintTo
            result.paintTo = function(self, bb, x, y)
                paintTo(self, bb, x, y)
                rawset(_G, "WOODLAND_LAST", self)
                local key = tostring(self.scene.width) .. "x" .. tostring(self.scene.height)
                    .. "@" .. x .. "," .. y
                if not logged[key] then
                    logged[key] = true
                    local screen = self.ctx and self.ctx._screen_widget
                    logger.info("woodland-harness: geometry", "pos", x, y, "size", self.dimen.w, self.dimen.h,
                        "factor", self.factor, "inset", self.inset, "scene", self.scene.width, self.scene.height,
                        "max_height", self.max_height, "content_h", screen and screen._layout_content_h)
                end
            end
        end
        return result
    end
end

-- Fit audit of the most recently painted Woodland widget, using measured
-- widget sizes: truncation, stack overflow, bounds, text collisions and
-- tap-target sizes (mm at the emulated screen's ppi).
rawset(_G, "WOODLAND_AUDIT", function(label)
    local w = rawget(_G, "WOODLAND_LAST")
    if not w then logger.warn("woodland-audit", label, "no widget painted"); return end
    local f, scene, problems, rects = w.factor, w.scene, {}, {}
    local function add(...) problems[#problems+1] = table.concat({...}, " ") end
    for _, item in ipairs(scene.items) do
        local child = w.children[item]
        local x, y, iw, ih = item.x, item.y, item.w or 0, item.h or 0
        if item.kind == "text" and child then
            local size = child:getSize()
            local tw, th = size.w / f, size.h / f
            if item.align == "center" then x = x + (item.w - tw) / 2 elseif item.align == "right" then x = x + item.w - tw end
            if item.box_h then y = y + (item.box_h - th) / 2 end
            iw, ih = tw, th
            if child._is_truncated then add("TRUNCATED:", item.text) end
            rects[#rects+1] = { x=x, y=y, w=iw, h=ih, name=item.text }
        elseif item.kind == "stack" and child then
            if item.overflow then add("STACK OVERFLOW:", tostring(item.blocks[1].text or "runs")) end
            for _, e in ipairs(child.entries) do
                if e.truncated then add("ELLIPSIS (by design, max_lines):", tostring(e.block.text)) end
                local ex = item.x
                if e.runs and e.block.align == "center" then ex = item.x + (child.width / f - e.w / f) / 2 end
                rects[#rects+1] = { x=ex, y=item.y + e.y / f, w=e.w / f, h=e.h / f,
                    name=tostring(e.block.text or (e.runs and "attribution")) }
            end
        elseif item.kind == "art" then
            rects[#rects+1] = { x=x, y=y, w=iw, h=ih, name="art " .. item.file:match("[^/]+$"), art=true }
        end
        if x < -0.5 or y < -0.5 or x + iw > scene.width + 0.5 or y + ih > scene.height + 0.5 then
            add("OUT OF BOUNDS:", item.kind, tostring(item.text or item.file or ""),
                string.format("%.0f,%.0f %.0fx%.0f", x, y, iw, ih))
        end
    end
    for i = 1, #rects do
        for j = i + 1, #rects do
            local a, b = rects[i], rects[j]
            local ox = math.min(a.x + a.w, b.x + b.w) - math.max(a.x, b.x)
            local oy = math.min(a.y + a.h, b.y + b.h) - math.max(a.y, b.y)
            -- Line boxes include ascender/descender padding; flag only
            -- overlaps deeper than 30% of the smaller box (real collisions).
            if ox > 1 and oy > 0.3 * math.min(a.h, b.h) and not (a.art and b.art) then
                add("OVERLAP:", a.name, "<>", b.name, string.format("(%.0fx%.0f units)", ox, oy))
            end
        end
    end
    -- A target is too small when it is shorter than KOReader's own standard
    -- menu item on this screen (Size.item.height_default, scaleBySize(30)).
    local smallest, ppi = math.huge, Device.screen:getDPI()
    local min_px = Device.screen:scaleBySize(30)
    for _, t in ipairs(scene.targets) do
        local px = math.min(t.w, t.h) * f
        local mm = px / ppi * 25.4
        smallest = math.min(smallest, mm)
        if px < min_px then
            add("SMALL TARGET:", tostring(t.action or t.file), string.format("%.1f mm (KOReader item %.1f mm)", mm, min_px / ppi * 25.4))
        end
    end
    logger.info("woodland-audit", label, string.format("%d text rects, %d targets (smallest %.1f mm), %d findings",
        #rects, #scene.targets, smallest, #problems))
    for _, p in ipairs(problems) do logger.info("woodland-audit", label, p) end
end)

local function gesture(spec)
    local ges = {
        ges = spec.ges, direction = spec.direction, distance = spec.distance or 500,
        pos = Geom:new{x = spec.x, y = spec.y, w = 0, h = 0},
        time = require("ui/time").now(),
    }
    UIManager:sendEvent(Event:new("Gesture", ges))
end

-- Tap the centre of the last painted Woodland widget's n-th target whose
-- action (or file/book title) matches; logs the screen point used.
rawset(_G, "WOODLAND_TAP", function(match, n)
    local w = rawget(_G, "WOODLAND_LAST")
    if not w then logger.warn("woodland-harness: tap, no widget"); return end
    local seen = 0
    for _, t in ipairs(w.scene.targets) do
        local label = table.concat({ t.action or "", t.book and t.book.title or "", t.file or "" }, " ")
        if tostring(label):find(match, 1, true) then
            seen = seen + 1
            if seen == (n or 1) then
                local x = math.floor(w.dimen.x + w.inset + (t.x + t.w / 2) * w.factor + 0.5)
                local y = math.floor(w.dimen.y + (t.y + t.h / 2) * w.factor + 0.5)
                logger.info("woodland-harness: tap", match, label, x, y)
                gesture{ges = "tap", x = x, y = y}
                return
            end
        end
    end
    logger.warn("woodland-harness: tap target not found", match)
end)
-- Press the most recently created button labelled `label` (any dialog), as
-- a tap would. Every Button KOReader builds is recorded by its label.
local buttons_by_label = {}
do
    local Button = require("ui/widget/button")
    local init = Button.init
    Button.init = function(self, ...)
        local result = init(self, ...)
        if type(self.text) == "string" then buttons_by_label[self.text] = self end
        return result
    end
end
rawset(_G, "WOODLAND_PRESS", function(label)
    local button = buttons_by_label[label]
    if button and type(button.callback) == "function" then
        logger.info("woodland-harness: press", label)
        button.callback()
    else
        logger.warn("woodland-harness: button not found", label)
    end
end)
-- Type `text` into the topmost InputDialog.
rawset(_G, "WOODLAND_INPUT", function(text)
    local top = UIManager._window_stack[#UIManager._window_stack]
    local dialog = top and top.widget
    if dialog and dialog._input_widget then
        dialog._input_widget:setText(text)
        logger.info("woodland-harness: input", text)
    else
        logger.warn("woodland-harness: no input dialog on top")
    end
end)
-- Log SimpleUI's saved home layout and Woodland's settings.
rawset(_G, "WOODLAND_LOG_STATE", function(label)
    local ok, S = pcall(require, "infra/sui_store")
    local layout = ok and S:readSetting("simpleui_layout")
    local pages = {}
    for i, page in ipairs(layout and layout.pages or {}) do
        local ids = {}
        for _, e in ipairs(page.modules or {}) do ids[#ids+1] = type(e) == "table" and e.id or tostring(e) end
        pages[#pages+1] = i .. ":" .. table.concat(ids, "+")
    end
    logger.info("woodland-check", label, "layout", layout and table.concat(pages, " | ") or "none",
        "name", tostring(G_reader_settings:readSetting("simpleui_woodland_name")),
        "goal", tostring(G_reader_settings:readSetting("simpleui_woodland_goal_minutes")),
        "goodreads", tostring(G_reader_settings:readSetting("simpleui_woodland_goodreads_profile")),
        "setup_done", tostring(G_reader_settings:readSetting("simpleui_woodland_setup_done")))
end)
-- Clear SimpleUI's saved home layout, as on a device where nothing has been
-- arranged yet, and rebuild the home screen.
rawset(_G, "WOODLAND_RESET_LAYOUT", function()
    local ok, S = pcall(require, "infra/sui_store")
    if ok then
        for _, key in ipairs{ "simpleui_layout", "simpleui_hs_module_order", "simpleui_hs_woodland_journal",
                "simpleui_hs_woodland_goodreads" } do S:del(key) end
    end
    local HS = package.loaded["screens/sui_homescreen"]
    if HS and HS._instance and HS.refresh then pcall(HS.refresh, false) end
    logger.info("woodland-harness: layout reset")
end)

-- Close the topmost dialog without touching the dashboard.
rawset(_G, "WOODLAND_CLOSE_TOP", function()
    local top = UIManager._window_stack[#UIManager._window_stack]
    if top and not top.widget._refreshImmediate then
        logger.info("woodland-harness: closing", top.widget.name or top.widget.title or tostring(top.widget))
        UIManager:close(top.widget)
    end
end)

local function step()
    index = index + 1
    local s = steps[index]
    if not s then
        logger.info("woodland-harness: done")
        UIManager:quit()
        return
    end
    local ok, err = pcall(function()
        if s.shot then
            UIManager:forceRePaint()
            Device.screen:shot(out .. "/" .. s.shot .. ".png")
            logger.info("woodland-harness: shot", s.shot)
        elseif s.tap then
            gesture{ges = "tap", x = s.tap[1], y = s.tap[2]}
        elseif s.swipe then
            gesture{ges = "swipe", direction = s.swipe, x = s.x or 632, y = s.y or 840}
        elseif s.lua then
            s.lua()
        end
    end)
    if not ok then logger.warn("woodland-harness: step failed", index, err) end
    UIManager:scheduleIn(s.wait or 1.5, step)
end

UIManager:scheduleIn(tonumber(os.getenv("WOODLAND_DELAY")) or 6, step)
