-- BIOS do emulador headless (roda em fengari/Lua 5.3, mas expoe a API do CC:Tweaked ~1.101).
-- Reimplementa: term, window, colors/colours, keys, textutils, settings, os, fs, parallel, paintutils (min),
-- peripheral/rednet/redstone/http (stubs), read/print/write/printError/sleep.
local host = host
local W, H = host.opts.width, host.opts.height

unpack = table.unpack
loadstring = load
_HOST = "ComputerCraft 1.101.1 (Emulador Mosaic)"
_CC_DEFAULT_SETTINGS = ""
if host.opts.pocket then pocket = {} end

-- ---------------------------------------------------------------- colors
colors = {}
local names = { "white", "orange", "magenta", "lightBlue", "yellow", "lime", "pink", "gray", "lightGray", "cyan",
    "purple", "blue", "brown", "green", "red", "black" }
for i, n in ipairs(names) do colors[n] = 2 ^ (i - 1) end
colors.grey, colors.lightGrey = colors.gray, colors.lightGray
function colors.toBlit(c)
    local n = 0
    c = math.floor(c)
    while c > 1 do c = c / 2 n = n + 1 end
    return string.format("%x", n)
end
function colors.combine(...) local r = 0 for _, c in ipairs({ ... }) do r = r | math.floor(c) end return r end
function colors.subtract(c, ...) c = math.floor(c) for _, d in ipairs({ ... }) do c = c & ~math.floor(d) end return c end
function colors.test(c, d) return (math.floor(c) & math.floor(d)) == math.floor(d) end
colours = colors

-- ---------------------------------------------------------------- keys (codigos GLFW como no CC 1.13+)
keys = { space = 32, apostrophe = 39, comma = 44, minus = 45, period = 46, slash = 47, semicolon = 59, equals = 61,
    leftBracket = 91, backslash = 92, rightBracket = 93, grave = 96, escape = 256, enter = 257, tab = 258,
    backspace = 259, insert = 260, delete = 261, right = 262, left = 263, down = 264, up = 265, pageUp = 266,
    pageDown = 267, home = 268, ["end"] = 269, capsLock = 280, f1 = 290, f2 = 291, f3 = 292, f4 = 293, f5 = 294,
    numPadEnter = 335, leftShift = 340, leftCtrl = 341, leftAlt = 342, rightShift = 344, rightCtrl = 345, rightAlt = 346 }
for i = 0, 9 do keys[tostring(i)] = 48 + i end
for i = 0, 25 do keys[string.char(97 + i)] = 65 + i end
function keys.getName(code) for k, v in pairs(keys) do if v == code then return k end end return nil end

-- ---------------------------------------------------------------- terminal nativo
local function makeBuffer(w, h)
    local b = { w = w, h = h, text = {}, fg = {}, bg = {} }
    for y = 1, h do
        b.text[y] = string.rep(" ", w) b.fg[y] = string.rep("0", w) b.bg[y] = string.rep("f", w)
    end
    return b
end

local function blitInto(b, x, y, text, fg, bg)
    if y < 1 or y > b.h then return end
    local n = #text
    if x < 1 then
        text, fg, bg = text:sub(2 - x), fg:sub(2 - x), bg:sub(2 - x)
        x = 1
        n = #text
    end
    if n == 0 or x > b.w then return end
    if x + n - 1 > b.w then
        n = b.w - x + 1
        text, fg, bg = text:sub(1, n), fg:sub(1, n), bg:sub(1, n)
    end
    b.text[y] = b.text[y]:sub(1, x - 1) .. text .. b.text[y]:sub(x + n)
    b.fg[y] = b.fg[y]:sub(1, x - 1) .. fg .. b.fg[y]:sub(x + n)
    b.bg[y] = b.bg[y]:sub(1, x - 1) .. bg .. b.bg[y]:sub(x + n)
end

local native = {}
do
    local buf = makeBuffer(W, H)
    local cx, cy, blink = 1, 1, false
    local tc, bc = colors.white, colors.black
    native._buf = buf
    function native.write(s)
        s = tostring(s)
        blitInto(buf, cx, cy, s, string.rep(colors.toBlit(tc), #s), string.rep(colors.toBlit(bc), #s))
        cx = cx + #s
    end
    function native.blit(t, f, b)
        assert(#t == #f and #t == #b, "Arguments must be the same length")
        blitInto(buf, cx, cy, t, f, b)
        cx = cx + #t
    end
    function native.clear()
        for y = 1, H do buf.text[y] = string.rep(" ", W) buf.fg[y] = string.rep(colors.toBlit(tc), W) buf.bg[y] = string.rep(colors.toBlit(bc), W) end
    end
    function native.clearLine()
        if cy >= 1 and cy <= H then
            buf.text[cy] = string.rep(" ", W) buf.fg[cy] = string.rep(colors.toBlit(tc), W) buf.bg[cy] = string.rep(colors.toBlit(bc), W)
        end
    end
    function native.getCursorPos() return cx, cy end
    function native.setCursorPos(x, y) cx, cy = math.floor(x), math.floor(y) end
    function native.setCursorBlink(b) blink = b end
    function native.getCursorBlink() return blink end
    function native.getSize() return W, H end
    function native.scroll(n)
        for _ = 1, math.abs(n) do
            if n > 0 then
                table.remove(buf.text, 1) table.remove(buf.fg, 1) table.remove(buf.bg, 1)
                buf.text[H] = string.rep(" ", W) buf.fg[H] = string.rep(colors.toBlit(tc), W) buf.bg[H] = string.rep(colors.toBlit(bc), W)
            else
                table.remove(buf.text, H) table.remove(buf.fg, H) table.remove(buf.bg, H)
                table.insert(buf.text, 1, string.rep(" ", W)) table.insert(buf.fg, 1, string.rep(colors.toBlit(tc), W)) table.insert(buf.bg, 1, string.rep(colors.toBlit(bc), W))
            end
        end
    end
    function native.setTextColor(c) tc = c end
    function native.setBackgroundColor(c) bc = c end
    function native.getTextColor() return tc end
    function native.getBackgroundColor() return bc end
    function native.isColor() return true end
    function native.setPaletteColor() end
    function native.getPaletteColor() return 0, 0, 0 end
    function native.getLine(y) return buf.text[y], buf.fg[y], buf.bg[y] end
    native.setTextColour, native.setBackgroundColour = native.setTextColor, native.setBackgroundColor
    native.getTextColour, native.getBackgroundColour = native.getTextColor, native.getBackgroundColor
    native.isColour, native.setPaletteColour, native.getPaletteColour = native.isColor, native.setPaletteColor, native.getPaletteColor
end

local current = native
term = {}
function term.native() return native end
function term.current() return current end
function term.redirect(t)
    assert(type(t) == "table", "bad redirect")
    local prev = current
    current = t
    return prev
end
setmetatable(term, { __index = function(_, k)
    local f = current[k]
    if f == nil then return nil end
    return function(...) return current[k](...) end
end })

function term.screenText()
    local out = {}
    for y = 1, H do out[y] = native._buf.text[y] end
    return table.concat(out, "\n")
end

-- ---------------------------------------------------------------- window API
window = {}
function window.create(parent, x, y, w, h, visible)
    if visible == nil then visible = true end
    local buf = makeBuffer(w, h)
    local win = {}
    local cx, cy, blink = 1, 1, false
    local tc, bc = colors.white, colors.black
    local px, py = x, y

    local function flushLine(ly)
        if not visible then return end
        parent.setCursorPos(px, py + ly - 1)
        parent.blit(buf.text[ly], buf.fg[ly], buf.bg[ly])
    end
    local function updateCursor()
        if visible then
            parent.setCursorPos(px + cx - 1, py + cy - 1)
            parent.setCursorBlink(blink)
            parent.setTextColor(tc)
        end
    end
    function win.write(s)
        s = tostring(s)
        if cy >= 1 and cy <= h then
            blitInto(buf, cx, cy, s, string.rep(colors.toBlit(tc), #s), string.rep(colors.toBlit(bc), #s))
            flushLine(cy)
        end
        cx = cx + #s
        updateCursor()
    end
    function win.blit(t, f, b)
        assert(#t == #f and #t == #b, "Arguments must be the same length")
        if cy >= 1 and cy <= h then blitInto(buf, cx, cy, t, f, b) flushLine(cy) end
        cx = cx + #t
        updateCursor()
    end
    function win.clear()
        for ly = 1, h do
            buf.text[ly] = string.rep(" ", w) buf.fg[ly] = string.rep(colors.toBlit(tc), w) buf.bg[ly] = string.rep(colors.toBlit(bc), w)
            flushLine(ly)
        end
        updateCursor()
    end
    function win.clearLine()
        if cy >= 1 and cy <= h then
            buf.text[cy] = string.rep(" ", w) buf.fg[cy] = string.rep(colors.toBlit(tc), w) buf.bg[cy] = string.rep(colors.toBlit(bc), w)
            flushLine(cy)
        end
    end
    function win.getCursorPos() return cx, cy end
    function win.setCursorPos(nx, ny) cx, cy = math.floor(nx), math.floor(ny) updateCursor() end
    function win.setCursorBlink(b) blink = b updateCursor() end
    function win.getCursorBlink() return blink end
    function win.getSize() return w, h end
    function win.scroll(n)
        for _ = 1, math.abs(n) do
            if n > 0 then
                table.remove(buf.text, 1) table.remove(buf.fg, 1) table.remove(buf.bg, 1)
                buf.text[h] = string.rep(" ", w) buf.fg[h] = string.rep(colors.toBlit(tc), w) buf.bg[h] = string.rep(colors.toBlit(bc), w)
            else
                table.remove(buf.text, h) table.remove(buf.fg, h) table.remove(buf.bg, h)
                table.insert(buf.text, 1, string.rep(" ", w)) table.insert(buf.fg, 1, string.rep(colors.toBlit(tc), w)) table.insert(buf.bg, 1, string.rep(colors.toBlit(bc), w))
            end
        end
        if visible then for ly = 1, h do flushLine(ly) end end
    end
    function win.setTextColor(c) tc = c end
    function win.setBackgroundColor(c) bc = c end
    function win.getTextColor() return tc end
    function win.getBackgroundColor() return bc end
    function win.isColor() return parent.isColor() end
    function win.setPaletteColor(...) parent.setPaletteColor(...) end
    function win.getPaletteColor(...) return parent.getPaletteColor(...) end
    function win.getLine(ly)
        if ly < 1 or ly > h then error("Line is out of range.", 2) end
        return buf.text[ly], buf.fg[ly], buf.bg[ly]
    end
    function win.setVisible(v)
        if v and not visible then
            visible = true
            win.redraw()
            updateCursor()
        else
            visible = v
        end
    end
    function win.isVisible() return visible end
    function win.redraw()
        if not visible then return end
        for ly = 1, h do flushLine(ly) end
        updateCursor()
    end
    function win.restoreCursor() updateCursor() end
    function win.getPosition() return px, py end
    function win.reposition(nx, ny, nw, nh, np)
        px, py = nx, ny
        if np then parent = np end
        if nw and nh and (nw ~= w or nh ~= h) then
            local nb = makeBuffer(nw, nh)
            for ly = 1, math.min(h, nh) do
                blitInto(nb, 1, ly, buf.text[ly]:sub(1, nw), buf.fg[ly]:sub(1, nw), buf.bg[ly]:sub(1, nw))
            end
            -- preenche area nova com a cor de fundo atual
            for ly = 1, nh do
                if ly > h then
                    nb.bg[ly] = string.rep(colors.toBlit(bc), nw)
                elseif nw > w then
                    nb.bg[ly] = nb.bg[ly]:sub(1, w) .. string.rep(colors.toBlit(bc), nw - w)
                end
            end
            buf, w, h = nb, nw, nh
        end
        if visible then win.redraw() end
    end
    win.setTextColour, win.setBackgroundColour = win.setTextColor, win.setBackgroundColor
    win.getTextColour, win.getBackgroundColour = win.getTextColor, win.getBackgroundColor
    win.isColour, win.setPaletteColour, win.getPaletteColour = win.isColor, win.setPaletteColor, win.getPaletteColor
    if visible then win.redraw() end
    return win
end

-- ---------------------------------------------------------------- write/print (como bios.lua)
function write(sText)
    sText = tostring(sText)
    local w, h = term.getSize()
    local x, y = term.getCursorPos()
    local nLinesPrinted = 0
    local function newLine()
        if y + 1 <= h then term.setCursorPos(1, y + 1) else term.setCursorPos(1, h) term.scroll(1) end
        x, y = term.getCursorPos()
        nLinesPrinted = nLinesPrinted + 1
    end
    for whitespace, text in sText:gmatch("([ \t]*)([^ \t\n]*)") do
        -- whitespace
        for _ = 1, #whitespace do
            if x > w then newLine() end
            term.write(" ") x = x + 1
        end
        -- word
        while #text > 0 do
            if x > w then newLine() end
            local avail = w - x + 1
            local piece = text:sub(1, avail)
            term.write(piece)
            x = x + #piece
            text = text:sub(avail + 1)
        end
    end
    -- newlines
    local _, nl = sText:gsub("\n", "")
    for _ = 1, nl do newLine() end
    return nLinesPrinted
end
-- versao mais fiel: trata \n na ordem correta
function write(sText)
    sText = tostring(sText)
    local w, h = term.getSize()
    local x, y = term.getCursorPos()
    local lines = 0
    local function newLine()
        if y + 1 <= h then term.setCursorPos(1, y + 1) else term.setCursorPos(1, h) term.scroll(1) end
        x, y = term.getCursorPos()
        lines = lines + 1
    end
    for line, nl in sText:gmatch("([^\n]*)(\n?)") do
        for ws, word in line:gmatch("([ \t]*)([^ \t]*)") do
            for _ = 1, #ws do
                if x > w then newLine() end
                term.write(" ") x = x + 1
            end
            if #word > w then
                while #word > 0 do
                    if x > w then newLine() end
                    local piece = word:sub(1, w - x + 1)
                    term.write(piece) x = x + #piece
                    word = word:sub(#piece + 1)
                end
            elseif #word > 0 then
                if x + #word - 1 > w then newLine() end
                term.write(word) x = x + #word
            end
        end
        if nl == "\n" then newLine() end
    end
    return lines
end
function print(...)
    local n = 0
    local parts = table.pack(...)
    for i = 1, parts.n do
        n = n + write(tostring(parts[i]))
        if i < parts.n then write("\t") end
    end
    return n + write("\n")
end
function printError(...)
    local old = term.getTextColor()
    term.setTextColor(colors.red)
    print(...)
    term.setTextColor(old)
end

-- ---------------------------------------------------------------- os / eventos
local queue, timers, nextTimer, clock = {}, {}, 1, 0
local eventsSeen = 0
os.pullEventRaw = function(filter) return coroutine.yield(filter) end
os.pullEvent = function(filter)
    local ev = table.pack(coroutine.yield(filter))
    if ev[1] == "terminate" then error("Terminated", 0) end
    return table.unpack(ev, 1, ev.n)
end
function os.queueEvent(name, ...) queue[#queue + 1] = table.pack(name, ...) end
function os.startTimer(t)
    local id = nextTimer nextTimer = nextTimer + 1
    timers[id] = clock + math.max(0.05, math.ceil(t / 0.05) * 0.05)
    return id
end
function os.cancelTimer(id) timers[id] = nil end
function os.setAlarm() return nextTimer end
function os.cancelAlarm() end
function os.clock() return clock end
function os.time(l) if type(l) == "table" then return 0 end return 12.0 end
function os.day() return 1 end
function os.epoch() return host.epoch() end
function os.date(fmt, t) if fmt == "*t" or fmt == "!*t" then return { year = 2026, month = 1, day = 1, hour = 12, min = 0, sec = 0 } end return host.date(fmt, t) end
function os.getComputerID() return 7 end
os.computerID = os.getComputerID
local label = "emu"
function os.getComputerLabel() return label end
os.computerLabel = os.getComputerLabel
function os.setComputerLabel(l) label = l end
function os.version() return "CraftOS 1.8" end
function os.shutdown(code) if host.opts.show then host.print(term.screenText()) end host.exit(code or 0) end
function os.reboot() host.exit(0, "reboot") end
function os.run(env, path, ...)
    setmetatable(env, { __index = _G })
    local fn, err = loadfile(path, "t", env)
    if not fn then printError(err) return false end
    local ok, e = pcall(fn, ...)
    if not ok then if e ~= nil and e ~= "" then printError(e) end return false end
    return true
end
function sleep(t)
    local id = os.startTimer(t or 0)
    repeat local _, tid = os.pullEvent("timer") until tid == id
end
os.sleep = sleep
function os.loadAPI() return false end

-- ---------------------------------------------------------------- fs
fs = {}
local function clean(p) p = tostring(p):gsub("\\", "/"):gsub("^/+", ""):gsub("/+$", "") return p end
function fs.exists(p) return host.exists(clean(p)) end
function fs.isDir(p) return host.isDir(clean(p)) end
function fs.isReadOnly(p) return host.isReadOnly(clean(p)) end
function fs.list(p)
    if not fs.isDir(p) then error("/" .. clean(p) .. ": Not a directory", 2) end
    return host.list(clean(p))
end
function fs.getName(p) p = clean(p) return p:match("([^/]+)$") or "root" end
function fs.getDir(p) p = clean(p) return p:match("^(.*)/[^/]+$") or "" end
function fs.combine(a, b)
    a, b = clean(a or ""), clean(b or "")
    local s = a == "" and b or (b == "" and a or a .. "/" .. b)
    local parts = {}
    for seg in s:gmatch("[^/]+") do
        if seg == ".." then table.remove(parts) elseif seg ~= "." then parts[#parts + 1] = seg end
    end
    return table.concat(parts, "/")
end
function fs.getSize(p) return host.size(clean(p)) end
function fs.getFreeSpace() return 1000000 end
function fs.getCapacity() return 1000000 end
function fs.makeDir(p) host.mkdir(clean(p)) end
function fs.delete(p) host.delete(clean(p)) end
function fs.move(a, b) host.move(clean(a), clean(b)) end
function fs.copy(a, b) host.copy(clean(a), clean(b)) end
function fs.getDrive(p) return "hdd" end
function fs.isDriveRoot(p) return clean(p) == "" end
function fs.attributes(p) return { size = fs.getSize(p), isDir = fs.isDir(p), modified = 0, created = 0, modification = 0 } end
function fs.find(pat)
    pat = clean(pat)
    local dir, name = fs.getDir(pat), fs.getName(pat)
    local out = {}
    if not fs.isDir(dir) then return out end
    local lpat = "^" .. name:gsub("%%", "%%%%"):gsub("%.", "%%."):gsub("%*", ".*") .. "$"
    for _, f in ipairs(fs.list(dir)) do if f:match(lpat) then out[#out + 1] = fs.combine(dir, f) end end
    return out
end
function fs.complete() return {} end
function fs.open(p, mode)
    p = clean(p)
    local m = mode:sub(1, 1)
    if m == "r" then
        local data = host.read(p)
        if not data or fs.isDir(p) then return nil, "/" .. p .. ": No such file" end
        local pos = 1
        local h = {}
        function h.readAll() local s = data:sub(pos) pos = #data + 1 return s end
        function h.readLine(keep)
            if pos > #data then return nil end
            local nl = data:find("\n", pos, true)
            local line
            if nl then line = data:sub(pos, keep and nl or nl - 1) pos = nl + 1 else line = data:sub(pos) pos = #data + 1 end
            return line
        end
        function h.read(n)
            if pos > #data then return nil end
            n = n or 1
            if mode == "rb" and n == 1 and not h._multi then local c = data:byte(pos) pos = pos + 1 return c end
            local s = data:sub(pos, pos + n - 1) pos = pos + n return s
        end
        function h.close() end
        function h.seek(whence, off)
            off = off or 0
            if whence == "set" then pos = off + 1 elseif whence == "end" then pos = #data + off + 1 else pos = pos + off end
            return pos - 1
        end
        return h
    elseif m == "w" or m == "a" then
        if host.isReadOnly(p) then return nil, "/" .. p .. ": Access denied" end
        local parts = {}
        local h = {}
        local append = m == "a"
        if not append then host.write(p, "", false) end
        function h.write(s) parts[#parts + 1] = tostring(s) end
        function h.writeLine(s) parts[#parts + 1] = tostring(s) .. "\n" end
        function h.flush() host.write(p, table.concat(parts), true) parts = {} end
        function h.close() h.flush() end
        if append then host.write(p, "", true) end
        return h
    end
    return nil, "Unsupported mode"
end

function loadfile(path, mode, env)
    local data = host.read(clean(path))
    if not data then return nil, "/" .. clean(path) .. ": No such file" end
    return load(data, "@" .. clean(path), mode or "t", env or _G)
end
function dofile(path) local fn, err = loadfile(path) if not fn then error(err, 2) end return fn() end

-- ---------------------------------------------------------------- textutils
textutils = {}
textutils.empty_json_array = setmetatable({}, { __name = "json_array" })
textutils.json_null = setmetatable({}, { __name = "json_null" })
local function serializeImpl(t, indent, seen)
    local ty = type(t)
    if ty == "table" then
        if seen[t] then error("Cannot serialize table with recursive entries", 0) end
        seen[t] = true
        local out = { "{" }
        for k, v in pairs(t) do
            local ks
            if type(k) == "string" and k:match("^[%a_][%w_]*$") then ks = k else ks = "[" .. serializeImpl(k, "", seen) .. "]" end
            out[#out + 1] = "  " .. ks .. " = " .. serializeImpl(v, "", seen) .. ","
        end
        out[#out + 1] = "}"
        seen[t] = nil
        return table.concat(out, "\n")
    elseif ty == "string" then return string.format("%q", t)
    elseif ty == "number" then
        if t == math.floor(t) and math.abs(t) < 1e15 then return string.format("%d", t) end
        return tostring(t)
    elseif ty == "boolean" or ty == "nil" then return tostring(t)
    else error("Cannot serialize type " .. ty, 0) end
end
function textutils.serialize(t) return serializeImpl(t, "", {}) end
function textutils.unserialize(s)
    local fn = load("return " .. tostring(s), "=unserialize", "t", {})
    if not fn then return nil end
    local ok, v = pcall(fn)
    if ok then return v end
    return nil
end
local function jsonEncode(v, seen)
    local ty = type(v)
    if ty == "table" then
        if v == textutils.empty_json_array then return "[]" end
        if v == textutils.json_null then return "null" end
        if seen[v] then error("Cannot serialize table with recursive entries", 0) end
        seen[v] = true
        local isArr = #v > 0 or next(v) == nil
        if next(v) == nil then seen[v] = nil return "{}" end
        local out = {}
        if isArr then
            for i = 1, #v do out[i] = jsonEncode(v[i], seen) end
            seen[v] = nil
            return "[" .. table.concat(out, ",") .. "]"
        end
        for k, val in pairs(v) do
            if type(k) ~= "string" then error("Cannot serialize non-string key", 0) end
            out[#out + 1] = string.format("%q", k):gsub("\\\n", "\\n") .. ":" .. jsonEncode(val, seen)
        end
        seen[v] = nil
        return "{" .. table.concat(out, ",") .. "}"
    elseif ty == "string" then
        return '"' .. v:gsub('[%c"\\]', function(c)
            if c == '"' then return '\\"' elseif c == "\\" then return "\\\\" elseif c == "\n" then return "\\n"
            elseif c == "\t" then return "\\t" elseif c == "\r" then return "\\r" else return string.format("\\u%04x", c:byte()) end
        end) .. '"'
    elseif ty == "number" then
        if v == math.floor(v) and math.abs(v) < 1e15 then return string.format("%d", v) end
        return tostring(v)
    elseif ty == "boolean" then return tostring(v)
    elseif ty == "nil" then return "null"
    else error("Cannot serialize type " .. ty, 0) end
end
function textutils.serializeJSON(v) return jsonEncode(v, {}) end
function textutils.unserializeJSON(s)
    local pos = 1
    local function skip() pos = s:find("%S", pos) or #s + 1 end
    local parseValue
    local function parseString()
        pos = pos + 1
        local out = {}
        while true do
            local c = s:sub(pos, pos)
            if c == "" then return nil, "unterminated string" end
            if c == '"' then pos = pos + 1 return table.concat(out) end
            if c == "\\" then
                local e = s:sub(pos + 1, pos + 1)
                local map = { n = "\n", t = "\t", r = "\r", b = "\b", f = "\f", ['"'] = '"', ["\\"] = "\\", ["/"] = "/" }
                if e == "u" then
                    local code = tonumber(s:sub(pos + 2, pos + 5), 16) or 63
                    out[#out + 1] = code < 256 and string.char(code) or "?"
                    pos = pos + 6
                else
                    out[#out + 1] = map[e] or e
                    pos = pos + 2
                end
            else
                out[#out + 1] = c
                pos = pos + 1
            end
        end
    end
    function parseValue()
        skip()
        local c = s:sub(pos, pos)
        if c == "{" then
            pos = pos + 1
            local obj = {}
            skip()
            if s:sub(pos, pos) == "}" then pos = pos + 1 return obj end
            while true do
                skip()
                if s:sub(pos, pos) ~= '"' then return nil, "expected key at " .. pos end
                local k = parseString()
                skip()
                if s:sub(pos, pos) ~= ":" then return nil, "expected : at " .. pos end
                pos = pos + 1
                local v, err = parseValue()
                if err then return nil, err end
                obj[k] = v
                skip()
                local d = s:sub(pos, pos)
                pos = pos + 1
                if d == "}" then return obj elseif d ~= "," then return nil, "expected , or } at " .. pos end
            end
        elseif c == "[" then
            pos = pos + 1
            local arr = {}
            skip()
            if s:sub(pos, pos) == "]" then pos = pos + 1 return arr end
            while true do
                local v, err = parseValue()
                if err then return nil, err end
                arr[#arr + 1] = v
                skip()
                local d = s:sub(pos, pos)
                pos = pos + 1
                if d == "]" then return arr elseif d ~= "," then return nil, "expected , or ] at " .. pos end
            end
        elseif c == '"' then return parseString()
        elseif s:sub(pos, pos + 3) == "true" then pos = pos + 4 return true
        elseif s:sub(pos, pos + 4) == "false" then pos = pos + 5 return false
        elseif s:sub(pos, pos + 3) == "null" then pos = pos + 4 return nil
        else
            local num = s:match("^-?%d+%.?%d*[eE]?[-+]?%d*", pos)
            if num and #num > 0 then pos = pos + #num return tonumber(num) end
            return nil, "unexpected char at " .. pos
        end
    end
    local v, err = parseValue()
    if err then return nil, err end
    return v
end
textutils.serialise, textutils.unserialise = textutils.serialize, textutils.unserialize
textutils.serialiseJSON, textutils.unserialiseJSON = textutils.serializeJSON, textutils.unserializeJSON
function textutils.formatTime(t, h24)
    local hour = math.floor(t)
    local min = math.floor((t - hour) * 60)
    if h24 then return string.format("%02d:%02d", hour, min) end
    local ampm = hour >= 12 and "PM" or "AM"
    hour = hour % 12 if hour == 0 then hour = 12 end
    return string.format("%d:%02d %s", hour, min, ampm)
end
function textutils.urlEncode(s) return (tostring(s):gsub("[^%w%-%._~]", function(c) return string.format("%%%02X", c:byte()) end)) end
function textutils.pagedPrint(s) print(s) end
function textutils.slowPrint(s) print(s) end
function textutils.slowWrite(s) write(s) end
function textutils.tabulate(...) for _, row in ipairs({ ... }) do if type(row) == "table" then print(table.concat(row, "  ")) end end end
textutils.pagedTabulate = textutils.tabulate
function textutils.complete(s, t)
    local out = {}
    for _, v in ipairs(t or {}) do if v:sub(1, #s) == s then out[#out + 1] = v:sub(#s + 1) end end
    return out
end

-- ---------------------------------------------------------------- settings
settings = {}
local defs, values = {}, {}
function settings.define(name, o) defs[name] = o or {} end
function settings.undefine(name) defs[name] = nil end
function settings.set(name, v) values[name] = v end
function settings.get(name, def)
    if values[name] ~= nil then return values[name] end
    if defs[name] and defs[name].default ~= nil then return defs[name].default end
    return def
end
function settings.getDetails(name) local d = defs[name] or {} return { description = d.description, default = d.default, type = d.type, value = values[name] } end
function settings.unset(name) values[name] = nil end
function settings.clear() values = {} end
function settings.getNames()
    local out = {}
    local seen = {}
    for k in pairs(defs) do out[#out + 1] = k seen[k] = true end
    for k in pairs(values) do if not seen[k] then out[#out + 1] = k end end
    table.sort(out)
    return out
end
function settings.load(path)
    local h = fs.open(path or "/.settings", "r")
    if not h then return false end
    local t = textutils.unserialize(h.readAll()) h.close()
    if type(t) == "table" then for k, v in pairs(t) do values[k] = v end end
    return true
end
function settings.save(path)
    local h = fs.open(path or "/.settings", "w")
    if not h then return false end
    h.write(textutils.serialize(values)) h.close()
    return true
end

-- ---------------------------------------------------------------- read()
function read(replace, history, complete, default)
    term.setCursorBlink(true)
    local line = default or ""
    local pos = #line
    local sx, sy = term.getCursorPos()
    local function redraw()
        term.setCursorPos(sx, sy)
        term.write(replace and string.rep(replace, #line) or line)
        term.write(" ")
        term.setCursorPos(sx + pos, sy)
    end
    redraw()
    while true do
        local ev, a = os.pullEvent()
        if ev == "char" then line = line:sub(1, pos) .. a .. line:sub(pos + 1) pos = pos + 1 redraw()
        elseif ev == "paste" then line = line:sub(1, pos) .. a .. line:sub(pos + 1) pos = pos + #a redraw()
        elseif ev == "key" then
            if a == keys.enter or a == keys.numPadEnter then break
            elseif a == keys.backspace and pos > 0 then line = line:sub(1, pos - 1) .. line:sub(pos + 1) pos = pos - 1 redraw()
            elseif a == keys.left then pos = math.max(0, pos - 1) redraw()
            elseif a == keys.right then pos = math.min(#line, pos + 1) redraw()
            elseif a == keys.home then pos = 0 redraw()
            elseif a == keys["end"] then pos = #line redraw() end
        end
    end
    term.setCursorBlink(false)
    print()
    return line
end

-- ---------------------------------------------------------------- parallel
parallel = {}
local function runUntil(fns, limit)
    local cos, filters = {}, {}
    for i, f in ipairs(fns) do cos[i] = coroutine.create(f) end
    local living = #cos
    local ev = { n = 0 }
    while true do
        for i, co in ipairs(cos) do
            if co and (filters[i] == nil or filters[i] == ev[1] or ev[1] == "terminate") then
                local ok, res = coroutine.resume(co, table.unpack(ev, 1, ev.n))
                if not ok then error(res, 0) end
                if coroutine.status(co) == "dead" then
                    cos[i] = false living = living - 1
                    if living <= limit then return end
                else filters[i] = res end
            end
        end
        ev = table.pack(os.pullEventRaw())
    end
end
function parallel.waitForAny(...) local f = { ... } runUntil(f, #f - 1) end
function parallel.waitForAll(...) local f = { ... } runUntil(f, 0) end

-- ---------------------------------------------------------------- stubs
peripheral = { getNames = function() return {} end, isPresent = function() return false end, getType = function() return nil end,
    getMethods = function() return nil end, call = function() error("No peripheral attached") end, wrap = function() return nil end,
    find = function() return nil end, hasType = function() return false end, getName = function() return nil end }
redstone = { getSides = function() return { "top", "bottom", "left", "right", "front", "back" } end, getInput = function() return false end,
    setOutput = function() end, getOutput = function() return false end, getAnalogInput = function() return 0 end,
    setAnalogOutput = function() end, getAnalogOutput = function() return 0 end, getBundledInput = function() return 0 end,
    setBundledOutput = function() end, getBundledOutput = function() return 0 end, testBundledInput = function() return false end }
rs = redstone
rednet = { open = function() error("No such modem: nil", 2) end, close = function() end, isOpen = function() return false end,
    send = function() return false end, broadcast = function() end, receive = function() return nil end,
    host = function() end, unhost = function() end, lookup = function() return nil end, run = function() end, CHANNEL_BROADCAST = 65535 }
http = { checkURL = function() return true end, checkURLAsync = function() return true end,
    get = function() return nil, "Emulador sem rede" end, post = function() return nil, "Emulador sem rede" end,
    request = function(url) os.queueEvent("http_failure", type(url) == "table" and url.url or url, "Emulador sem rede") end,
    websocket = function() return false, "Emulador sem rede" end,
    websocketAsync = function(url) os.queueEvent("websocket_failure", url, "Emulador sem rede") end }
paintutils = { loadImage = function() return nil end, drawImage = function() end, drawPixel = function() end,
    drawLine = function() end, drawBox = function() end, drawFilledBox = function() end }
gps = { locate = function() return nil end }
help = { path = function() return "/rom/help" end, lookup = function() return nil end, topics = function() return {} end }
disk = { isPresent = function() return false end }
bit32 = bit32 or { band = function(a, b) return a & b end, bor = function(a, b) return a | b end, bxor = function(a, b) return a ~ b end,
    bnot = function(a) return ~a & 0xffffffff end, lshift = function(a, n) return (a << n) & 0xffffffff end,
    rshift = function(a, n) return (a & 0xffffffff) >> n end, arshift = function(a, n) return a >> n end }

-- ---------------------------------------------------------------- loop principal
local main = coroutine.create(function()
    os.run({}, "/rom/programs/shell.lua")
end)

local function nextEvent()
    if #queue > 0 then return table.remove(queue, 1) end
    local bestId, bestAt
    for id, at in pairs(timers) do
        if not bestAt or at < bestAt then bestId, bestAt = id, at end
    end
    if not bestId then return nil end
    timers[bestId] = nil
    clock = bestAt
    return table.pack("timer", bestId)
end

local filter
local ev = { n = 0 }
while true do
    if filter == nil or filter == ev[1] or ev[1] == "terminate" then
        local ok, res = coroutine.resume(main, table.unpack(ev, 1, ev.n))
        if not ok then
            host.stderr("=== ERRO NO COMPUTADOR ===\n" .. tostring(res) .. "\n" .. (debug.traceback(main) or ""))
            host.stderr(term.screenText())
            host.exit(2)
        end
        if coroutine.status(main) == "dead" then
            if host.opts.show then host.print(term.screenText()) end
            host.exit(0)
        end
        filter = res
    end
    ev = nextEvent()
    if not ev then
        host.stderr("=== DEADLOCK: sem eventos e sem timers (filtro=" .. tostring(filter) .. ") ===")
        host.stderr(term.screenText())
        host.exit(3)
    end
    eventsSeen = eventsSeen + 1
    if eventsSeen > host.opts.maxEvents then
        host.stderr("=== limite de eventos atingido ===")
        host.stderr(term.screenText())
        host.exit(4)
    end
end
