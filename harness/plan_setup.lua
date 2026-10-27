-- First-run setup (run with WOODLAND_TEST_SETUP=1).
-- WOODLAND_SETUP_PATH=accept: a device where nothing has been arranged (the
-- saved layout is cleared first); adds a Goodreads profile and puts the
-- dashboard first, Goodreads after it.
-- WOODLAND_SETUP_PATH=decline: keeps the sandbox's layout; turns Goodreads
-- off, which takes the Goodreads page out of the layout.
local path = os.getenv("WOODLAND_SETUP_PATH") or "accept"
local steps = {
    { lua=function() if path == "accept" then WOODLAND_RESET_LAYOUT() end end, wait=1 },
    { lua=function() WOODLAND_LOG_STATE("before setup") end, wait=0.3 },
    { shot="s01-welcome", wait=0.3 },
    { lua=function() WOODLAND_INPUT("Test Reader") end, wait=0.5 },
    { lua=function() WOODLAND_PRESS("Next") end, wait=2 },
    { shot="s02-goal", wait=0.3 },
    { lua=function() WOODLAND_PRESS("Next") end, wait=2 },
    { shot="s03-goodreads", wait=0.3 },
}
if path == "accept" then
    for _, s in ipairs{
        { lua=function() WOODLAND_PRESS("Add my Goodreads profile") end, wait=2 },
        { shot="s04-profile", wait=0.3 },
        { lua=function() WOODLAND_INPUT("https://www.goodreads.com/user/show/12345678-test-reader") end, wait=0.5 },
        { lua=function() WOODLAND_PRESS("Save") end, wait=2 },
        { shot="s05-placement", wait=0.3 },
        { lua=function() WOODLAND_PRESS("As the first page") end, wait=3 },
    } do steps[#steps+1] = s end
else
    for _, s in ipairs{
        { lua=function() WOODLAND_PRESS("Not now") end, wait=2 },
        { shot="s05-placement", wait=0.3 },
        { lua=function() WOODLAND_PRESS("I'll arrange it myself") end, wait=3 },
    } do steps[#steps+1] = s end
end
for _, s in ipairs{
    { shot="s06-ready", wait=0.3 },
    { lua=function() WOODLAND_CLOSE_TOP() end, wait=3 },
    { lua=function() WOODLAND_LOG_STATE("after setup") end, wait=0.3 },
    { shot="s07-home", wait=0.3 },
    { lua=function() WOODLAND_AUDIT("home after setup") end, wait=0.3 },
} do steps[#steps+1] = s end
return steps
