-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Native KOReader renderer. No browser, raster template or network dependency.
local Device = require("device")
local Screen = Device.screen
local BB = require("ffi/blitbuffer")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local TextWidget = require("ui/widget/textwidget")
local TextBoxWidget = require("ui/widget/textboxwidget")
local logger = require("logger")
local gettext = require("gettext")
local Widget = InputContainer:extend{}

local function round(n) return math.floor(n + 0.5) end

-- Display serif for headings and the quote; Noto Serif for small text, whose
-- large x-height and lining figures stay legible on e-ink. Alegreya ships with
-- this Kobo's KOReader fonts; Noto Serif is the fallback for every role.
local FONTS = {
    display = { "Alegreya-Bold.ttf", "NotoSerif-Bold.ttf" },
    display_italic = { "Alegreya-Italic.ttf", "NotoSerif-Italic.ttf" },
    ui = { "NotoSerif-Regular.ttf" },
    ui_bold = { "NotoSerif-Bold.ttf" },
    ui_italic = { "NotoSerif-Italic.ttf", "NotoSerif-Regular.ttf" },
}
local font_scale
local function face(role, px)
    font_scale = font_scale or Screen:scaleBySize(1000) / 1000
    for _, name in ipairs(FONTS[role] or FONTS.ui) do
        local ok, value = pcall(Font.getFace, Font, name, px / font_scale)
        if ok and value then return value end
    end
    return Font:getFace("cfont", px / font_scale)
end

-- Text stays black or dark grey: Kaleido colour has half the resolution of
-- the black layer, so colour is used only for fills, rings, bars and art.
local function palette(monochrome)
    local color = not monochrome and Screen:isColorEnabled()
    local function ink(r, g, b)
        if color then return BB.ColorRGB32(r, g, b, 255) end
        return BB.Color8(math.floor(0.299*r + 0.587*g + 0.114*b + 0.5))
    end
    return {
        background=BB.COLOR_WHITE, on_accent=BB.COLOR_WHITE,
        ink=BB.COLOR_BLACK, ink2=BB.Color8(0x48), rule=BB.Color8(0x99), track=BB.Color8(0xD4),
        moss=ink(46, 107, 63), ochre=ink(185, 138, 46), rust=ink(180, 71, 58),
        sky=ink(61, 126, 166), bark=ink(122, 86, 52),
    }
end

-- Integer line rasterisation uses only BlitBuffer's stable paintRect API.
local function line(bb, x0, y0, x1, y1, width, color)
    x0, y0, x1, y1 = round(x0), round(y0), round(x1), round(y1)
    local dx, dy = math.abs(x1-x0), -math.abs(y1-y0)
    local sx, sy = x0 < x1 and 1 or -1, y0 < y1 and 1 or -1
    local err = dx + dy
    local half = math.floor(width / 2)
    while true do
        bb:paintRectRGB32(x0-half, y0-half, width, width, color)
        if x0 == x1 and y0 == y1 then break end
        local e2 = 2 * err
        if e2 >= dy then err = err + dy; x0 = x0 + sx end
        if e2 <= dx then err = err + dx; y0 = y0 + sy end
    end
end

-- Horizontal inset of a rounded rectangle's edge on a given row.
local function inset(row, h, r)
    if r <= 0 then return 0 end
    local dy
    if row < r then dy = r - row - 0.5
    elseif row >= h - r then dy = row - (h - r) + 0.5
    else return 0 end
    return r - math.sqrt(math.max(0, r*r - dy*dy))
end

local function fillRounded(bb, x, y, w, h, r, color)
    r = math.min(r or 0, math.floor(math.min(w, h) / 2))
    if r <= 0 then bb:paintRectRGB32(x, y, w, h, color); return end
    for row = 0, h - 1 do
        local i = round(inset(row, h, r))
        bb:paintRectRGB32(x + i, y + row, w - 2*i, 1, color)
    end
end

local function strokeRounded(bb, x, y, w, h, r, s, color)
    r = math.min(r or 0, math.floor(math.min(w, h) / 2))
    local ir = math.max(0, r - s)
    for row = 0, h - 1 do
        local o = round(inset(row, h, r))
        local inner = row >= s and row < h - s
        if not inner then
            bb:paintRectRGB32(x + o, y + row, w - 2*o, 1, color)
        else
            local i = s + round(inset(row - s, h - 2*s, ir))
            bb:paintRectRGB32(x + o, y + row, math.max(1, i - o), 1, color)
            bb:paintRectRGB32(x + w - i, y + row, math.max(1, i - o), 1, color)
        end
    end
end

-- A refresh function that asks for a dithered colour refresh over the
-- dashboard. On MediaTek Kobo colour panels only dithered partial or full
-- refreshes use the Kaleido colour waveforms; SimpleUI repaints with "ui",
-- which stays greyscale. The first paint of a freshly built dashboard uses a
-- flashing "full" refresh, which also clears ghosts of the previous screen;
-- later repaints use a non-flashing no-merge partial. It runs after painting
-- and does nothing unless a refresh already queued for this repaint overlaps
-- the dashboard, so the status-bar clock tick never triggers a colour pass.
function Widget.colourRefresh(region, UIManager, first)
    return function()
        local stack = UIManager._refresh_stack
        if type(stack) == "table" then
            local overlap = 0
            for _, refresh in ipairs(stack) do
                local r = refresh.region
                if r then
                    local w = math.min(r.x + r.w, region.x + region.w) - math.max(r.x, region.x)
                    local h = math.min(r.y + r.h, region.y + region.h) - math.max(r.y, region.y)
                    if w > 0 and h > 0 then overlap = overlap + w * h end
                end
            end
            if overlap == 0 then return end
        end
        return first and "full" or "[partial]", region, true
    end
end

function Widget:textWidget(spec, width, height)
    local f = self.factor
    local px = spec.size * f
    local color = self.colors[spec.color or "ink"] or self.colors.ink
    if height then
        return TextBoxWidget:new{ text=spec.text, face=face(spec.font, px), width=width, height=height,
            height_overflow_show_ellipsis=true, line_height=spec.line_height or 0.18,
            alignment=spec.align or "left", fgcolor=color, bgcolor=self.colors.background }
    end
    return TextWidget:new{ text=spec.text, face=face(spec.font, px), max_width=width, fgcolor=color }
end

-- Lays out a vertical stack of text blocks by their measured heights.
-- Blocks are capped at max_lines; optional blocks are dropped from the end
-- when the stack would not fit; valign places the stack in its box.
function Widget:buildStack(item)
    local f = self.factor
    local width, box_h = round(item.w * f), round(item.h * f)
    local entries = {}
    for _, block in ipairs(item.blocks) do
        local entry = { block=block, gap=round((block.gap or 0) * f) }
        if block.runs then
            entry.runs, entry.w, entry.h = {}, 0, 0
            for _, run in ipairs(block.runs) do
                local w = TextWidget:new{ text=run.text, face=face(run.font, run.size * f),
                    fgcolor=self.colors[run.color or "ink"] or self.colors.ink }
                local size = w:getSize()
                entry.runs[#entry.runs+1] = w
                entry.w, entry.h = entry.w + size.w, math.max(entry.h, size.h)
            end
            if entry.w > width then
                -- Keep attribution on one line: shrink the last run to fit.
                local last, run = entry.runs[#entry.runs], block.runs[#block.runs]
                local others = entry.w - last:getSize().w
                last:free()
                last = TextWidget:new{ text=run.text, face=face(run.font, run.size * f),
                    max_width=math.max(1, width - others), fgcolor=self.colors[run.color or "ink"] or self.colors.ink }
                entry.runs[#entry.runs] = last
                entry.w = others + last:getSize().w
            end
        else
            local widget = TextBoxWidget:new{ text=block.text, face=face(block.font, block.size * f), width=width,
                line_height=0.18, alignment=block.align or "left",
                fgcolor=self.colors[block.color or "ink"] or self.colors.ink, bgcolor=self.colors.background }
            local lines = #(widget.vertical_string_list or {})
            if block.max_lines and lines > block.max_lines then
                local h = block.max_lines * widget.line_height_px
                widget:free()
                widget = TextBoxWidget:new{ text=block.text, face=face(block.font, block.size * f), width=width,
                    height=h, height_overflow_show_ellipsis=true, line_height=0.18,
                    alignment=block.align or "left",
                    fgcolor=self.colors[block.color or "ink"] or self.colors.ink, bgcolor=self.colors.background }
                entry.truncated = true
            end
            entry.widget, entry.h, entry.w = widget, widget:getSize().h, width
        end
        entries[#entries+1] = entry
    end
    local function total()
        local sum = 0
        for i, e in ipairs(entries) do sum = sum + e.h + (i > 1 and e.gap or 0) end
        return sum
    end
    while total() > box_h and #entries > 1 and entries[#entries].block.optional do
        local e = table.remove(entries)
        if e.widget then e.widget:free() end
    end
    local y = 0
    local spare = math.max(0, box_h - total())
    if item.valign == "center" then y = round(spare / 2)
    elseif item.valign == "bottom" then y = spare end
    for i, e in ipairs(entries) do
        if i > 1 then y = y + e.gap end
        e.y = y
        y = y + e.h
    end
    item.overflow = total() > box_h
    return { entries=entries, width=width }
end

function Widget:init()
    self.factor = self.width / self.scene.width
    if self.max_height then self.factor = math.min(self.factor, self.max_height / self.scene.height) end
    self.inset = round((self.width - self.scene.width * self.factor) / 2)
    self.dimen = Geom:new{ w=self.width, h=round(self.scene.height * self.factor) }
    self.colors = palette(self.scene.monochrome)
    self.color_refresh = self.scene.color_refresh and not self.scene.monochrome
        and Screen:isColorEnabled() and Device.hasKaleidoWfm and Device:hasKaleidoWfm()
    self.children = {}
    self.ges_events.WoodlandTap = { GestureRange:new{ ges="tap", range=self.dimen } }
    local f = self.factor
    for _, item in ipairs(self.scene.items) do
        local child
        if item.kind == "text" then
            child = self:textWidget(item, round(item.w * f), item.h and round(item.h * f))
        elseif item.kind == "stack" then
            child = self:buildStack(item)
        elseif item.kind == "art" then
            local ok, value = pcall(function()
                return require("ui/widget/imagewidget"):new{ file=item.file, alpha=true,
                    width=round(item.w * f), height=round(item.h * f), scale_factor=0 }
            end)
            if ok then child = value else logger.warn("woodland: artwork unavailable", item.file) end
        elseif item.kind == "cover" then
            if self.book_helpers then
                local ok, cover = pcall(self.book_helpers.getBookCover, item.file,
                    round(item.w * f), round(item.h * f))
                if ok then child = cover end
            end
            if not child and self.book_helpers and self.book_helpers.coverPlaceholder then
                -- SimpleUI's generated cover, matching its other modules.
                local ok, cover = pcall(self.book_helpers.coverPlaceholder, item.title or "",
                    item.authors, round(item.w * f), round(item.h * f))
                if ok then child = cover end
            end
            if not child then
                child = TextBoxWidget:new{ text=item.title or "", face=face("ui_bold", 18 * f),
                    width=round((item.w - 16) * f), height=round((item.h - 24) * f),
                    height_overflow_show_ellipsis=true, alignment="center",
                    fgcolor=self.colors.ink2, bgcolor=self.colors.background }
                item.placeholder = true
            end
        end
        if child then
            self.children[item] = child
            if item.clock_date then self.clock_date_widget, self.clock_date_item = child, item end
        end
    end
end

-- With the time shown in the header, a minute tick updates only that label
-- and refreshes only its region. Never paint over sleep images or a parked
-- dashboard, and cancel the timer when this widget frees.
function Widget:startClock()
    if not (self.scene.show_time and self.clock_date_widget) then return end
    local UIManager = require("ui/uimanager")
    self._clock_tick = function()
        if self._freed then return end
        local screen = self.ctx and self.ctx._screen_widget
        if not Device.screen_saver_mode and screen and not screen._parked then
            self.clock_date_widget:setText(require("woodland_journal/scene").dateText(os.time(), true))
            local item, f = self.clock_date_item, self.factor
            local region = Geom:new{ x=self.dimen.x + self.inset + round(item.x * f),
                y=self.dimen.y + round(item.y * f), w=round(item.w * f), h=self.clock_date_widget:getSize().h }
            self._clock_only = true
            UIManager:setDirty(screen, function() return "ui", region end)
        end
        if not self._freed then UIManager:scheduleIn(60 - tonumber(os.date("%S")), self._clock_tick) end
    end
    UIManager:scheduleIn(60 - tonumber(os.date("%S")), self._clock_tick)
end

function Widget:paintItem(bb, x, y, item)
    local f, c = self.factor, self.colors
    local child = self.children[item]
    if item.kind == "rect" and item.w > 0 and item.h > 0 then
        fillRounded(bb, x + round(item.x * f), y + round(item.y * f),
            math.max(1, round(item.w * f)), math.max(1, round(item.h * f)), round((item.radius or 0) * f), c[item.color])
    elseif item.kind == "frame" then
        strokeRounded(bb, x + round(item.x * f), y + round(item.y * f), round(item.w * f), round(item.h * f),
            round((item.radius or 0) * f), math.max(1, round((item.stroke or 1) * f)), c[item.color])
    elseif item.kind == "dash" then
        local px, stop = x + round(item.x * f), x + round((item.x + item.w) * f)
        local dash, space = math.max(2, round(item.dash * f)), math.max(2, round(item.space * f))
        while px < stop do
            bb:paintRectRGB32(px, y + round(item.y * f), math.min(dash, stop - px), math.max(1, round(item.h * f)), c[item.color])
            px = px + dash + space
        end
    elseif item.kind == "rings" then
        -- Cache the drawn rings, which do not change between repaints.
        local side = round((item.r * 2 + 24) * f)
        if not self.ring_buffer then
            self.ring_buffer = BB.new(side, side, bb:getType())
            self.ring_buffer:fill(c.background)
            local origin, radius = side / 2, item.r * f
            for _, ring in ipairs(item.rings.rings) do
                local pts = ring.points
                for i = 2, #pts do
                    local a, b = pts[i-1], pts[i]
                    line(self.ring_buffer, origin + a.x * radius, origin + a.y * radius,
                        origin + b.x * radius, origin + b.y * radius,
                        math.max(1, round((b.complete and 4.4 or 1.8) * f)), b.complete and c.moss or c.ochre)
                end
            end
            local bark = item.rings.bark
            for i = 2, #bark do
                local a, b = bark[i-1], bark[i]
                line(self.ring_buffer, origin + a.x * radius, origin + a.y * radius,
                    origin + b.x * radius, origin + b.y * radius, math.max(2, round(5 * f)), c.bark)
            end
        end
        bb:blitFrom(self.ring_buffer, x + round(item.x * f - side / 2), y + round(item.y * f - side / 2), 0, 0, side, side)
    elseif item.kind == "stack" and child then
        local bx, by = x + round(item.x * f), y + round(item.y * f)
        for _, e in ipairs(child.entries) do
            if e.runs then
                local align = e.block.align or "left"
                local rx = bx + (align == "center" and round((child.width - e.w) / 2) or align == "right" and child.width - e.w or 0)
                for _, run in ipairs(e.runs) do
                    run:paintTo(bb, rx, by + e.y + e.h - run:getSize().h)
                    rx = rx + run:getSize().w
                end
            else
                e.widget:paintTo(bb, bx, by + e.y)
            end
        end
    elseif child then
        local cx, cy = x + round(item.x * f), y + round(item.y * f)
        if item.placeholder then
            local cw, ch = round(item.w * f), round(item.h * f)
            bb:paintRectRGB32(cx, cy, cw, ch, c.background)
            strokeRounded(bb, cx, cy, cw, ch, 0, math.max(1, round(2 * f)), c.rule)
            cx, cy = cx + round(8 * f), cy + round(12 * f)
        elseif item.kind == "cover" and item.center then
            -- Fit-scaled covers: centre horizontally, sit on the box's base.
            local size = child:getSize()
            cx = cx + round((item.w * f - size.w) / 2)
            cy = cy + round(item.h * f - size.h)
            child:paintTo(bb, cx, cy)
            if item.frame then strokeRounded(bb, cx, cy, size.w, size.h, 0, math.max(1, round(1.5 * f)), c.rule) end
            return
        elseif item.kind == "text" and not item.h then
            local size = child:getSize()
            if item.align == "center" then cx = cx + round((item.w * f - size.w) / 2)
            elseif item.align == "right" then cx = cx + round(item.w * f - size.w) end
            if item.box_h then cy = cy + round((item.box_h * f - size.h) / 2) end
            if item.swatch then
                -- A dashed key drawn just before the measured text.
                local s = item.swatch
                local sw, sx = round(s.w * f), cx - round((s.w + s.gap) * f)
                local sy = cy + round(size.h / 2 - s.h * f / 2)
                local dash, space = round(s.dash * f), round(s.space * f)
                local px = sx
                while px < sx + sw do
                    bb:paintRectRGB32(px, sy, math.min(dash, sx + sw - px), math.max(1, round(s.h * f)), c[s.color])
                    px = px + dash + space
                end
            end
        end
        child:paintTo(bb, cx, cy)
    end
end

function Widget:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    bb:paintRect(x, y, self.dimen.w, self.dimen.h, self.colors.background)
    for _, item in ipairs(self.scene.items) do self:paintItem(bb, x + self.inset, y, item) end
    if self.color_refresh and not self._clock_only then
        local UIManager = require("ui/uimanager")
        UIManager:setDirty(nil, Widget.colourRefresh(self.dimen:copy(), UIManager, not self._colour_shown))
        self._colour_shown = true
    end
    self._clock_only = nil
end

function Widget:onWoodlandTap(_, gesture)
    if not gesture or not gesture.pos then return false end
    local x = (gesture.pos.x - self.dimen.x - self.inset) / self.factor
    local y = (gesture.pos.y - self.dimen.y) / self.factor
    for i = #self.scene.targets, 1, -1 do
        local target = self.scene.targets[i]
        if x >= target.x and x <= target.x + target.w and y >= target.y and y <= target.y + target.h then
            if self.actions and self.actions[target.action] then
                self.actions[target.action](target)
            elseif target.action == "settings" then
                if self.ctx.open_settings_fn then self.ctx.open_settings_fn("woodland_journal") end
            elseif target.action == "library" then
                local UIManager = require("ui/uimanager")
                local Event = require("ui/event")
                UIManager:broadcastEvent(Event:new("SimpleUIGoLibrary"))
            elseif target.action == "goodreads" then
                -- The home page that holds the Goodreads module, wherever it was placed.
                local page = require("woodland_journal/layout").pageOf("woodland_goodreads")
                local screen = self.ctx and self.ctx._screen_widget
                if page and screen and screen._setPage then
                    screen:_setPage(page)
                else
                    require("ui/uimanager"):show(require("ui/widget/infomessage"):new{
                        text=gettext("Add Goodreads Bookshelves to a home-screen page of its own in SimpleUI's Arrange Modules.") })
                end
            elseif target.action == "goodreads_off" then
                require("ui/uimanager"):show(require("ui/widget/infomessage"):new{
                    text=gettext("Goodreads is off. To show your public Goodreads shelves, add your profile in Tools → Woodland Journal → Goodreads profile.") })
            elseif target.action == "quote" and target.quote then
                local q = target.quote
                require("ui/uimanager"):show(require("ui/widget/infomessage"):new{
                    text=q.q:gsub(" / ", "\n") .. "\n\n" .. q.a .. ", " .. q.b .. "\n" .. q.source })
            elseif target.file and self.ctx.open_fn then
                self.ctx.open_fn(target.file)
            end
            return true
        end
    end
    return false
end

function Widget:free()
    self._freed = true
    if self._clock_tick then require("ui/uimanager"):unschedule(self._clock_tick) end
    for item, child in pairs(self.children or {}) do
        if item.kind == "stack" then
            for _, e in ipairs(child.entries) do
                if e.widget then e.widget:free() end
                for _, run in ipairs(e.runs or {}) do run:free() end
            end
        elseif child.free then child:free() end
    end
    self.children = {}
    if self.ring_buffer then self.ring_buffer:free(); self.ring_buffer = nil end
end

return Widget
