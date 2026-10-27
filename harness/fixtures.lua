-- Edge-case scenarios for the Woodland harness. Each receives the real
-- snapshot built from the sandboxed device data and returns a variant.
local function copy(t)
    if type(t) ~= "table" then return t end
    local r = {}
    for k, v in pairs(t) do r[k] = copy(v) end
    return r
end
local function at(data, hour)
    local d = os.date("*t", data.now)
    d.hour, d.min = hour, 20
    data.now = os.time(d)
    return data
end
local function week(data, minutes)
    for i, day in ipairs(data.days) do day.seconds = (minutes[i] or 0) * 60 end
    return data
end
return {
    -- Swap the current book with the first book in progress: the reading hero.
    employees = function(data)
        data = at(data, 9)
        local others = data.others
        if others[1] then data.current, others[1] = others[1], data.current end
        week(data, { 0, 5, 0, 22, 31, 4, 12 })
        data.streak, data.books_year = 3, 4
        return data
    end,
    -- Long title and authors, high progress, a heavy reading week and big goal.
    long = function(data)
        data = at(data, 15)
        data.current = copy(data.current)
        data.current.title = "The Life and Strange Surprizing Adventures of Robinson Crusoe, of York, Mariner"
        data.current.authors = "Daniel Defoe\nwith a foreword by Somebody Unusually Long-Named"
        data.current.percent, data.current.pages, data.current.avg_time = 0.87, 3298, 41
        data.current.status = nil
        data.goal = 600
        week(data, { 610, 125, 0.5, 45, 600, 1, 333 })
        data.streak, data.books_year = 112, 21
        data.others[1] = copy(data.others[1])
        data.others[1].title = "The Rámáyan of Válmíki, translated into English verse by Ralph T. H. Griffith"
        data.others[1].percent = 0.009
        return data
    end,
    -- No reading in the last seven days, older last-read time.
    empty_week = function(data)
        data = at(data, 20)
        week(data, {})
        data.streak = 0
        data.last_read = data.now - 9 * 86400
        return data
    end,
    -- Statistics database unavailable.
    no_stats = function(data)
        week(data, {})
        data.available, data.streak, data.books_year = false, nil, nil
        data.last_read, data.last_read_available = nil, false
        return data
    end,
    -- Covers that cannot be extracted.
    no_covers = function(data)
        data.current = copy(data.current)
        data.current.file = "/nonexistent/Missing Cover Book.epub"
        data.current.title = "A Book Without Any Cover"
        for i, b in ipairs(data.others) do
            data.others[i] = copy(b)
            data.others[i].file = "/nonexistent/missing-" .. i .. ".epub"
        end
        return data
    end,
    -- First launch: nothing open and nothing else in progress.
    fresh = function(data)
        data = at(data, 7)
        data.current, data.others = nil, {}
        week(data, {})
        data.streak, data.books_year, data.last_read = 0, 0, nil
        return data
    end,
    -- An in-progress book marked finished at 62%: full rings and the finish
    -- date, with the remaining book in progress below.
    finished = function(data)
        data.current = copy(data.others[1] or data.current)
        data.current.percent, data.current.status, data.current.finished_on = 0.62, "complete", "26 Oct 2026"
        data.others = { data.others[2] }
        return data
    end,
    -- Finished with nothing else in progress.
    finished_alone = function(data)
        data.current = copy(data.current)
        data.current.percent, data.current.status = 1, "complete"
        data.others = {}
        return data
    end,
    -- Finished, with long titles and authors everywhere and no pages.
    finished_long = function(data)
        data.current = copy(data.current)
        data.current.title = "The Rámáyan of Válmíki, translated into English verse by Ralph T. H. Griffith"
        data.current.authors = "Valmiki\nRalph T. H. Griffith"
        data.current.percent, data.current.status, data.current.pages = 1, nil, nil
        data.current.finished_on = nil
        if data.others[1] then
            data.others[1] = copy(data.others[1])
            data.others[1].title = "Middlemarch: A Study of Provincial Life, with an Introduction and Notes"
        end
        return data
    end,
    -- Day N of the quote rotation (set by the plan), at noon.
    quote_day = function(data)
        data = at(data, 12)
        data.now = data.now + (rawget(_G, "WOODLAND_QUOTE_DAY") or 0) * 86400
        return data
    end,
    -- Time shown in the header (optional setting).
    with_time = function(data)
        data = at(data, 13)
        data.show_time = true
        return data
    end,
}
