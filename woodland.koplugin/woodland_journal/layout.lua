-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Woodland's pages in SimpleUI's home-screen layout. Reads the layout SimpleUI
-- saves under "simpleui_layout" and changes only Woodland's own module ids,
-- saving them the way SimpleUI's layout editor does: the page list, the flat
-- module order and the module's enabled flag. Every other module and page is
-- left exactly as it was.
local M = {}

local LAYOUT_KEY, PFX = "simpleui_layout", "simpleui_hs_"

local function require_first(paths)
    for _i, path in ipairs(paths) do
        local ok, mod = pcall(require, path)
        if ok and type(mod) == "table" then return mod end
    end
end
local function store() return require_first{ "infra/sui_store", "sui_store" } end
local function registry() return require_first{ "modules/moduleregistry", "desktop_modules/moduleregistry" } end

local function entryId(entry)
    if type(entry) == "table" then return entry.id end
    return entry
end

-- SimpleUI's layout before anyone has arranged it: its module order, split
-- at page breaks, keeping enabled modules (as SimpleUI's editor computes it).
local function defaultLayout(Registry)
    if not (Registry and Registry.loadOrder) then return nil end
    local pages, page = {}, { modules={} }
    for _i, id in ipairs(Registry.loadOrder(PFX)) do
        if id == "__page_break__" then
            pages[#pages+1] = page
            page = { modules={} }
        else
            local mod = Registry.get and Registry.get(id)
            if mod and (not Registry.isEnabled or Registry.isEnabled(mod, PFX)) then
                page.modules[#page.modules+1] = id
            end
        end
    end
    pages[#pages+1] = page
    return { pages=pages }
end

local function wellFormed(layout)
    if type(layout) ~= "table" or type(layout.pages) ~= "table" then return false end
    for _i, page in ipairs(layout.pages) do
        if type(page) ~= "table" or type(page.modules) ~= "table" then return false end
    end
    return true
end

-- The saved layout, or SimpleUI's default one when none is saved yet. A saved
-- layout of a shape this code does not know is left alone (nil).
function M.layout()
    local S = store()
    if not S then return nil end
    local layout = S:readSetting(LAYOUT_KEY)
    if layout == nil then return defaultLayout(registry()), S end
    if wellFormed(layout) then return layout, S end
end

-- 1-based home page holding mod_id, or nil.
function M.pageOf(mod_id)
    local layout = M.layout()
    for i, page in ipairs(layout and layout.pages or {}) do
        for _j, entry in ipairs(page.modules or {}) do
            if entryId(entry) == mod_id then return i end
        end
    end
end

local function save(S, layout, mod_id, enabled)
    for i, page in ipairs(layout.pages) do page.id = i end
    S:saveSetting(LAYOUT_KEY, layout)
    local order, seen = {}, {}
    for _i, page in ipairs(layout.pages) do
        for _j, entry in ipairs(page.modules) do
            local id = entryId(entry)
            if id and not seen[id] then seen[id] = true; order[#order+1] = id end
        end
    end
    local Registry = registry()
    for _i, mod in ipairs(Registry and Registry.list and Registry.list() or {}) do
        if mod.id and not seen[mod.id] then seen[mod.id] = true; order[#order+1] = mod.id end
    end
    S:saveSetting(PFX .. "module_order", order)
    S:saveSetting(PFX .. mod_id, enabled)
    local HS = package.loaded["screens/sui_homescreen"] or package.loaded["sui_homescreen"]
    if HS and HS._instance and HS.refresh then pcall(HS.refresh, false) end
end

-- Put mod_id on a page of its own, first or last. False when SimpleUI's
-- layout cannot be read or the module is already placed.
function M.placeOnOwnPage(mod_id, first)
    local layout, S = M.layout()
    if not (layout and S) or M.pageOf(mod_id) then return false end
    -- A lone empty page (a home screen with nothing on it) is replaced.
    if #layout.pages == 1 and #(layout.pages[1].modules or {}) == 0 then layout.pages = {} end
    table.insert(layout.pages, first and 1 or #layout.pages + 1, { modules={ mod_id } })
    save(S, layout, mod_id, true)
    return true
end

-- Put mod_id on its own page directly after the page holding after_id.
function M.placeAfter(mod_id, after_id)
    local layout, S = M.layout()
    if not (layout and S) or M.pageOf(mod_id) then return false end
    local index = M.pageOf(after_id) or #layout.pages
    table.insert(layout.pages, index + 1, { modules={ mod_id } })
    save(S, layout, mod_id, true)
    return true
end

-- Take mod_id out of the layout; a page it leaves empty is removed, but the
-- home screen always keeps at least one page.
function M.remove(mod_id)
    local layout, S = M.layout()
    if not (layout and S) or not M.pageOf(mod_id) then return false end
    local pages = {}
    for _i, page in ipairs(layout.pages) do
        local modules = {}
        for _j, entry in ipairs(page.modules or {}) do
            if entryId(entry) ~= mod_id then modules[#modules+1] = entry end
        end
        if #modules > 0 or #(page.modules or {}) == 0 then
            page.modules = modules
            pages[#pages+1] = page
        end
    end
    if #pages == 0 then pages[1] = { modules={} } end
    layout.pages = pages
    save(S, layout, mod_id, false)
    return true
end

return M
