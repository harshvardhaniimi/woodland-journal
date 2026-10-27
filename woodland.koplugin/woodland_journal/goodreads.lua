-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Read-only cache of a reader's public Goodreads shelves (RSS). No account
-- credentials; the profile comes from Woodland's settings.
local M = {}
-- Goodreads' standard shelves, offered before any shelf has been saved.
M.DEFAULT_SHELVES = {
    {id="to-read",label="Want to read"},
    {id="currently-reading",label="Currently reading"},
    {id="read",label="Read"},
}
-- Covers larger than this are re-saved smaller: the book page shows at most
-- about 460 x 690 pixels, and a 1875 x 2850 cover decodes to more than
-- KOReader's 8 MiB image cache allows.
M.COVER_MAX_W, M.COVER_MAX_H = 600, 900
-- What one refresh may take in. A hostile or broken feed must not be able to
-- freeze the home screen or fill the Kobo: a page of the feed, its tags and
-- items, each stored field, each cover, all covers together, and the free
-- space a refresh leaves on the Kobo.
M.FEED_MAX_BYTES, M.FEED_MAX_TAGS, M.PAGE_MAX_ITEMS = 4*1024*1024, 100000, 200
M.COVER_MAX_BYTES, M.COVERS_MAX_BYTES, M.KEEP_FREE_BYTES = 4*1024*1024, 300*1024*1024, 200*1024*1024
local function json() return require("dkjson") end
function M.directory()
    return require("datastorage"):getSettingsDir().."/simpleui/woodland-goodreads"
end
local function read(path)
    local f=io.open(path,"rb");if not f then return nil end
    local s=f:read("*a");f:close();return s
end
-- The saved snapshot. With a profile, a snapshot saved for another profile
-- is not shown (other_profile=true).
function M.load(profile)
    local s=read(M.directory().."/shelves.json")
    if not s then return {shelves={}} end
    local ok,v=pcall(json().decode,s)
    if not (ok and type(v)=="table" and type(v.shelves)=="table") then
        return {shelves={},error="The saved Goodreads snapshot could not be read."}
    end
    if profile and v.profile_id and tostring(v.profile_id)~=tostring(profile) then
        return {shelves={},other_profile=true}
    end
    return v
end
-- Pixel size of a PNG or JPEG from the start of its file; nil when unknown.
function M.imageSize(data)
    data=data or ""
    local function u16(i) local a,b=data:byte(i,i+1);return a and b and a*256+b end
    if data:sub(1,8)=="\137PNG\r\n\26\n" and #data>=24 then
        return u16(17)*65536+u16(19),u16(21)*65536+u16(23)
    end
    if data:sub(1,2)~="\255\216" then return nil end
    local i=3
    while i+8<=#data do
        if data:byte(i)~=0xFF then return nil end
        local marker=data:byte(i+1)
        if marker==0xFF then i=i+1
        elseif marker==0x01 or (marker>=0xD0 and marker<=0xD8) then i=i+2
        else
            -- Start-of-frame markers carry the size; C4, C8 and CC do not.
            if marker>=0xC0 and marker<=0xCF and marker~=0xC4 and marker~=0xC8 and marker~=0xCC then
                return u16(i+7),u16(i+5)
            end
            i=i+2+u16(i+2)
        end
    end
end
-- Whether an image of w x h pixels is safe to decode. A small file can claim
-- an enormous size, and decoding it would exhaust the reader's memory; real
-- Goodreads covers stay far below these limits.
M.DECODE_MAX_SIDE, M.DECODE_MAX_PIXELS = 6000, 12000000
function M.decodable(w,h)
    return (w and h and w>0 and h>0 and w<=M.DECODE_MAX_SIDE and h<=M.DECODE_MAX_SIDE and w*h<=M.DECODE_MAX_PIXELS) and true or false
end
-- Size that fits w x h inside max_w x max_h keeping the aspect ratio; nil
-- when it already fits (or the size is unknown).
function M.fitWithin(w,h,max_w,max_h)
    if not (w and h) or w<=0 or h<=0 or (w<=max_w and h<=max_h) then return nil end
    local scale=math.min(max_w/w,max_h/h)
    return math.max(1,math.floor(w*scale+0.5)),math.max(1,math.floor(h*scale+0.5))
end
-- Pixel size of an image file; nil when unknown.
function M.fileImageSize(path)
    local f=io.open(path,"rb");if not f then return nil end
    local head=f:read(65536)
    local w,h=M.imageSize(head)
    -- Colour profiles can push a JPEG's size marker far into the file.
    if not w and head and head:sub(1,2)=="\255\216" then
        local rest=f:read(8*1024*1024)
        w,h=M.imageSize(head..(rest or ""))
    end
    f:close()
    return w,h
end
-- Whether a saved cover may be drawn; checked once a session per path.
local safe={}
function M.coverIsSafe(path)
    if safe[path]==nil then safe[path]=M.decodable(M.fileImageSize(path)) end
    return safe[path]
end
-- Re-save a cover larger than COVER_MAX as a smaller JPEG (PNG for greyscale
-- images) in place. True when the file changed. Each path is checked once a
-- session.
local checked={}
function M.shrinkCover(path)
    if checked[path] then return false end
    checked[path]=true
    local w,h=M.fileImageSize(path)
    if not M.decodable(w,h) then return false end
    local tw,th=M.fitWithin(w,h,M.COVER_MAX_W,M.COVER_MAX_H)
    -- A cover of normal size can still carry megabytes of other data.
    if not tw and (require("libs/libkoreader-lfs").attributes(path,"size") or 0)>1024*1024 then tw,th=w,h end
    if not tw then return false end
    local RenderImage=require("ui/renderimage")
    local bb=RenderImage:renderImageFile(path,false)
    if not bb then return false end
    local small=RenderImage:scaleBlitBuffer(bb,tw,th,true)
    local temp=path..".small.part"
    local function written() local s=read(temp);return s and #s>0 end
    pcall(small.writeToFile,small,temp,"jpg",85)
    if not written() then pcall(small.writeToFile,small,temp,"png") end
    small:free()
    if written() and os.rename(temp,path) then return true end
    os.remove(temp)
    return false
end
local function text(v)
    if type(v)=="table" then v=v[1] end
    return type(v)=="string" and v or ""
end
local function utf8char(c)
    if c<0x80 then return string.char(c) end
    if c<0x800 then return string.char(0xC0+math.floor(c/64),0x80+c%64) end
    if c<0x10000 then return string.char(0xE0+math.floor(c/4096),0x80+math.floor(c/64)%64,0x80+c%64) end
    return string.char(0xF0+math.floor(c/262144),0x80+math.floor(c/4096)%64,0x80+math.floor(c/64)%64,0x80+c%64)
end
local ENTITIES={amp="&",lt="<",gt=">",quot='"',apos="'",nbsp=" "}
-- Goodreads descriptions and reviews are HTML fragments: keep paragraphs, drop tags.
function M.plain(s)
    -- A bold or italic lead-in often runs straight into the next sentence: "readers.</b>On a".
    s=text(s):gsub("([%.!?:])(</[BbIi]>)%s*(%u)","%1%2\n\n%3"):gsub("<[Bb][Rr]%s*/?>","\n"):gsub("</?[Pp]%f[%s>][^>]*>","\n\n"):gsub("<[^>]*>","")
    s=s:gsub("&(#?)([xX]?)(%w+);",function(hash,hex,name)
        if hash=="" then return ENTITIES[name] end
        local c=tonumber(name,hex~="" and 16 or 10)
        return c and c>0 and c<0x110000 and utf8char(c) or nil
    end)
    s=s:gsub("\r",""):gsub("[ \t]+"," "):gsub(" *\n *","\n"):gsub("\n\n\n+","\n\n")
    return (s:gsub("^%s+",""):gsub("%s+$",""))
end
-- Cap stored text without splitting a UTF-8 character.
local function cut(s,limit)
    limit=limit or 6000
    if #s<=limit then return s end
    return (s:sub(1,limit):gsub("[\192-\255][\128-\191]*$","")).."…"
end
-- "Wed, 23 Sep 2026 23:23:03 -0700" -> "23 Sep 2026"
local function day(v)
    local d,m,y=text(v):sub(1,64):match("(%d+) (%a+) (%d%d%d%d)")
    return d and (tonumber(d).." "..m.." "..y) or nil
end
function M.parse(xml)
    assert(type(xml)=="string" and #xml<=M.FEED_MAX_BYTES and not xml:find("<!ENTITY",1,true),"Unsupported RSS document")
    assert(select(2,xml:gsub("<",""))<=M.FEED_MAX_TAGS,"Unsupported RSS document")
    local h=require("woodland_journal/xml_handler").simpleTreeHandler()
    require("woodland_journal/xml").xmlParser(h):parse(xml:gsub("^\239\187\191",""))
    local channel=h.root and h.root.rss and h.root.rss.channel
    assert(type(channel)=="table","Goodreads did not return an RSS shelf")
    local items=channel.item or {}
    if items.book_id then items={items} end
    local books={}
    for _,it in ipairs(items) do
        if #books>=M.PAGE_MAX_ITEMS then break end
        local id=text(it.book_id)
        if id:match("^%d+$") and #id<=12 then
            local cover=text(it.book_large_image_url)
            if cover=="" then cover=text(it.book_medium_image_url) end
            local book=type(it.book)=="table" and it.book or {}
            local rating=tonumber(text(it.user_rating))
            local link=text(it.link)
            books[#books+1]={id=id,title=cut(text(it.title),300),author=cut(text(it.author_name),300),
                url=#link<=512 and link:match("^https://www%.goodreads%.com/[%w%-%._~/%%?=&]+$") or nil,
                image_url=M.allowedUrl(cover) and cover or "",
                description=cut(M.plain(cut(text(it.book_description),60000))),review=cut(M.plain(cut(text(it.user_review),60000))),
                pages=tonumber(text(book.num_pages)),average=tonumber(text(it.average_rating)),
                published=text(it.book_published):match("^%-?%d+$"),isbn=text(it.isbn):match("^[%dXx]+$"),
                rating=rating and rating>0 and rating or nil,added=day(it.user_date_added),read_at=day(it.user_read_at)}
        end
    end
    return books
end
-- The only addresses the refresh fetches: a profile's shelf feed and covers.
function M.allowedUrl(url)
    return type(url)=="string" and #url<=512 and (url:match("^https://www%.goodreads%.com/review/list_rss/%d+%?[%w%-_=&]+$")
        or url:match("^https://[is]%.gr%-assets%.com/[%w%-%._~/%%]+$")
        or url:match("^https://images%.gr%-assets%.com/[%w%-%._~/%%]+$")) and true or false
end
-- A certificate name such as "*.gr-assets.com" (one leading wildcard label).
function M.hostMatches(name,host)
    name,host=tostring(name):lower(),tostring(host):lower()
    if name==host then return true end
    local rest=name:match("^%*%.(.+)$")
    return rest~=nil and host:match("^[^%.]+%.(.+)$")==rest
end
function M.certificateMatches(cert,host)
    local ok,ext=pcall(function() return cert:extensions() end)
    local san=ok and type(ext)=="table" and ext["2.5.29.17"]
    for _,name in ipairs(type(san)=="table" and type(san.dNSName)=="table" and san.dNSName or {}) do
        if M.hostMatches(name,host) then return true end
    end
    return false
end
-- LuaSec verifies the certificate chain but not that the certificate names
-- the host; this connection checks the name after the handshake.
local function checkedConnection(params)
    local create=require("ssl.https").tcp(params)
    return function()
        local conn=create()
        local connect=conn.connect
        function conn:connect(host,port)
            local r,err=connect(self,host,port)
            if not r then return r,err end
            local cert=self.sock.getpeercertificate and self.sock:getpeercertificate()
            if cert and M.certificateMatches(cert,host) then return r end
            self.sock:close()
            return nil,"The certificate is not for "..tostring(host)
        end
        return conn
    end
end
-- GET an allowed address over checked HTTPS, at most maxbytes and about 30
-- seconds, following up to three redirects that stay on allowed addresses.
function M.request(url,maxbytes)
    local http,socketutil=require("socket.http"),require("socketutil")
    -- Through a proxy the certificate check would see the proxy, not Goodreads.
    assert(not http.PROXY,"Goodreads refresh does not work through a proxy")
    local create=checkedConnection{verify="peer",cafile="data/ca-bundle.crt"}
    local deadline=os.time()+30
    for _=1,4 do
        assert(M.allowedUrl(url),"Unexpected feed or cover address")
        local parts,total={},0
        socketutil:set_timeout(10,30)
        local ok,result,code,headers=pcall(http.request,{
            url=url,method="GET",create=create,redirect=false,
            headers={["User-Agent"]=socketutil.USER_AGENT},
            sink=function(chunk)
                if chunk then
                    total=total+#chunk
                    if total>maxbytes then return nil,"Response too large" end
                    if os.time()>deadline then return nil,"Goodreads took too long" end
                    parts[#parts+1]=chunk
                end
                return 1
            end,
        })
        socketutil:reset_timeout()
        code=tonumber(code)
        if ok and result and code==200 then return table.concat(parts) end
        local location=ok and result and (code==301 or code==302 or code==303 or code==307 or code==308)
            and type(headers)=="table" and headers.location
        if type(location)~="string" then break end
        url=require("socket.url").absolute(url,location)
    end
    error("Goodreads refresh failed; the saved shelf is unchanged")
end
-- Returns a replacement shelf from a cancellable worker; never replaces the
-- main snapshot until the worker completes and the UI accepts its result.
function M.fetchShelf(profile,id,label)
    assert(tostring(profile):match("^%d+$"),"No Goodreads profile is set")
    assert(id:match("^[%w%-]+$"),"Invalid shelf")
    local books,seen={},{}
    for page=1,10 do
        local batch=M.parse(M.request("https://www.goodreads.com/review/list_rss/"..profile
            .."?shelf="..id.."&per_page=200&page="..page,M.FEED_MAX_BYTES))
        local added=0
        for _,b in ipairs(batch) do
            if not seen[b.id] then seen[b.id]=true;books[#books+1]=b;added=added+1 end
        end
        if #batch<200 or added==0 then break end
        assert(page<10,"Shelf exceeds the refresh limit; saved data retained")
    end
    local dir=M.directory().."/covers"
    require("util").makePath(dir)
    local lfs=require("libs/libkoreader-lfs")
    -- Leftovers of a refresh that was cancelled mid-write.
    for name in lfs.dir(dir) do
        if name:match("^%d+%.jpg%.[%d%.a-z]*part$") then os.remove(dir.."/"..name) end
    end
    local missing,taken=0,0
    for _,b in ipairs(books) do
        local path=dir.."/"..b.id..".jpg"
        if (lfs.attributes(path,"size") or 0)==0 then
            local free=require("util").diskUsage(dir).available
            local ok,body=false,nil
            if taken<M.COVERS_MAX_BYTES and (not free or free>M.KEEP_FREE_BYTES) then
                ok,body=pcall(M.request,b.image_url,M.COVER_MAX_BYTES)
            end
            if ok and (body:sub(1,2)=="\255\216" or body:sub(1,4)=="\137PNG") and M.decodable(M.imageSize(body)) then
                taken=taken+#body
                local temp=path.."."..os.time()..".part"
                local f=io.open(temp,"wb")
                local written=f and f:write(body)
                if f then f:close() end
                if written and os.rename(temp,path) then pcall(M.shrinkCover,path)
                else os.remove(temp);missing=missing+1 end
            else missing=missing+1 end
        end
    end
    return {id=id,label=label,books=books,updated=os.time(),missing_covers=missing}
end
-- Saves a refreshed shelf into the snapshot for this profile; a snapshot of
-- another profile is replaced rather than merged. The previous snapshot is
-- kept as shelves-previous.json.
function M.saveShelf(shelf,profile)
    local dir=M.directory();require("util").makePath(dir)
    local previous=read(dir.."/shelves.json")
    local data=M.load(profile);local replaced=false
    if data.other_profile or data.error then data={shelves={}} end
    for i,s in ipairs(data.shelves) do if s.id==shelf.id then data.shelves[i]=shelf;replaced=true end end
    if not replaced then data.shelves[#data.shelves+1]=shelf end
    data.profile_id=profile
    if previous then
        assert(require("util").writeToFile(previous,dir.."/shelves-previous.json",true))
    end
    local temp=dir.."/shelves."..os.time()..".part"
    assert(require("util").writeToFile(json().encode(data),temp,true))
    assert(os.rename(temp,dir.."/shelves.json"))
end
return M
