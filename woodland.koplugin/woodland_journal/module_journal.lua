-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Woodland Journal: the home-screen dashboard, registered with SimpleUI by
-- woodland.koplugin/main.lua.
local _ = require("gettext")
local Device = require("device")
local Data = require("woodland_journal/data")
local Scene = require("woodland_journal/scene")
local Settings = require("woodland_journal/settings")
local M = {
    id="woodland_journal", name=_("Woodland Journal"),
    description=_("A reading dashboard with tree rings and daily minutes."),
    label=nil, enabled_key="woodland_journal", default_on=false,
    default_enabled=true, has_covers=true, is_book_mod=true, owns_chrome=true,
    needs={db=true,stats=true,books=true,recent=12},
}

-- The page holds SimpleUI's gap above the module plus the module itself, so
-- the dashboard may use everything else without an overflow warning.
local function heightLimit(ctx)
    return Data.moduleHeight(ctx, M.id)
end

function M.build(width,ctx)
    local Widget=require("woodland_journal/widget")
    local snapshot,helpers=Data.snapshot(ctx or {},Settings.snapshot())
    local max_height=heightLimit(ctx)
    local widget=Widget:new{width=math.floor(width),max_height=max_height,
        scene=Scene.build(snapshot,_,max_height/math.floor(width)),ctx=ctx or {},book_helpers=helpers}
    widget:startClock()
    return widget
end

function M.getHeight(ctx)
    local UI=Data.resolve("infra/sui_core","sui_core")
    local width=ctx and ctx.col_w or UI and UI.getInnerW and UI.getInnerW() or Device.screen:getWidth()
    local limit=heightLimit(ctx)
    return math.floor(math.min(limit,width*Scene.heightFor(limit/width)/Scene.width)+0.5)
end

-- No independent cache: each rebuild reads a bounded seven-day query. Native
-- SimpleUI owns statistics caching and its reading-session invalidation.
function M.invalidateCache() end
function M.refreshStats() end

function M.getMenuItems(menu)
    local UIManager=require("ui/uimanager")
    local function refresh() if menu.refresh then menu.refresh() end end
    return {
        {
            text=_("Reader name"), value_func=function()
                local name=Settings.name()
                return name~="" and name or _("none")
            end,
            callback=function()
                local InputDialog=require("ui/widget/inputdialog")
                local dialog
                dialog=InputDialog:new{title=_("Reader name"),input=Settings.name(),
                    description=_("Leave empty for a greeting without a name."),
                    buttons={{
                        {text=_("Cancel"),id="close",callback=function() UIManager:close(dialog) end},
                        {text=_("Save"),is_enter_default=true,callback=function()
                            Settings.setName(dialog:getInputText())
                            UIManager:close(dialog); refresh()
                        end},
                    }}}
                UIManager:show(dialog); dialog:onShowKeyboard()
            end,
        },
        {
            text=_("Daily reading goal"),
            value_func=function() return tostring(Settings.goal()).." ".._("min") end,
            callback=function()
                local SpinWidget=require("ui/widget/spinwidget")
                UIManager:show(SpinWidget:new{title_text=_("Daily reading goal (minutes)"),
                    value=Settings.goal(),value_min=1,value_max=600,value_step=5,
                    value_hold_step=30,default_value=30,ok_text=_("Save"),
                    callback=function(widget)
                        Settings.setGoal(widget.value)
                        refresh()
                    end})
            end,
        },
        {
            text=_("Show time in header"),checked_func=function() return Settings.showTime() end,
            callback=function()
                Settings.setShowTime(not Settings.showTime())
                refresh()
            end,
        },
        {
            text=_("Colour refresh"),checked_func=function() return Settings.colourRefresh() end,
            help_text=_("Kobo colour screens show colour only with a dithered refresh. Turn this off if the dashboard flickers."),
            callback=function()
                Settings.setColourRefresh(not Settings.colourRefresh())
                refresh()
            end,
        },
        {
            text=_("Ink"),
            sub_item_table={
                {
                    text=_("Automatic (follow the screen)"),
                    checked_func=function() return Settings.monochromeIsAutomatic() end,
                    callback=function() Settings.setMonochrome(nil); refresh() end,
                },
                {
                    text=_("Colour"),
                    checked_func=function() return not Settings.monochromeIsAutomatic() and not Settings.monochrome() end,
                    callback=function() Settings.setMonochrome(false); refresh() end,
                },
                {
                    text=_("Monochrome"),
                    checked_func=function() return not Settings.monochromeIsAutomatic() and Settings.monochrome() end,
                    callback=function() Settings.setMonochrome(true); refresh() end,
                },
            },
        },
    }
end

return M
