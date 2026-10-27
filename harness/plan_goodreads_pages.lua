-- Goodreads on: the home button opens the shelf page; every shelf page and
-- the first book's page are audited (large covers are shrunk on first view);
-- back and Woodland home return.
local logger = require("logger")
local function has(action)
    local w = rawget(_G, "WOODLAND_LAST")
    for _, t in ipairs(w and w.scene.targets or {}) do if t.action == action then return true end end
end
local steps = {
    { lua=function() WOODLAND_TAP("goodreads") end, wait=3 },
    { shot="g01-shelf", wait=0.3 },
    { lua=function() WOODLAND_AUDIT("shelf page 1") end, wait=0.3 },
    { lua=function() WOODLAND_TAP("book") end, wait=3 },
    { shot="g02-book", wait=0.3 },
    { lua=function() WOODLAND_AUDIT("book page") end, wait=0.3 },
    { lua=function() WOODLAND_TAP("back") end, wait=3 },
}
-- Up to 30 shelf pages, auditing each, until there is no Next.
for page = 2, 30 do
    steps[#steps+1] = { lua=function()
        if has("next") then WOODLAND_TAP("next") else rawset(_G, "WOODLAND_LAST_PAGE", rawget(_G, "WOODLAND_LAST_PAGE") or page - 1) end
    end, wait=2 }
    steps[#steps+1] = { lua=function()
        if not rawget(_G, "WOODLAND_LAST_PAGE") then WOODLAND_AUDIT("shelf page " .. page) end
    end, wait=0.2 }
end
steps[#steps+1] = { lua=function() logger.info("woodland-check", "shelf pages visited", rawget(_G, "WOODLAND_LAST_PAGE") or "30+") end, wait=0.2 }
steps[#steps+1] = { shot="g03-last-shelf-page", wait=0.3 }
steps[#steps+1] = { lua=function() WOODLAND_TAP("home") end, wait=3 }
steps[#steps+1] = { shot="g04-home", wait=0.3 }
return steps
