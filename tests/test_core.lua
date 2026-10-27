-- Woodland Journal's device-independent code without KOReader: settings,
-- goal suggestion, cover sizes, the Goodreads feed parser, page layouts and
-- the SimpleUI layout edits (against an in-memory store).
-- Usage: luajit test_core.lua <repo-dir>
local root = arg[1]
package.path = root .. "/woodland.koplugin/?.lua;" .. package.path

-- Minimal KOReader stand-ins.
local settings = {}
_G.G_reader_settings = {
    readSetting = function(_, k) return settings[k] end,
    saveSetting = function(_, k, v) settings[k] = v end,
    delSetting = function(_, k) settings[k] = nil end,
}
local colour_screen = true
package.preload["device"] = function()
    return { screen = { isColorEnabled = function() return colour_screen end } }
end
package.preload["gettext"] = function() return function(s) return s end end
for _, name in ipairs{ "ui/uimanager", "ui/widget/infomessage" } do
    package.preload[name] = function() return setmetatable({}, { __index = function() return function() end end }) end
end
-- SimpleUI's store and registry, in memory.
local store = {}
package.preload["infra/sui_store"] = function()
    return {
        readSetting = function(_, k) return store[k] end,
        saveSetting = function(_, k, v) store[k] = v end,
        del = function(_, k) store[k] = nil end,
    }
end
local MODULES = { { id="clock" }, { id="currently" }, { id="woodland_journal" }, { id="woodland_goodreads" } }
package.preload["modules/moduleregistry"] = function()
    local R = {}
    function R.list() return MODULES end
    function R.get(id) for _, m in ipairs(MODULES) do if m.id == id then return m end end end
    function R.isEnabled(m) return m.id ~= "woodland_goodreads" end
    function R.loadOrder() return { "clock", "currently", "__page_break__", "woodland_journal", "woodland_goodreads" } end
    function R.register() end
    return R
end

local n, failures = 0, 0
local function check(label, ok)
    n = n + 1
    if not ok then failures = failures + 1; print("FAIL", label) end
end
local function read(path) local f = assert(io.open(path, "rb")); local s = f:read("*a"); f:close(); return s end

-- Settings: no personal defaults; Goodreads profile parsing.
local Settings = require("woodland_journal/settings")
check("no default name", Settings.name() == "")
check("default goal", Settings.goal() == 30)
check("no Goodreads by default", not Settings.goodreadsEnabled())
check("monochrome follows a colour screen", Settings.monochrome() == false and Settings.monochromeIsAutomatic())
colour_screen = false
check("monochrome follows a b/w screen", Settings.monochrome() == true)
Settings.setMonochrome(false)
check("explicit colour wins", Settings.monochrome() == false and not Settings.monochromeIsAutomatic())
colour_screen = true
local P = Settings.parseGoodreadsProfile
check("profile from number", P("12345678") == "12345678")
check("profile from address", P("https://www.goodreads.com/user/show/12345678-test-reader") == "12345678")
check("profile from shelf address", P("https://www.goodreads.com/review/list/12345678?shelf=read") == "12345678")
check("profile with spaces", P("  42 ") == "42")
check("not a profile", P("test-reader") == nil and P("") == nil and P(nil) == nil and P("12 34") == nil)
check("overlong number rejected", P(string.rep("9", 20)) == nil)
Settings.setGoodreadsProfile("https://www.goodreads.com/user/show/12345678-x")
check("profile saved as number", settings.simpleui_woodland_goodreads_profile == "12345678" and Settings.goodreadsEnabled())
Settings.setGoodreadsProfile("")
check("empty profile turns Goodreads off", settings.simpleui_woodland_goodreads_profile == nil)
Settings.setName("  Test\nReader  ")
check("name cleaned", Settings.name() == "Test Reader")
Settings.setName("   ")
check("blank name cleared", settings.simpleui_woodland_name == nil)

-- Goal suggestion from daily minutes.
local Setup = require("woodland_journal/setup")
check("too little history", Setup.medianGoal({ 10, 20, 30, 40 }) == nil)
check("median rounded to 5", Setup.medianGoal({ 12, 18, 23, 41, 60 }) == 25)
check("goal floor", Setup.medianGoal({ 1, 2, 3, 4, 5, 6 }) == 10)
check("goal ceiling", Setup.medianGoal({ 300, 400, 500, 600, 700 }) == 120)
check("zero days ignored", Setup.medianGoal({ 0, 0, 0, 30, 30, 30, 30, 30 }) == 30)

-- Cover sizes from file headers, and the fit.
local Store = require("woodland_journal/goodreads")
local function be32(v) return string.char(math.floor(v / 16777216) % 256, math.floor(v / 65536) % 256, math.floor(v / 256) % 256, v % 256) end
local function be16(v) return string.char(math.floor(v / 256) % 256, v % 256) end
local png = "\137PNG\r\n\26\n" .. be32(13) .. "IHDR" .. be32(1838) .. be32(2775) .. "\8\2\0\0\0"
local w, h = Store.imageSize(png)
check("PNG size", w == 1838 and h == 2775)
local app0 = "\255\224" .. be16(16) .. "JFIF\0\1\1\0\0\1\0\1\0\0"
local dqt = "\255\219" .. be16(5) .. "\0\1\2"
local sof2 = "\255\194" .. be16(17) .. "\8" .. be16(2850) .. be16(1875) .. "\3\1\34\0\2\17\1\3\17\1"
w, h = Store.imageSize("\255\216" .. app0 .. dqt .. sof2 .. "\255\218")
check("progressive JPEG size", w == 1875 and h == 2850)
w, h = Store.imageSize("\255\216" .. app0 .. "\255\196" .. be16(4) .. "\0\0" .. "\255\192" .. be16(17) .. "\8" .. be16(475) .. be16(318))
check("baseline JPEG size after a DHT", w == 318 and h == 475)
check("unknown data", Store.imageSize("GIF89a") == nil and Store.imageSize("") == nil and Store.imageSize(nil) == nil)
check("truncated JPEG", Store.imageSize("\255\216" .. app0) == nil)
local fw, fh = Store.fitWithin(1875, 2850, 600, 900)
check("tall cover fits by height", fh == 900 and fw == 592)
fw, fh = Store.fitWithin(2000, 1000, 600, 900)
check("wide cover fits by width", fw == 600 and fh == 300)
check("small cover left alone", Store.fitWithin(318, 475, 600, 900) == nil and Store.fitWithin(nil, 10, 600, 900) == nil)

-- Feed parsing: entities, HTML, invalid ids, missing fields, Devanagari.
local books = Store.parse(read(root .. "/tests/fixtures/shelf.xml"))
check("three books with numeric ids", #books == 3)
local walden, middlemarch, godan = books[1], books[2], books[3]
check("title and author", walden.title == "Walden; or, Life in the Woods" and walden.author == "Henry David Thoreau")
check("description cleaned", walden.description:find("“", 1, true) == nil
    and walden.description:find('"deliberately" & simply — a record of seasons, work & solitude.', 1, true) ~= nil
    and walden.description:find("pond.\n\nIn 1845", 1, true) ~= nil and walden.description:find("<", 1, true) == nil)
check("numbers", walden.pages == 352 and walden.average == 3.81 and walden.published == "1854" and walden.isbn == "0451532163")
check("unrated stays nil", walden.rating == nil and walden.added == "14 Oct 2026")
check("medium cover when large is missing", middlemarch.image_url:find("medium", 1, true) ~= nil)
check("review and rating", middlemarch.rating == 5 and middlemarch.review:find("then impossible", 1, true) ~= nil
    and middlemarch.read_at == "3 Jan 2026")
check("Devanagari kept", godan.title == "गोदान" and godan.description == "होरी और धनिया की कथा।")
check("entity declarations refused", not pcall(Store.parse, '<!DOCTYPE x [<!ENTITY a "b">]><rss/>'))
check("non-RSS refused", not pcall(Store.parse, "<html>Blocked</html>"))

-- Goodreads pages fit at several screen shapes.
local GScene = require("woodland_journal/goodreads_scene")
local function inside(scene)
    for _, t in ipairs(scene.targets) do
        if t.x < 0 or t.y < 0 or t.x + t.w > scene.width or t.y + t.h > scene.height then return false end
    end
    for _, it in ipairs(scene.items) do
        if it.x < 0 or it.y < 0 or it.x + (it.w or 0) > scene.width + 0.5 then return false end
    end
    return true
end
local shelf = { id="to-read", label="Want to read", books=books }
for _, aspect in ipairs{ 1473 / 1228, 1200 / 1000, 1240 / 1040, 1700 / 1400, 856 / 1650 } do
    local scene, page, pages = GScene.build(shelf, 1, os.time(), aspect)
    check("shelf fits " .. aspect, inside(scene) and page == 1 and pages == 1)
    for _, b in ipairs(books) do
        check("book page fits " .. aspect .. " " .. b.id, inside(GScene.buildBook(b, { shelf_label="Want to read", on_kobo=true, aspect=aspect })))
    end
end
local empty = GScene.build({ id="read", label="Read", books={} }, 3, nil, 1.2)
check("empty shelf page", inside(empty))

-- Home page: no name, Goodreads on and off, finished book.
local Model = require("woodland_journal/model")
local Scene = require("woodland_journal/scene")
local now = os.time{ year=2026, month=10, day=26, hour=9, min=5 }
local function home(over)
    local data = { now=now, name="", goal=30, days=Model.days(now), available=true, others={}, goodreads=false,
        current={ file="/b.epub", title="Walden", authors="Henry David Thoreau", percent=0.4, pages=352 } }
    for k, v in pairs(over or {}) do data[k] = v end
    return Scene.build(data, nil, 1473 / 1228)
end
local function texts(scene) local t = {} for _, it in ipairs(scene.items) do if it.text then t[it.text] = true end end return t end
local function action(scene, a) for _, t in ipairs(scene.targets) do if t.action == a then return true end end end
check("greeting without a name", texts(home())["Good morning"])
check("greeting with a name", texts(home({ name="Test Reader" }))["Good morning, Test Reader"])
check("Goodreads off: label and no shelf jump", texts(home())["Goodreads not available"] and action(home(), "goodreads_off") and not action(home(), "goodreads"))
check("Goodreads on: shelf button", texts(home({ goodreads=true }))["Goodreads shelves"] and action(home({ goodreads=true }), "goodreads"))
local finished = home({ current={ file="/b.epub", title="Walden", authors="Henry David Thoreau", percent=1, status="complete" } })
check("finished book", texts(finished)["Book finished"] and texts(finished)["Open library"] and not texts(finished)["Continue reading"])
check("model finished rule", Model.finished({ percent=1 }) and Model.finished({ percent=0.2, status="complete" })
    and not Model.finished({ percent=0.99 }) and not Model.finished(nil))
check("short date", Model.shortDate("2026-10-03") == "3 Oct 2026" and Model.shortDate("yesterday") == nil)

-- SimpleUI layout edits change only Woodland's own entries.
local Layout = require("woodland_journal/layout")
store.simpleui_layout = nil
check("default layout from module order", Layout.pageOf("woodland_journal") == 2 and Layout.pageOf("woodland_goodreads") == nil)
store.simpleui_layout = { pages = { { id=1, modules={ "clock", "currently" } } } }
check("place first", Layout.placeOnOwnPage("woodland_journal", true))
local pages = store.simpleui_layout.pages
check("journal on page 1, others kept", #pages == 2 and pages[1].modules[1] == "woodland_journal" and pages[2].modules[2] == "currently"
    and pages[1].id == 1 and pages[2].id == 2)
check("enabled flag", store.simpleui_hs_woodland_journal == true)
check("module order", table.concat(store.simpleui_hs_module_order, ",") == "woodland_journal,clock,currently,woodland_goodreads")
check("no double placement", not Layout.placeOnOwnPage("woodland_journal", false))
check("Goodreads after the journal", Layout.placeAfter("woodland_goodreads", "woodland_journal") and Layout.pageOf("woodland_goodreads") == 2
    and #store.simpleui_layout.pages == 3)
check("remove Goodreads drops its page", Layout.remove("woodland_goodreads") and #store.simpleui_layout.pages == 2
    and store.simpleui_hs_woodland_goodreads == false and Layout.pageOf("woodland_goodreads") == nil)
store.simpleui_layout = { pages = { { id=1, modules={ "woodland_journal", "clock" } } } }
check("remove keeps a shared page", Layout.remove("woodland_journal") and #store.simpleui_layout.pages == 1
    and store.simpleui_layout.pages[1].modules[1] == "clock")
store.simpleui_layout = { pages = { { id=1, modules={ "woodland_journal" } } } }
check("removing the last module keeps one page", Layout.remove("woodland_journal") and #store.simpleui_layout.pages == 1)
store.simpleui_layout = { pages = { { id=1, modules={} } } }
check("empty home screen replaced", Layout.placeOnOwnPage("woodland_journal", false) and #store.simpleui_layout.pages == 1)

print(string.format("%s core: %d checks, %d failures", failures == 0 and "PASS" or "FAIL", n, failures))
os.exit(failures == 0 and 0 or 1)
