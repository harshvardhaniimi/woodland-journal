-- SPDX-License-Identifier: AGPL-3.0-or-later
-- First-run setup: the reader's name (optional), a daily goal suggested from
-- KOReader's own statistics, Goodreads (opt-in) and where the dashboard goes
-- on the home screen. Runs once in the file manager; Tools → Woodland
-- Journal → Set up runs it again. Nothing leaves the device.
local UIManager = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")
local _ = require("gettext")
local Settings = require("woodland_journal/settings")
local Layout = require("woodland_journal/layout")

local M = {}

local JOURNAL, GOODREADS = "woodland_journal", "woodland_goodreads"

-- Median minutes on the days with reading in the last 30, rounded to 5 and
-- kept between 10 and 120. Nil with fewer than five reading days.
function M.medianGoal(day_minutes)
    local days = {}
    for _i, m in ipairs(day_minutes or {}) do
        m = tonumber(m)
        if m and m >= 1 then days[#days+1] = m end
    end
    if #days < 5 then return nil end
    table.sort(days)
    local median = days[math.ceil(#days / 2)]
    return math.max(10, math.min(120, math.floor(median / 5 + 0.5) * 5))
end

function M.suggestedGoal(now)
    local ok, minutes = pcall(function()
        local path = require("datastorage"):getSettingsDir() .. "/statistics.sqlite3"
        if not require("libs/libkoreader-lfs").attributes(path, "mode") then return nil end
        local conn = require("lua-ljsqlite3/init").open(path, "ro")
        local since = (now or os.time()) - 30 * 86400
        local ok_q, columns = pcall(conn.exec, conn, string.format([[
            SELECT sum(duration) FROM page_stat_data
            WHERE start_time >= %d AND duration > 0
            GROUP BY date(start_time, 'unixepoch', 'localtime')]], since))
        pcall(conn.close, conn)
        local days = {}
        for _i, seconds in ipairs(ok_q and columns and columns[1] or {}) do days[#days+1] = (tonumber(seconds) or 0) / 60 end
        return M.medianGoal(days)
    end)
    return ok and minutes or nil
end

-- A Goodreads profile already in use: the one saved with an offline shelf
-- snapshot (Woodland 0.1 kept shelves without a profile setting).
local function savedProfile()
    local ok, data = pcall(function() return require("woodland_journal/goodreads").load() end)
    return ok and data and Settings.parseGoodreadsProfile(data.profile_id) or nil
end

local function finish(on_done)
    Settings.setSetupDone(true)
    if on_done then on_done() end
end

local function placement(on_done)
    local function after()
        -- Goodreads gets its own page after the dashboard, and only when on.
        if Settings.goodreadsEnabled() then
            pcall(Layout.placeAfter, GOODREADS, JOURNAL)
        else
            pcall(Layout.remove, GOODREADS)
        end
        finish(on_done)
        UIManager:show(InfoMessage:new{ timeout=6, text=_("Woodland Journal is ready.") .. "\n\n"
            .. (Layout.pageOf(JOURNAL) and _("Open the Home tab to see your dashboard.")
                or _("Add it to a home-screen page in SimpleUI's Arrange Modules, on a page by itself.")) })
    end
    if Layout.pageOf(JOURNAL) then return after() end
    local ButtonDialog = require("ui/widget/buttondialog")
    local dialog
    local function choose(first)
        return function()
            UIManager:close(dialog)
            if first ~= nil then pcall(Layout.placeOnOwnPage, JOURNAL, first) end
            after()
        end
    end
    dialog = ButtonDialog:new{
        title = _("Where should the dashboard go?\n\nIt fills a home-screen page by itself; your other pages stay as they are."),
        buttons = {
            {{ text=_("As the first page"), callback=choose(true) }},
            {{ text=_("As the last page"), callback=choose(false) }},
            {{ text=_("I'll arrange it myself"), callback=choose(nil) }},
        },
    }
    UIManager:show(dialog)
end

-- Ask for a Goodreads profile. on_saved(true) after saving, (false) when the
-- reader declines or clears it.
function M.goodreads(on_saved)
    local InputDialog = require("ui/widget/inputdialog")
    local dialog
    dialog = InputDialog:new{
        title = _("Goodreads profile"),
        description = _("Paste your Goodreads profile address, or just its number: in https://www.goodreads.com/user/show/12345678-name the number is 12345678.\n\nWoodland reads your public shelves over Wi-Fi when you tap Refresh and keeps an offline copy on this device. No password is needed; the profile must be public. Leave empty to turn Goodreads off."),
        input = Settings.goodreadsProfile() or savedProfile() or "",
        buttons = {{
            { text=_("Cancel"), id="close", callback=function() UIManager:close(dialog) end },
            { text=_("Save"), is_enter_default=true, callback=function()
                local text = dialog:getInputText()
                local id = Settings.parseGoodreadsProfile(text)
                if text:match("%S") and not id then
                    UIManager:show(InfoMessage:new{ text=_("That doesn't look like a Goodreads profile address or number.") })
                    return
                end
                UIManager:close(dialog)
                Settings.setGoodreadsProfile(id)
                if on_saved then on_saved(id ~= nil) end
            end },
        }},
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

local function goodreadsStep(on_done)
    local ButtonDialog = require("ui/widget/buttondialog")
    local dialog
    dialog = ButtonDialog:new{
        title = _("Show your Goodreads shelves?\n\nA second home page can show your public Goodreads shelves, saved for offline reading. Without it, Woodland shows only what is on this device."),
        buttons = {
            {{ text=_("Add my Goodreads profile"), callback=function()
                UIManager:close(dialog)
                M.goodreads(function() placement(on_done) end)
            end }},
            {{ text=_("Not now"), callback=function()
                UIManager:close(dialog)
                Settings.setGoodreadsProfile(nil)
                placement(on_done)
            end }},
        },
    }
    UIManager:show(dialog)
end

local function goalStep(on_done)
    local SpinWidget = require("ui/widget/spinwidget")
    local suggested = M.suggestedGoal()
    local info
    if Settings.hasGoal() then
        info = string.format(_("Your current goal is %d minutes a day."), Settings.goal())
            .. (suggested and ("\n" .. string.format(_("Your reading over the last 30 days suggests %d."), suggested)) or "")
    elseif suggested then
        info = string.format(_("Suggested from your reading on this device over the last 30 days: %d minutes a day."), suggested)
    else
        info = _("KOReader has little reading history here yet; 30 minutes a day is a common start.")
    end
    UIManager:show(SpinWidget:new{
        title_text = _("Daily reading goal (minutes)"),
        info_text = info,
        -- A goal already chosen (an earlier setup, or Woodland 0.1) is kept.
        value = Settings.hasGoal() and Settings.goal() or suggested or 30,
        value_min = 5, value_max = 600, value_step = 5, value_hold_step = 30, default_value = suggested or 30,
        ok_text = _("Next"), ok_always_enabled = true,
        callback = function(widget) Settings.setGoal(widget.value) end,
        close_callback = function() goodreadsStep(on_done) end,
    })
end

function M.run(on_done)
    local InputDialog = require("ui/widget/inputdialog")
    local dialog
    dialog = InputDialog:new{
        title = _("Welcome to Woodland Journal"),
        description = _("What name should the greeting use? Leave it empty for a greeting without a name."),
        input = Settings.name(),
        buttons = {{
            { text=_("Skip setup"), id="close", callback=function()
                UIManager:close(dialog)
                finish(on_done)
            end },
            { text=_("Next"), is_enter_default=true, callback=function()
                Settings.setName(dialog:getInputText())
                UIManager:close(dialog)
                goalStep(on_done)
            end },
        }},
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

-- Version, what this device has, and where Woodland has been tested.
function M.about(plugin)
    local meta = dofile(plugin.path .. "/_meta.lua")
    local Registry = plugin.registry and plugin.registry()
    local lines = {
        "Woodland Journal " .. tostring(meta.version),
        "",
        _("SimpleUI") .. ": " .. (Registry and _("found") or _("not found — install SimpleUI first")),
        _("Goodreads") .. ": " .. (Settings.goodreadsProfile() or _("off")),
        _("Ink") .. ": " .. (Settings.monochrome() and _("monochrome") or _("colour"))
            .. (Settings.monochromeIsAutomatic() and (" (" .. _("automatic") .. ")") or ""),
    }
    local legacy = plugin.legacyCopy and plugin:legacyCopy()
    if legacy then
        lines[#lines+1] = ""
        lines[#lines+1] = _("An older copy inside SimpleUI Extra is active, so this plugin is idle:") .. "\n" .. legacy
    end
    lines[#lines+1] = ""
    lines[#lines+1] = _("Tested by its author on one Kobo Libra Colour only. Back up your Kobo before installing, and expect rough edges on other devices.")
    UIManager:show(InfoMessage:new{ text=table.concat(lines, "\n") })
end

return M
