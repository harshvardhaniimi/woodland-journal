-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Woodland Journal settings, kept in KOReader's settings under the
-- simpleui_woodland_* keys used since 0.1. Nothing personal has a default:
-- the name, goal and Goodreads profile come from first-run setup.
local M = {}

local PREFIX = "simpleui_woodland_"

local function read(key) return G_reader_settings:readSetting(PREFIX .. key) end
local function save(key, value)
    if value == nil then G_reader_settings:delSetting(PREFIX .. key)
    else G_reader_settings:saveSetting(PREFIX .. key, value) end
end

function M.name()
    return (tostring(read("name") or ""):gsub("[\r\n]", " "))
end
function M.setName(name)
    name = (tostring(name or ""):gsub("[\r\n]", " "):gsub("^%s+", ""):gsub("%s+$", ""))
    save("name", name ~= "" and name or nil)
end

function M.goal()
    return math.max(1, math.min(600, tonumber(read("goal_minutes")) or 30))
end
function M.hasGoal() return tonumber(read("goal_minutes")) ~= nil end
function M.setGoal(minutes) save("goal_minutes", math.max(1, math.min(600, math.floor(tonumber(minutes) or 30)))) end

-- Monochrome ink: an explicit choice, otherwise follow the screen (black and
-- white Kobos, or colour rendering switched off in KOReader).
function M.monochrome()
    local value = read("monochrome")
    if value ~= nil then return value == true end
    local ok, colour = pcall(function() return require("device").screen:isColorEnabled() end)
    return not (ok and colour)
end
function M.setMonochrome(value) save("monochrome", value) end
function M.monochromeIsAutomatic() return read("monochrome") == nil end

function M.showTime() return read("show_time") == true end
function M.setShowTime(value) save("show_time", value == true) end

function M.colourRefresh() return read("color_refresh") ~= false end
function M.setColourRefresh(value) save("color_refresh", value == true) end

-- Goodreads profile: the number in a profile address such as
-- https://www.goodreads.com/user/show/12345678-name. Accepts the number or
-- any text containing such an address; nil when none is set.
function M.parseGoodreadsProfile(text)
    text = tostring(text or "")
    local id = text:match("goodreads%.com/user/show/(%d+)") or text:match("goodreads%.com/review/list/(%d+)")
        or text:match("^%s*(%d+)%s*$")
    if id and #id >= 1 and #id <= 15 then return id end
end
function M.goodreadsProfile()
    local id = read("goodreads_profile")
    return M.parseGoodreadsProfile(id)
end
function M.setGoodreadsProfile(id) save("goodreads_profile", M.parseGoodreadsProfile(id)) end
function M.goodreadsEnabled() return M.goodreadsProfile() ~= nil end

function M.setupDone() return read("setup_done") == true end
function M.setSetupDone(value) save("setup_done", value == true or nil) end

-- The snapshot the dashboard builds from.
function M.snapshot()
    return { name=M.name(), goal=M.goal(), monochrome=M.monochrome(), show_time=M.showTime(),
        color_refresh=M.colourRefresh(), goodreads=M.goodreadsEnabled() }
end

return M
