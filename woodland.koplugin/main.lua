-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Woodland Journal: registers its home-screen pages with SimpleUI through
-- SimpleUI's external-module API (Registry.register). KOReader creates this
-- plugin for every file manager and reader instance, and SimpleUI rebuilds
-- its registry on each switch, so registration runs on every init.
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local UIManager = require("ui/uimanager")
local logger = require("logger")
local _ = require("gettext")

local Settings = require("woodland_journal/settings")

local Woodland = WidgetContainer:extend{
    name = "woodland",
    is_doc_only = false,
}

local JOURNAL, GOODREADS = "woodland_journal", "woodland_goodreads"

-- SimpleUI 2.5 and later; earlier versions kept the registry at the root.
local function registry()
    for _i, path in ipairs{ "modules/moduleregistry", "desktop_modules/moduleregistry" } do
        local ok, Registry = pcall(require, path)
        if ok and type(Registry) == "table" and type(Registry.register) == "function" then return Registry end
    end
end

-- Woodland Journal 0.1 was installed inside SimpleUI Extra. While that copy
-- exists it registers the same pages, so this plugin stays out of its way.
function Woodland:legacyCopy()
    local plugins = tostring(self.path or ""):match("^(.*)/[^/]+$")
    local path = plugins and plugins .. "/simpleui_ext.koplugin/modules/module_woodland_journal.lua"
    local lfs = require("libs/libkoreader-lfs")
    if path and lfs.attributes(path, "mode") == "file" then return path end
end

-- The home screen SimpleUI is showing, if any.
local function homeScreen()
    for i = #UIManager._window_stack, 1, -1 do
        local widget = UIManager._window_stack[i].widget
        if widget and widget._refreshImmediate then return widget end
    end
end

function Woodland:register()
    if self:legacyCopy() then
        logger.warn("woodland: Woodland Journal 0.1 inside SimpleUI Extra is active; not registering this copy")
        return false
    end
    local Registry = registry()
    if not Registry then
        logger.warn("woodland: SimpleUI is not installed or not loaded; nothing to register")
        return false
    end
    local ok, err = pcall(function()
        Registry.register(require("woodland_journal/module_journal"))
        if Settings.goodreadsEnabled() then
            Registry.register(require("woodland_journal/module_goodreads"))
        else
            if Registry.unregister then Registry.unregister(GOODREADS) end
            -- Without a profile there is no Goodreads page: take Woodland's
            -- own Goodreads entry out of the home layout (after setup, which
            -- handles it itself).
            if Settings.setupDone() then
                local Layout = require("woodland_journal/layout")
                if Layout.pageOf(GOODREADS) then Layout.remove(GOODREADS) end
            end
        end
    end)
    if not ok then logger.warn("woodland: registration failed", err) end
    return ok
end

-- Rebuild a home screen that rendered before this plugin registered.
function Woodland.refreshHome()
    local home = homeScreen()
    if home then pcall(home._refreshImmediate, home, false) end
end

function Woodland:init()
    self.ui.menu:registerToMainMenu(self)
    -- SimpleUI loads before this plugin (plugins load by name), so its
    -- registry normally exists already; otherwise try again on the next tick.
    if not self:register() then
        UIManager:scheduleIn(0, function()
            if self:register() then Woodland.refreshHome() end
        end)
    end
    -- First-run setup, in the file manager only: never over an open book.
    -- Without SimpleUI there is nothing to set up yet; say so once a session.
    if not Settings.setupDone() and not (self.ui and self.ui.document) then
        UIManager:scheduleIn(1.5, function()
            if Settings.setupDone() or require("device").screen_saver_mode or self:legacyCopy() then return end
            if not registry() then
                if not Woodland._told_missing_simpleui then
                    Woodland._told_missing_simpleui = true
                    UIManager:show(require("ui/widget/infomessage"):new{
                        text=_("Woodland Journal needs the SimpleUI plugin for KOReader. Install SimpleUI, then restart KOReader.") })
                end
                return
            end
            require("woodland_journal/setup").run(Woodland.onSettingsChanged)
        end)
    end
end

-- After setup or a Goodreads change: register the Goodreads page and give it
-- its own home page after the dashboard, or drop both; redraw the home screen.
function Woodland.onSettingsChanged()
    local Registry = registry()
    if Registry then
        pcall(function()
            local Layout = require("woodland_journal/layout")
            if Settings.goodreadsEnabled() then
                Registry.register(require("woodland_journal/module_goodreads"))
                if Layout.pageOf(JOURNAL) then Layout.placeAfter(GOODREADS, JOURNAL) end
            else
                if Registry.unregister then Registry.unregister(GOODREADS) end
                Layout.remove(GOODREADS)
            end
        end)
    end
    Woodland.refreshHome()
end

function Woodland:addToMainMenu(menu_items)
    local Setup = require("woodland_journal/setup")
    menu_items.woodland_journal = {
        text = _("Woodland Journal"),
        sorting_hint = "tools",
        sub_item_table = {
            {
                text = _("Set up Woodland Journal…"),
                callback = function() Setup.run(Woodland.onSettingsChanged) end,
            },
            {
                text_func = function()
                    local id = Settings.goodreadsProfile()
                    return id and (_("Goodreads profile") .. ": " .. id) or _("Goodreads profile: not set")
                end,
                keep_menu_open = true,
                callback = function(touchmenu)
                    Setup.goodreads(function()
                        Woodland.onSettingsChanged()
                        if touchmenu then touchmenu:updateItems() end
                    end)
                end,
            },
            {
                text = _("Remove from home screen"),
                help_text = _("Takes Woodland's pages out of SimpleUI's home screen. Do this before uninstalling, so no empty pages are left behind."),
                callback = function()
                    local Layout = require("woodland_journal/layout")
                    local ok1, gone1 = pcall(Layout.remove, GOODREADS)
                    local ok2, gone2 = pcall(Layout.remove, JOURNAL)
                    local removed = (ok1 and gone1) or (ok2 and gone2)
                    UIManager:show(require("ui/widget/infomessage"):new{ timeout=5, text = removed
                        and _("Woodland Journal's pages were removed from the home screen. Set up Woodland Journal puts them back.")
                        or _("Woodland Journal is not on the home screen.") })
                end,
            },
            {
                text = _("About Woodland Journal"),
                keep_menu_open = true,
                callback = function() Setup.about(self) end,
            },
        },
    }
end

Woodland.JOURNAL, Woodland.GOODREADS = JOURNAL, GOODREADS
Woodland.registry = registry
return Woodland
