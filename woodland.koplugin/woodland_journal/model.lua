-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Woodland Journal. Pure calculations; no device, database or UI dependencies.
local M = {}

function M.clamp(value, low, high)
    value = tonumber(value)
    if not value or value ~= value then return low end
    return math.max(low, math.min(high, value))
end

-- Calendar arithmetic (rather than subtracting 86400) preserves local dates
-- across daylight-saving changes. The Kobo's timezone is authoritative.
function M.days(now)
    local today = os.date("*t", now)
    local result = {}
    for offset = 6, 0, -1 do
        local noon = os.time{ year=today.year, month=today.month,
            day=today.day-offset, hour=12, min=0, sec=0 }
        local date = os.date("*t", noon)
        result[#result+1] = {
            key=os.date("%Y-%m-%d", noon), weekday=date.wday,
            day=date.day, month=date.month,
            start=os.time{year=date.year, month=date.month, day=date.day,
                hour=0, min=0, sec=0}, seconds=0,
        }
    end
    return result
end

function M.applyRows(days, columns)
    local by_date = {}
    for i, key in ipairs(columns and columns[1] or {}) do
        by_date[key] = math.max(0, tonumber(columns[2] and columns[2][i]) or 0)
    end
    for _, day in ipairs(days) do day.seconds = by_date[day.key] or 0 end
    return days
end

function M.minutes(seconds)
    if seconds == nil then return nil end
    seconds = math.max(0, tonumber(seconds) or 0)
    if seconds > 0 and seconds < 60 then return "<1" end
    return tostring(math.floor(seconds / 60 + 0.5))
end

-- "1 h 20 min", "45 min"; nil for unknown or non-positive input.
function M.duration(seconds)
    seconds = tonumber(seconds)
    if not seconds or seconds ~= seconds or seconds <= 0 then return nil end
    local minutes = math.max(1, math.floor(seconds / 60 + 0.5))
    local hours = math.floor(minutes / 60)
    minutes = minutes - hours * 60
    if hours == 0 then return minutes .. " min" end
    if minutes == 0 then return hours .. " h" end
    return hours .. " h " .. minutes .. " min"
end

-- Marked complete or read to the end: SimpleUI's own rule (SH.isFinished).
function M.finished(book)
    return book ~= nil and (book.status == "complete" or M.clamp(book.percent, 0, 1) >= 1)
end

-- "2026-10-23" -> "23 Oct 2026"; nil for anything else.
function M.shortDate(iso)
    local y, m, d = tostring(iso or ""):match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
    if not y then return nil end
    local t = os.time{ year=tonumber(y), month=tonumber(m), day=tonumber(d), hour=12 }
    return (os.date("%d %b %Y", t):gsub("^0", ""))
end

function M.plural(count, one, many)
    return string.format(count == 1 and one or many, count)
end

function M.seed(text)
    local value = 17
    for i = 1, #(text or "") do value = (value * 31 + text:byte(i)) % 65521 end
    return value
end

-- Ten irregular growth rings, one for each tenth of the book. Rings fill from
-- the heartwood outwards and the ring in progress fills clockwise from the
-- top, so 3% is a visible arc rather than a speck. The shape comes from the
-- book's identity (stable between visits); progress changes only the ink.
-- Coordinates are relative to the outer bark radius (1.0). No math.random.
M.HEARTWOOD = 0.37 -- clear centre reserved for the percentage

function M.rings(identity, progress, count, samples)
    count, samples = count or 10, samples or 200
    progress = M.clamp(progress, 0, 1)
    local seed = M.seed(identity or "woodland")
    local phase = seed / 65521 * 2 * math.pi
    -- Uneven ring widths, as in real wood: wide and narrow growth years.
    local widths, total = {}, 0
    for index = 1, count do
        local wobble = math.sin(seed * 0.013 * index + phase) * 0.5 + 0.5
        widths[index] = 0.7 + 0.6 * wobble
        total = total + widths[index]
    end
    local function contour(angle, amount)
        return 1 + amount * (0.045 * math.sin(3*angle + phase)
            + 0.026 * math.cos(5*angle - phase)
            + 0.012 * math.sin(11*angle + 2*phase))
    end
    local rings, radius = {}, M.HEARTWOOD
    local span = 0.88 - radius
    for index = 1, count do
        radius = radius + span * widths[index] / total
        local filled = M.clamp(progress * count - (index - 1), 0, 1)
        local points = {}
        for step = 0, samples do
            local t = step / samples
            local angle = t * math.pi * 2 - math.pi / 2
            local r = radius * contour(angle, 0.6 + 0.4 * index / count)
            points[#points+1] = { x=r * math.cos(angle), y=r * math.sin(angle),
                complete = filled > 0 and t <= filled }
        end
        rings[#rings+1] = { points=points, filled=filled }
    end
    local bark = {}
    for step = 0, samples do
        local angle = step / samples * math.pi * 2 - math.pi / 2
        local r = 0.95 * contour(angle, 1.15)
        bark[#bark+1] = { x=r * math.cos(angle), y=r * math.sin(angle) }
    end
    return { rings=rings, bark=bark, heartwood=M.HEARTWOOD }
end

return M
