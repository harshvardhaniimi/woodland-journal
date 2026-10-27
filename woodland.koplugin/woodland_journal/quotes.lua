-- Public-domain literary excerpts, each checked word for word against the
-- linked Project Gutenberg text. A slash marks a line break in verse.
local walden = "https://www.gutenberg.org/ebooks/205"
local bacon = "https://www.gutenberg.org/ebooks/575"
local alcott = "https://www.gutenberg.org/ebooks/514"
local dickinson = "https://www.gutenberg.org/ebooks/12242"
local quotes = {
    { q="There is no frigate like a book / To take us lands away,", a="Emily Dickinson", b="Poems", source=dickinson },
    { q="Books are the treasured wealth of the world and the fit inheritance of generations and nations.", a="Henry David Thoreau", b="Walden", source=walden },
    { q="Some books are to be tasted, others to be swallowed, and some few to be chewed and digested.", a="Francis Bacon", b="Of Studies", source=bacon },
    { q="I’m not afraid of storms, for I’m learning how to sail my ship.", a="Louisa May Alcott", b="Little Women", source=alcott },
    { q="Hope is the thing with feathers / That perches in the soul,", a="Emily Dickinson", b="Poems", source=dickinson },
    { q="Books must be read as deliberately and reservedly as they were written.", a="Henry David Thoreau", b="Walden", source=walden },
    { q="Studies serve for delight, for ornament, and for ability.", a="Francis Bacon", b="Of Studies", source=bacon },
    { q="I like good strong words that mean something.", a="Louisa May Alcott", b="Little Women", source=alcott },
    { q="He ate and drank the precious words, / His spirit grew robust;", a="Emily Dickinson", b="Poems", source=dickinson },
    { q="How many a man has dated a new era in his life from the reading of a book.", a="Henry David Thoreau", b="Walden", source=walden },
    { q="Reading maketh a full man; conference a ready man; and writing an exact man.", a="Francis Bacon", b="Of Studies", source=bacon },
    { q="I went to the woods because I wished to live deliberately, to front only the essential facts of life…", a="Henry David Thoreau", b="Walden", source=walden },
    { q="A written word is the choicest of relics.", a="Henry David Thoreau", b="Walden", source=walden },
}
local M = { all = quotes }
function M.forDay(now)
    -- Local calendar day, stable throughout a day and across restarts.
    local d = os.date("*t", now or os.time())
    local y, m = d.year, d.month
    if m <= 2 then y = y - 1; m = m + 12 end
    local day = math.floor(365.25*y) + math.floor(30.6001*(m+1)) + d.day
        + 2 - math.floor(y/100) + math.floor(y/400)
    return quotes[(day % #quotes) + 1]
end
return M
