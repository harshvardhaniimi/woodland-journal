-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Read-only adapter to SimpleUI and KOReader. No network or statistics writes.
local Model = require("woodland_journal/model")
local logger = require("logger")
local M = {}

function M.resolve(current, legacy)
    -- Resolve on each build: SimpleUI reloads modules across FM/Reader switches.
    local ok, result = pcall(require, current)
    if ok then return result end
    if legacy then
        ok, result = pcall(require, legacy)
        if ok then return result end
    end
end

-- Height a full-width Woodland page may use: SimpleUI's content area minus
-- the gap it places above the module (Config.getModuleGapPx), less 2 px.
function M.moduleHeight(ctx, mod_id)
    local Device = require("device")
    local UI = M.resolve("infra/sui_core", "sui_core")
    local Config = M.resolve("infra/sui_config", "sui_config")
    local screen = ctx and ctx._screen_widget
    local available = screen and screen._layout_content_h
        or UI and UI.getContentHeight and UI.getContentHeight()
        or Device.screen:getHeight()
    local gap = UI and UI.MOD_GAP or Device.screen:scaleBySize(23)
    if Config and Config.getModuleGapPx then
        local ok, value = pcall(Config.getModuleGapPx, mod_id, screen and screen._pfx or "simpleui_hs_", gap)
        if ok and tonumber(value) then gap = value end
    end
    return math.max(220, math.floor(available - gap - 2))
end

function M.week(conn, now)
    local days = Model.days(now)
    if not conn then return days, false end
    local ok, columns = pcall(conn.exec, conn, string.format([[
        SELECT date(start_time, 'unixepoch', 'localtime'),
               sum(min(duration, max(0, %d - start_time)))
        FROM page_stat_data
        WHERE start_time >= %d AND start_time <= %d AND duration > 0
        GROUP BY date(start_time, 'unixepoch', 'localtime')
    ]], now, days[1].start, now))
    if not ok then
        logger.warn("woodland: reading statistics unavailable", columns)
        return days, false
    end
    -- KOReader assigns a page interval to its start date; use the same policy.
    return Model.applyRows(days, columns), true
end

-- Latest saved positive reading interval across all books, independent of
-- the seven-day chart window. Clamp the end to now and ignore future rows.
function M.lastRead(conn, now)
    if not conn then return nil, false end
    local ok, columns = pcall(conn.exec, conn, string.format([[
        SELECT max(min(%d, start_time + duration))
        FROM page_stat_data
        WHERE start_time > 0 AND start_time <= %d AND duration > 0
    ]], now, now))
    if not ok then
        logger.warn("woodland: last reading time unavailable", columns)
        return nil, false
    end
    local value = columns and columns[1] and tonumber(columns[1][1])
    return value, true
end

local function book(SH, fp, prefetched)
    if not fp then return nil end
    local ok, data = pcall(SH.getBookData, fp, prefetched)
    if not ok or type(data) ~= "table" then return nil end
    data.file = fp
    data.percent = Model.clamp(data.percent, 0, 1)
    return data
end

function M.snapshot(ctx, settings, now)
    now = now or os.time()
    local SH = M.resolve("modules/module_books_shared", "desktop_modules/module_books_shared")
    local current = ctx.current_fp
    local recent, prefetched = ctx.recent_fps or {}, ctx.prefetched or {}
    if SH and not current then
        local ok, state = pcall(SH.prefetchBooks, true, true, 12)
        if ok and state then
            current, recent = state.current_fp, state.recent_fps or {}
            prefetched = state.prefetched_data or {}
        end
    end
    -- Sleep rendering can happen with the document still open. Prefer its live
    -- progress over a sidecar snapshot that may precede the current session.
    local RUI = package.loaded["apps/reader/readerui"]
    local reader = RUI and RUI.instance
    if reader and reader.document and reader.document.file then current = reader.document.file end
    local current_book = SH and book(SH, current, prefetched[current]) or nil
    if current_book and reader and reader.document and reader.document.file == current then
        local ok, percent = pcall(function()
            local controller = reader.rolling or reader.paging
            return controller and controller:getLastPercent()
        end)
        if ok and percent then current_book.percent = Model.clamp(percent, 0, 1) end
    end
    -- KOReader dates the finish (and any later status change) in the
    -- sidecar's summary.
    if Model.finished(current_book) and current_book.status == "complete" and SH.sidecarData then
        local ok, sidecar = pcall(SH.sidecarData, current)
        local summary = ok and sidecar and sidecar.summary
        current_book.finished_on = type(summary) == "table"
            and Model.shortDate(summary.date_finished or summary.modified) or nil
    end

    local conn, owned = ctx.db_conn, false
    if not conn then
        local ok, db = pcall(function()
            local path = require("datastorage"):getSettingsDir() .. "/statistics.sqlite3"
            local connection = require("lua-ljsqlite3/init").open(path, "ro")
            connection:set_busy_timeout(100)
            return connection
        end)
        if ok then conn, owned = db, true end
    end
    local days, available = M.week(conn, now)
    local last_read, last_read_available = M.lastRead(conn, now)
    local stats = ctx.stats
    if not stats then
        local SP = M.resolve("modules/module_stats_provider", "desktop_modules/module_stats_provider")
        if SP and SP.get then
            local ok, value = pcall(SP.get, conn, os.date("%Y", now), true)
            if ok then stats = value end
        end
    end
    if owned then pcall(conn.close, conn) end

    local others, seen = {}, {[current or ""] = true}
    if SH then
        for _, fp in ipairs(recent) do
            if not seen[fp] then
                seen[fp] = true
                local candidate = book(SH, fp, prefetched[fp])
                if candidate and candidate.percent > 0 and candidate.percent < 1
                        and candidate.status ~= "complete" and candidate.status ~= "abandoned" then
                    others[#others+1] = candidate
                    if #others == 2 then break end
                end
            end
        end
    end
    local battery
    local Device = require("device")
    pcall(function() battery = Device:getPowerDevice():getCapacity() end)
    return {
        now=now, name=settings.name or "", goal=settings.goal or 30,
        monochrome=settings.monochrome == true, show_time=settings.show_time == true,
        color_refresh=settings.color_refresh ~= false, goodreads=settings.goodreads == true,
        current=current_book, others=others, days=days, available=available,
        last_read=last_read, last_read_available=last_read_available,
        streak=available and stats and stats.streak or nil,
        books_year=stats and stats.books_year or nil,
        battery=battery,
    }, SH
end

return M
