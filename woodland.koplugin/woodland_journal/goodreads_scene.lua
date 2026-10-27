-- Goodreads shelf page in Woodland's visual language. Height follows the
-- space SimpleUI offers; covers grow to fill it, six to a page.
local M = { width=1000, height=1200, page_size=6 }
local MARGIN, RIGHT = 40, 960

function M.heightFor(aspect)
    return math.max(1000, math.floor(M.width * (aspect or 1.2)))
end

function M.build(shelf, page, updated, aspect)
    local height = M.heightFor(aspect)
    local scene = { width=M.width, height=height, items={}, targets={}, color_refresh=true }
    local function item(t) scene.items[#scene.items+1] = t; return t end
    local function text(s, x, y, w, size, font, color, align)
        return item{ kind="text", text=s, x=x, y=y, w=w, size=size, font=font or "ui",
            color=color or "ink", align=align or "left" }
    end
    local function button(label, x, y, w, h, action)
        item{ kind="frame", x=x, y=y, w=w, h=h, color="moss", stroke=3, radius=10 }
        text(label, x + 8, y, w - 16, 24, "ui_bold", "ink", "center").box_h = h
        scene.targets[#scene.targets+1] = { x=x, y=y, w=w, h=h, action=action }
    end
    local books = shelf.books or {}
    local pages = math.max(1, math.ceil(#books / M.page_size))
    page = math.max(1, math.min(page, pages))

    text(shelf.label or "Goodreads", MARGIN, 4, RIGHT - MARGIN, 40, "display")
    local count = #books == 1 and "1 book" or (#books .. " books")
    local saved = updated and os.date("saved %d %b %Y, %H:%M", updated):gsub(" 0", " ") or "not yet saved"
    text("Goodreads shelf, " .. count .. ", " .. saved, MARGIN, 62, RIGHT - MARGIN, 20, "ui", "ink2")
    local bw = (RIGHT - MARGIN - 40) / 3
    button("Change shelf", MARGIN, 104, bw, 68, "shelves")
    button("Refresh", MARGIN + bw + 20, 104, bw, 68, "sync")
    button("Woodland home", MARGIN + 2 * (bw + 20), 104, bw, 68, "home")

    local footer = height - 78
    local top, bottom = 104 + 68 + 30, footer - 26
    local row_gap = 26
    local row_h = (bottom - top - row_gap) / 2
    local column = (RIGHT - MARGIN) / 3
    local cover_h = math.max(150, row_h - 98)
    local cover_w = math.min(column - 40, cover_h * 2 / 3)
    for i = (page - 1) * M.page_size + 1, math.min(page * M.page_size, #books) do
        local b = books[i]
        local slot = i - (page - 1) * M.page_size - 1
        local col, row = slot % 3, math.floor(slot / 3)
        local x, y = MARGIN + col * column, top + row * (row_h + row_gap)
        item{ kind="cover", file=b.id, title=b.title, x=x + (column - cover_w) / 2, y=y, w=cover_w, h=cover_h,
            center=true, frame=true }
        item{ kind="stack", x=x + 8, y=y + cover_h + 10, w=column - 16, h=row_h - cover_h - 10, valign="top", blocks={
            { text=b.title or "", font="ui_bold", size=21, max_lines=2, align="center" },
            { text=b.author or "", font="ui", size=19, color="ink2", max_lines=1, align="center", gap=2 },
        } }
        scene.targets[#scene.targets+1] = { x=x, y=y, w=column, h=row_h, action="book", book=b }
    end
    if #books == 0 then
        item{ kind="stack", x=MARGIN + 60, y=top + 120, w=RIGHT - MARGIN - 120, h=200, valign="top", blocks={
            { text="This shelf has no saved books.", font="display", size=32, align="center", max_lines=2 },
            { text="Connect to Wi-Fi and choose Refresh to fetch it.", font="ui", size=22, color="ink2",
                align="center", max_lines=2, gap=12 },
        } }
    end
    if page > 1 then button("‹ Previous", MARGIN, footer, 260, 72, "previous") end
    text("Page " .. page .. " of " .. pages, MARGIN + 280, footer, RIGHT - MARGIN - 560, 22, "ui", "ink2", "center").box_h = 72
    if page < pages then button("Next ›", RIGHT - 260, footer, 260, 72, "next") end
    return scene, page, pages
end

local function stars(n)
    n = math.max(0, math.min(5, math.floor((n or 0) + 0.5)))
    return string.rep("★", n) .. string.rep("☆", 5 - n)
end

-- One book from a Goodreads shelf: large cover, the facts the shelf feed
-- carries, and the publisher's description. opts: shelf_label, on_kobo, aspect.
function M.buildBook(book, opts)
    opts = opts or {}
    local height = M.heightFor(opts.aspect)
    local scene = { width=M.width, height=height, items={}, targets={}, color_refresh=true }
    local function item(t) scene.items[#scene.items+1] = t; return t end
    local function button(label, x, y, w, h, action)
        item{ kind="frame", x=x, y=y, w=w, h=h, color="moss", stroke=3, radius=10 }
        item{ kind="text", text=label, x=x + 8, y=y, w=w - 16, size=24, font="ui_bold", color="ink",
            align="center", box_h=h }
        scene.targets[#scene.targets+1] = { x=x, y=y, w=w, h=h, action=action }
    end

    button("‹ Back to shelf", MARGIN, 8, 300, 68, "back")
    if opts.on_kobo then button("Open on this Kobo", RIGHT - 330, 8, 330, 68, "open") end

    local top, cover_w = 112, 330
    local cover_h = math.floor(cover_w * 1.5)
    item{ kind="cover", file=book.id, title=book.title, x=MARGIN, y=top, w=cover_w, h=cover_h,
        center=true, frame=true }

    local facts = {}
    local edition = {}
    if book.published then edition[#edition+1] = book.published end
    if book.pages then edition[#edition+1] = book.pages .. " pages" end
    if #edition > 0 then facts[#facts+1] = table.concat(edition, " · ") end
    if book.average then facts[#facts+1] = string.format("%s  %.2f on Goodreads", stars(book.average), book.average) end
    if book.rating then facts[#facts+1] = stars(book.rating) .. "  your rating" end
    local dates = {}
    if book.added then dates[#dates+1] = "added " .. book.added end
    if book.read_at then dates[#dates+1] = "read " .. book.read_at end
    if #dates > 0 then facts[#facts+1] = (dates[1]:gsub("^%l", string.upper)) .. (dates[2] and (" · " .. dates[2]) or "") end
    facts[#facts+1] = "On your shelf “" .. (opts.shelf_label or "Goodreads") .. "”"
    if opts.on_kobo then facts[#facts+1] = "Also on this Kobo" end

    -- "Title: Subtitle" (or "Title (Series #2)") sets the subtitle smaller, in italics.
    local title = book.title or ""
    local main, sub = title:match("^(.-):%s+(.+)$")
    if not main then main, sub = title:match("^(.-)%s+(%b())$") end
    local blocks = { { text=main or title, font="display", size=40, max_lines=3 } }
    if sub then blocks[2] = { text=sub, font="display_italic", size=25, color="ink2", max_lines=3, gap=6 } end
    blocks[#blocks+1] = { text=book.author or "", font="ui", size=24, color="ink2", max_lines=2, gap=12 }
    for i, line in ipairs(facts) do
        blocks[#blocks+1] = { text=line, font="ui", size=21, color="ink", max_lines=2, gap=i == 1 and 26 or 10,
            optional=i > 2 }
    end
    local col = MARGIN + cover_w + 36
    item{ kind="stack", x=col, y=top, w=RIGHT - col, h=cover_h, valign="top", blocks=blocks }

    local rule_y = top + cover_h + 30
    item{ kind="rect", x=MARGIN, y=rule_y, w=RIGHT - MARGIN, h=2, color="rule" }
    local body_y = rule_y + 24
    local footer = height - 78
    local text = book.description or ""
    local review = book.review ~= "" and book.review or nil
    if review then
        -- Your own words come first: up to five lines, the rest in the full view.
        local lines = 0
        for para in (review .. "\n"):gmatch("(.-)\n") do lines = lines + math.max(1, math.ceil(#para / 85)) end
        local h = 56 + math.min(5, lines) * 30 + 24
        item{ kind="stack", x=MARGIN, y=body_y, w=RIGHT - MARGIN, h=h, valign="top", blocks={
            { text="Your review", font="display", size=28, max_lines=1 },
            { text=review, font="ui_italic", size=21, max_lines=5, gap=8 },
        } }
        scene.targets[#scene.targets+1] = { x=MARGIN, y=body_y, w=RIGHT - MARGIN, h=h, action="description" }
        body_y = body_y + h
    end
    local long = #text > 700 or (review and #review > 400)
    if text == "" and not review then
        local missing = book.pages == nil and book.average == nil
        item{ kind="stack", x=MARGIN, y=body_y, w=RIGHT - MARGIN, h=footer - body_y - 20, valign="top", blocks={
            { text=missing and "No description saved yet." or "Goodreads has no description for this book.",
                font="display", size=28, max_lines=2 },
            missing and { text="Connect to Wi-Fi and choose Refresh on the shelf page to fetch descriptions, "
                .. "page counts and ratings for this shelf.", font="ui", size=21, color="ink2", max_lines=4, gap=12 } or nil,
        } }
    elseif text ~= "" then
        item{ kind="text", text="About this book", x=MARGIN, y=body_y, w=RIGHT - MARGIN, size=28, font="display" }
        local box_y = body_y + 56
        local box_h = (long and footer - 20 or footer + 60) - box_y
        item{ kind="text", text=text, x=MARGIN, y=box_y, w=RIGHT - MARGIN, h=box_h, size=21, font="ui",
            line_height=0.3 }
        scene.targets[#scene.targets+1] = { x=MARGIN, y=box_y, w=RIGHT - MARGIN, h=box_h, action="description" }
    end
    if long then button("Read the full description", MARGIN + 220, footer, RIGHT - MARGIN - 440, 72, "description") end
    return scene
end

return M
