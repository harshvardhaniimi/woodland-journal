-- SPDX-License-Identifier: AGPL-3.0-or-later
-- A separate, offline-first Goodreads bookshelf page for Woodland Journal.
-- Registered only when the reader has set a Goodreads profile.
local Device=require("device")
local Store=require("woodland_journal/goodreads")
local Settings=require("woodland_journal/settings")
local Scene=require("woodland_journal/goodreads_scene")
local M={id="woodland_goodreads",name="Goodreads Bookshelves",enabled_key="woodland_goodreads",
    default_on=false,default_enabled=true,has_covers=true,is_book_mod=true,owns_chrome=true,
    needs={}}
local selected,page,detail="to-read",1,nil
local Data=require("woodland_journal/data")
local function limit(ctx) return Data.moduleHeight(ctx,M.id) end
function M.getHeight(ctx)
    local UI=Data.resolve("infra/sui_core","sui_core")
    local width=ctx and ctx.col_w or UI and UI.getInnerW() or Device.screen:getWidth()
    local h=limit(ctx)
    return math.floor(math.min(h,width*Scene.heightFor(h/width)/Scene.width)+0.5)
end
-- A Goodreads entry may also be a book on this Kobo: match its title (without
-- subtitle or series) against file names in the library folder. Skip macOS
-- "._" metadata files, which sit beside books copied from a Mac.
local function localCopy(title)
    local home=G_reader_settings:readSetting("home_dir")
    local function norm(s)
        s=tostring(s or ""):lower():gsub("%b()",""):gsub(":.*$","")
        return (s:gsub("[^%w]+"," "):gsub("^ +",""):gsub(" +$",""))
    end
    local want=norm(title)
    if not home or #want<4 then return end
    local ok,iter,dir=pcall(require("libs/libkoreader-lfs").dir,home)
    if not ok then return end
    for name in iter,dir do
        local ext=name:match("%.(%w+)$")
        ext=ext and ext:lower()
        if ext and ({epub=1,pdf=1,mobi=1,azw3=1,fb2=1,djvu=1,cbz=1,txt=1})[ext] and not name:match("^%._")
                and (" "..norm(name:gsub("%.%w+$",""))):find(" "..want,1,true) then
            return home.."/"..name
        end
    end
end
function M.build(width,ctx)
    local UIManager=require("ui/uimanager")
    local Info=require("ui/widget/infomessage")
    local profile=Settings.goodreadsProfile()
    local data=Store.load(profile);local shelf
    for _,s in ipairs(data.shelves) do if s.id==selected then shelf=s;break end end
    if not shelf then
        for _,s in ipairs(Store.DEFAULT_SHELVES) do if s.id==selected then shelf={id=s.id,label=s.label,books={}} end end
    end
    shelf=shelf or data.shelves[1] or {id="to-read",label="Want to read",books={}}
    local max_height=limit(ctx)
    local book
    for _,b in ipairs(detail and shelf.books or {}) do if b.id==detail then book=b;break end end
    detail=book and detail or nil
    local local_path=book and localCopy(book.title)
    local scene,p,pages
    if book then
        scene=Scene.buildBook(book,{shelf_label=shelf.label,on_kobo=local_path~=nil,aspect=max_height/math.floor(width)})
        p,pages=page,1
    else
        scene,p,pages=Scene.build(shelf,page,shelf.updated or data.updated,max_height/math.floor(width))
    end
    page=p
    local screen=ctx._screen_widget
    local function refresh()
        if screen and screen._refreshImmediate then screen:_refreshImmediate(false) end
    end
    local function back()
        if not detail then return false end
        detail=nil;refresh();return true
    end
    local function turn(delta)
        if detail then return false end
        local nextpage=math.max(1,math.min(page+delta,pages))
        if nextpage==page then return false end
        page=nextpage;refresh();return true
    end
    local actions={
        previous=function() turn(-1) end,next=function() turn(1) end,
        home=function()
            detail=nil
            if screen then screen:_setPage(require("woodland_journal/layout").pageOf("woodland_journal") or 1) end
        end,
        book=function(target) detail=target.book.id;refresh() end,
        back=back,
        open=function() if local_path and ctx and ctx.open_fn then ctx.open_fn(local_path) end end,
        description=function()
            local text=book.description or ""
            if book.review and book.review~="" then text=(text~="" and text.."\n\n" or "").."Your review\n\n"..book.review end
            UIManager:show(require("ui/widget/textviewer"):new{title=book.title or "Goodreads",text=text})
        end,
        shelves=function()
            local Dialog=require("ui/widget/buttondialog");local dialog;local rows={};local listed={}
            local function row(entry,count)
                listed[entry.id]=true
                rows[#rows+1]={{text=entry.label..(count and (" ("..count..")") or " (not saved yet)"),callback=function()
                    selected=entry.id;page=1;detail=nil;UIManager:close(dialog);refresh()
                end}}
            end
            for _,s in ipairs(data.shelves) do row(s,#s.books) end
            -- Goodreads' standard shelves, until each has been refreshed once.
            for _,s in ipairs(Store.DEFAULT_SHELVES) do if not listed[s.id] then row(s) end end
            rows[#rows+1]={{text="Close",callback=function() UIManager:close(dialog) end}}
            dialog=Dialog:new{title="Goodreads shelves",buttons=rows};UIManager:show(dialog)
        end,
        sync=function()
            local Trapper=require("ui/trapper")
            require("ui/network/manager"):runWhenOnline(function()
                Trapper:wrap(function()
                    local finished,ok,result=Trapper:dismissableRunInSubprocess(function()
                        return pcall(Store.fetchShelf,profile,shelf.id,shelf.label)
                    end,"Refreshing Goodreads shelf and covers…\nTap to cancel; your saved shelf will remain available.")
                    if finished and ok and type(result)=="table" then
                        local saved,err=pcall(Store.saveShelf,result,profile)
                        if saved then
                            page=1;refresh()
                            UIManager:show(Info:new{text="Goodreads shelf updated: "..#result.books.." books.\n"..(result.missing_covers or 0).." covers unavailable.",timeout=4})
                        else UIManager:show(Info:new{text="Could not save the refresh. Your earlier snapshot is retained.\n"..tostring(err)}) end
                    elseif finished then
                        UIManager:show(Info:new{text="Refresh failed. Your saved shelf remains available.\n"..tostring(result)})
                    end
                end)
            end)
        end,
    }
    local widget=require("woodland_journal/widget"):new{width=math.floor(width),max_height=max_height,scene=scene,ctx=ctx,actions=actions,
        book_helpers={getBookCover=function(id,w,h)
            if not tostring(id):match("^%d+$") then return nil end
            local path=Store.directory().."/covers/"..id..".jpg"
            if not require("libs/libkoreader-lfs").attributes(path) then return nil end
            -- Never decode a file claiming an enormous (or unknown) size.
            if not Store.coverIsSafe(path) then return nil end
            -- Covers saved before the downscaler existed are shrunk once here.
            pcall(Store.shrinkCover,path)
            -- Uncached: a cover decoding larger than KOReader's 8 MiB image cache
            -- fails the cache's assert on insert and quits KOReader.
            return require("ui/widget/imagewidget"):new{file=path,file_do_cache=false,width=w,height=h,scale_factor=0}
        end}}
    -- SimpleUI forwards body swipes to book modules. At the first/last shelf
    -- page, let the parent handle the swipe so Home remains one swipe away.
    -- On a book's page, a swipe back (east) returns to the shelf.
    widget.onSwipe=function(_,_,gesture)
        if gesture and gesture.direction=="west" then return turn(1) end
        if gesture and gesture.direction=="east" then return back() or turn(-1) end
        return false
    end
    return widget
end
return M
