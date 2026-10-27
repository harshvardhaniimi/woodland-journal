-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Woodland Journal home: a scene in 1000-unit-wide coordinates whose height
-- follows the space SimpleUI offers, so the dashboard fills it exactly.
-- Text is black for crisp e-ink; colour is kept to fills, rings and art.
local Model = require("woodland_journal/model")
local Quotes = require("woodland_journal/quotes")
local source = debug.getinfo(1, "S").source:sub(2)
local assets = (source:match("^(.*)/") or ".") .. "/assets/"
local M = { width = 1000, height = 1200 }

local MARGIN = 40
local RIGHT = M.width - MARGIN
-- Natural section heights; spare height becomes breathing room between them.
local HEADER, HERO, STATS, WEEK, SHELF, QUOTE = 92, 300, 86, 258, 182, 136
local GAPS = { 1, 1, 0.55, 1, 0.9 } -- stats and week form one group
local MIN_GAP = 14

function M.heightFor(aspect)
    local natural = HEADER + HERO + STATS + WEEK + SHELF + QUOTE + 8 + #GAPS * MIN_GAP
    return math.max(natural, math.floor(M.width * (aspect or 1.2)))
end

-- "Friday, 23 October 2026", optionally followed by ", 03:14".
function M.dateText(now, show_time)
    local date = os.date("%A, %d %B %Y", now):gsub(", 0", ", ")
    if show_time then date = date .. ", " .. os.date("%H:%M", now) end
    return date
end

function M.build(data, translate, aspect)
    local _ = translate or function(s) return s end
    local height = M.heightFor(aspect)
    local scene = { width = M.width, height = height, items = {}, targets = {},
        monochrome = data.monochrome, color_refresh = data.color_refresh ~= false,
        show_time = data.show_time }
    local function item(t) scene.items[#scene.items+1] = t; return t end
    local function target(x, y, w, h, spec)
        spec.x, spec.y, spec.w, spec.h = x, y, w, h
        scene.targets[#scene.targets+1] = spec
    end
    local function text(s, x, y, w, size, font, color, align)
        return item{ kind="text", text=s, x=x, y=y, w=w, size=size, font=font or "ui",
            color=color or "ink", align=align or "left" }
    end
    local function rect(x, y, w, h, color, radius)
        item{ kind="rect", x=x, y=y, w=w, h=h, color=color, radius=radius }
    end
    local function frame(x, y, w, h, color, stroke, radius)
        item{ kind="frame", x=x, y=y, w=w, h=h, color=color, stroke=stroke, radius=radius }
    end
    local function bar(x, y, w, h, fraction)
        rect(x, y, w, h, "track", h / 2)
        local filled = w * Model.clamp(fraction, 0, 1)
        if filled > 0 then rect(x, y, math.max(h, filled), h, "moss", h / 2) end
    end
    -- style: "filled", nil (outlined) or "muted" (an unavailable feature).
    local function button(label, x, y, w, h, spec, style)
        if style == "filled" or style == true then
            rect(x, y, w, h, "moss", 10)
        elseif style == "muted" then
            frame(x, y, w, h, "rule", 2, 10)
        else
            frame(x, y, w, h, "moss", 3, 10)
        end
        local color = (style == "filled" or style == true) and "on_accent" or style == "muted" and "ink2" or "ink"
        text(label, x + 8, y, w - 16, style == "muted" and 22 or 25, style == "muted" and "ui" or "ui_bold",
            color, "center").box_h = h
        target(x, y, w, h, spec)
    end
    local function cover(book, x, y, w, h)
        -- SimpleUI's cover helper draws its own border and shadow.
        item{ kind="cover", file=book.file, title=book.title, authors=book.authors, x=x, y=y, w=w, h=h }
        target(x, y, w, h, { file=book.file })
    end

    -- Vertical rhythm: fixed section heights, flexible gaps.
    local spare = height - (HEADER + HERO + STATS + WEEK + SHELF + QUOTE) - 8
    local weight = 0
    for _, g in ipairs(GAPS) do weight = weight + g end
    local gap = {}
    for i, g in ipairs(GAPS) do gap[i] = math.max(MIN_GAP, spare * g / weight) end
    local y_header = 4
    local y_hero = y_header + HEADER + gap[1]
    local y_stats = y_hero + HERO + gap[2]
    local y_week = y_stats + STATS + gap[3]
    local y_shelf = y_week + WEEK + gap[4]
    local y_quote = y_shelf + SHELF + gap[5]

    -- Header: greeting and the full date (the status bar carries the time).
    local hour = tonumber(os.date("%H", data.now))
    local greeting = hour < 5 and _("Hello") or hour < 12 and _("Good morning")
        or hour < 17 and _("Good afternoon") or _("Good evening")
    local name = tostring(data.name or ""):gsub("[\r\n]", " ")
    text(greeting .. (name ~= "" and ", " .. name or ""), MARGIN, y_header, 600, 46, "display")
    text(M.dateText(data.now, data.show_time), MARGIN, y_header + 63, 600, 22, "ui", "ink2").clock_date = true

    -- Hero: the current book, Continue reading and its tree rings; once the
    -- book is finished, a Finished badge, full rings and the library.
    local book = data.current
    local finished = Model.finished(book)
    local ring_r, ring_x = 150, RIGHT - 154
    local ring_y = y_hero + HERO / 2
    local column_x = MARGIN + 200 + 30
    local column_w = ring_x - ring_r - 24 - column_x
    local rings = Model.rings(book and (book.file or book.title) or "empty",
        finished and 1 or book and book.percent or 0)
    item{ kind="rings", x=ring_x, y=ring_y, r=ring_r, rings=rings }
    item{ kind="art", file=assets .. "robin.png", x=ring_x - 0.95 * ring_r * 0.47 - 52,
        y=ring_y - 0.95 * ring_r * 0.88 - 88, w=110, h=93 }
    if finished then
        cover(book, MARGIN, y_hero, 200, HERO)
        local badge_h = 44
        rect(column_x, y_hero, 200, badge_h, "moss", badge_h / 2)
        text(_("Book finished"), column_x + 10, y_hero, 180, 22, "ui_bold", "on_accent", "center").box_h = badge_h
        local title = book.title or ""
        local blocks = {
            { text=title, font="display", size=#title > 30 and 33 or 40, max_lines=2 },
            { text=(book.authors or ""):gsub("\n", ", "), font="ui", size=24, max_lines=1, gap=6 },
        }
        local meta = {}
        if book.finished_on then meta[#meta+1] = string.format(_("Finished %s"), book.finished_on) end
        if tonumber(book.pages) and book.pages > 0 then
            meta[#meta+1] = Model.plural(math.floor(book.pages), _("%d page"), _("%d pages"))
        end
        if #meta > 0 then
            blocks[#blocks+1] = { text=table.concat(meta, ", "), font="ui", size=19,
                color="ink2", max_lines=1, gap=8, optional=true }
        end
        local stack_y = y_hero + badge_h + 14
        item{ kind="stack", x=column_x, y=stack_y, w=column_w, h=y_hero + HERO - 78 - 16 - stack_y,
            valign="top", blocks=blocks }
        button(_("Open library"), column_x, y_hero + HERO - 78, math.min(330, column_w), 78,
            { action="library" }, true)
        target(ring_x - ring_r, ring_y - ring_r, 2 * ring_r, 2 * ring_r, { file=book.file })
        local pct = math.floor(Model.clamp(book.percent, 0, 1) * 100 + 0.5)
        text(pct .. "%", ring_x - 70, ring_y - 44, 140, 40, "display", "ink", "center").box_h = 56
        text(_("finished"), ring_x - 70, ring_y + 10, 140, 18, "ui", "ink2", "center").box_h = 28
    elseif book then
        cover(book, MARGIN, y_hero, 200, HERO)
        local title = book.title or ""
        local blocks = {
            { text=title, font="display", size=#title > 46 and 33 or 40, max_lines=3 },
            { text=(book.authors or ""):gsub("\n", ", "), font="ui", size=24, max_lines=2, gap=6 },
        }
        local meta = {}
        if tonumber(book.pages) and book.pages > 0 then
            meta[#meta+1] = Model.plural(math.floor(book.pages), _("%d page"), _("%d pages"))
        end
        local left = tonumber(book.avg_time) and tonumber(book.pages)
            and Model.duration(book.avg_time * book.pages * (1 - book.percent))
        if left and book.percent < 1 then meta[#meta+1] = string.format(_("about %s left"), left) end
        if #meta > 0 then
            blocks[#blocks+1] = { text=table.concat(meta, ", "), font="ui", size=19,
                color="ink2", max_lines=1, gap=8, optional=true }
        end
        item{ kind="stack", x=column_x, y=y_hero, w=column_w, h=HERO - 78 - 16, valign="top", blocks=blocks }
        button(_("Continue reading"), column_x, y_hero + HERO - 78, math.min(330, column_w), 78,
            { file=book.file }, true)
        target(ring_x - ring_r, ring_y - ring_r, 2 * ring_r, 2 * ring_r, { file=book.file })
        local pct = math.floor(Model.clamp(book.percent, 0, 1) * 100 + 0.5)
        text(pct .. "%", ring_x - 70, ring_y - 44, 140, 40, "display", "ink", "center").box_h = 56
        text(_("read"), ring_x - 70, ring_y + 10, 140, 18, "ui", "ink2", "center").box_h = 28
    else
        item{ kind="stack", x=MARGIN, y=y_hero + 30, w=ring_x - ring_r - 40 - MARGIN, h=HERO - 130,
            valign="top", blocks={
                { text=_("Your next chapter starts here"), font="display", size=40, max_lines=2 },
                { text=_("Open a book from your library to begin."), font="ui", size=24, max_lines=2, gap=10 },
            } }
        button(_("Open library"), MARGIN, y_hero + HERO - 78, 330, 78, { action="library" }, true)
        text(_("Begin"), ring_x - 70, ring_y - 28, 140, 34, "display", "ink", "center").box_h = 56
    end

    -- Today, streak and the year's finished books.
    local col_w = (RIGHT - MARGIN) / 3
    local today = data.available and data.days[7].seconds or nil
    local values = {
        { _("Today"), today and (Model.minutes(today) .. " / " .. data.goal .. " " .. _("min")) or "—" },
        { _("Streak"), data.streak and Model.plural(data.streak, _("%d day"), _("%d days")) or "—" },
        { string.format(_("Finished in %s"), os.date("%Y", data.now)),
            data.books_year and Model.plural(data.books_year, _("%d book"), _("%d books")) or "—" },
    }
    for i, v in ipairs(values) do
        local x = MARGIN + (i - 1) * col_w
        text(v[1], x, y_stats, col_w - 16, 21, "ui", "ink2")
        text(v[2], x, y_stats + 28, col_w - 16, 31, "ui_bold")
    end
    if today then bar(MARGIN, y_stats + 74, 250, 11, today / (data.goal * 60)) end
    target(MARGIN, y_stats - 8, RIGHT - MARGIN, STATS + 8, { action="settings" })

    -- This week: bars against the daily goal, minutes under every day.
    local chart_right = RIGHT
    local column = (chart_right - MARGIN) / 7
    local base = y_week + 40 + 110
    local total, highest = 0, data.goal * 60
    for _, day in ipairs(data.days) do
        total = total + day.seconds
        highest = math.max(highest, day.seconds)
    end
    text(_("This week"), MARGIN, y_week, 400, 21, "ui", "ink2")
    local legend = string.format(_("%d min daily goal"), data.goal)
    text(legend, RIGHT - 360, y_week, 360, 21, "ui", "ink2", "right").swatch =
        { w=48, h=3, color="ochre", dash=12, space=6, gap=12 }
    local goal_y = base - data.goal * 60 / highest * 110
    item{ kind="dash", x=MARGIN, y=goal_y - 1.5, w=chart_right - MARGIN, h=3, color="ochre", dash=12, space=9 }
    rect(MARGIN, base, chart_right - MARGIN, 2, "rule")
    local labels = { _("Sun"), _("Mon"), _("Tue"), _("Wed"), _("Thu"), _("Fri"), _("Sat") }
    for i, day in ipairs(data.days) do
        local x = MARGIN + (i - 1) * column
        local is_today = i == 7
        if data.available and day.seconds > 0 then
            local h = math.max(6, day.seconds / highest * 110)
            rect(x + (column - 52) / 2, base - h, 52, h, is_today and "rust" or "moss", 3)
        end
        text(labels[day.weekday], x, base + 10, column, 21, is_today and "ui_bold" or "ui",
            is_today and "ink" or "ink2", "center")
        local minutes = data.available and (Model.minutes(day.seconds) .. " " .. _("min")) or "—"
        text(minutes, x, base + 42, column, 20, "ui_bold", "ink", "center").daily_minutes = true
    end
    if not data.available then
        text(_("Reading statistics are unavailable."), MARGIN, base - 70, chart_right - MARGIN, 22,
            "ui", "ink2", "center")
    elseif total == 0 then
        text(_("No reading recorded in the last 7 days."), MARGIN, base - 52, chart_right - MARGIN, 22,
            "ui", "ink2", "center")
    end
    local last = data.last_read
        and _("Last read") .. " " .. os.date("%d %b %Y, %H:%M", data.last_read):gsub("^0", "")
        or data.last_read_available and _("No reading recorded yet") or _("Last read unavailable")
    text(last, MARGIN, base + 82, 560, 20, "ui", "ink2")
    if data.available and total > 0 then
        text(string.format(_("%s this week"), Model.duration(total) or "<1 min"),
            RIGHT - 340, base + 82, 340, 20, "ui", "ink2", "right")
    end

    -- Also reading, with the library and Goodreads one tap away.
    text(_("Also reading"), MARGIN, y_shelf, 400, 21, "ui", "ink2")
    local others = data.others or {}
    for i = 1, math.min(2, #others) do
        local b, x = others[i], MARGIN + (i - 1) * 305
        local y = y_shelf + 34
        cover(b, x, y, 92, 138)
        item{ kind="stack", x=x + 108, y=y, w=180, h=86, valign="top", blocks={
            { text=b.title or "", font="ui_bold", size=20, max_lines=3 },
        } }
        local pct = math.floor(Model.clamp(b.percent, 0, 1) * 100 + 0.5)
        text(pct .. "%", x + 108, y + 92, 180, 20, "ui", "ink2")
        bar(x + 108, y + 124, 170, 9, b.percent)
        target(x + 92, y, 196, 138, { file=b.file })
    end
    if #others == 0 then
        item{ kind="stack", x=MARGIN, y=y_shelf + 40, w=560, h=120, valign="top", blocks={
            { text=_("No other books in progress."), font="ui", size=22, color="ink2", max_lines=2 },
        } }
    end
    button(_("All books"), RIGHT - 300, y_shelf + 34, 300, 68, { action="library" })
    if data.goodreads then
        button(_("Goodreads shelves"), RIGHT - 300, y_shelf + 114, 300, 68, { action="goodreads" })
    else
        button(_("Goodreads not available"), RIGHT - 300, y_shelf + 114, 300, 68, { action="goodreads_off" }, "muted")
    end

    -- A daily quote in a small woodland clearing.
    local quote = Quotes.forDay(data.now)
    local quote_bottom = y_quote + QUOTE
    item{ kind="art", file=assets .. "flank-left.png", x=MARGIN - 22, y=quote_bottom - 112, w=150, h=112 }
    item{ kind="art", file=assets .. "flank-right.png", x=RIGHT - 92, y=quote_bottom - 132, w=107, h=132 }
    item{ kind="stack", x=MARGIN + 150, y=y_quote, w=RIGHT - MARGIN - 300, h=QUOTE, valign="center", blocks={
        { text="“" .. quote.q .. "”", font="display_italic", size=27, max_lines=3, align="center", quote=true },
        { runs={ { text=quote.a .. ", ", font="ui", size=19, color="ink2" },
                 { text=quote.b, font="ui_italic", size=19, color="ink2" } }, gap=8, align="center" },
    } }
    target(MARGIN + 150, y_quote, RIGHT - MARGIN - 300, QUOTE, { action="quote", quote=quote })
    return scene
end

return M
