-- Utilitarios de texto e numeros. `local s = mosaic.lib("strutil")`
local strutil = {}

function strutil.split(s, sep)
    sep = sep or "%s"
    local out = {}
    for piece in tostring(s):gmatch("([^" .. sep .. "]+)") do out[#out + 1] = piece end
    return out
end

function strutil.trim(s) return (tostring(s):gsub("^%s+", ""):gsub("%s+$", "")) end

function strutil.startsWith(s, p) return tostring(s):sub(1, #p) == p end
function strutil.endsWith(s, p) return p == "" or tostring(s):sub(-#p) == p end

function strutil.pad(s, w, align)
    s = tostring(s == nil and "" or s)
    if #s >= w then return s:sub(1, w) end
    local space = w - #s
    if align == "right" then return string.rep(" ", space) .. s end
    if align == "center" then
        local l = math.floor(space / 2)
        return string.rep(" ", l) .. s .. string.rep(" ", space - l)
    end
    return s .. string.rep(" ", space)
end

-- Corta no meio preservando o comeco e o fim: "arquivo...longo.lua"
function strutil.ellipsis(s, w)
    s = tostring(s)
    if #s <= w then return s end
    if w <= 3 then return s:sub(1, w) end
    local head = math.ceil((w - 3) / 2)
    return s:sub(1, head) .. "..." .. s:sub(#s - (w - 3 - head) + 1)
end

function strutil.wrap(text, w)
    local lines = {}
    for para in (tostring(text) .. "\n"):gmatch("(.-)\n") do
        local line = ""
        for word in para:gmatch("%S+") do
            while #word > w do
                if #line > 0 then lines[#lines + 1] = line line = "" end
                lines[#lines + 1] = word:sub(1, w)
                word = word:sub(w + 1)
            end
            if #line == 0 then line = word
            elseif #line + 1 + #word <= w then line = line .. " " .. word
            else lines[#lines + 1] = line line = word end
        end
        lines[#lines + 1] = line
    end
    return lines
end

-- 1536 -> "1.5 KB"
function strutil.bytes(n)
    n = tonumber(n) or 0
    local units = { "B", "KB", "MB" }
    local i = 1
    while n >= 1024 and i < #units do n = n / 1024 i = i + 1 end
    if i == 1 then return string.format("%d %s", n, units[i]) end
    return string.format("%.1f %s", n, units[i])
end

-- 12345678 -> "12.3M" (para RF, itens, etc)
function strutil.short(n)
    n = tonumber(n) or 0
    local neg = n < 0
    n = math.abs(n)
    local out
    if n >= 1e9 then out = string.format("%.2fG", n / 1e9)
    elseif n >= 1e6 then out = string.format("%.2fM", n / 1e6)
    elseif n >= 1e3 then out = string.format("%.1fk", n / 1e3)
    else out = string.format("%d", n) end
    return (neg and "-" or "") .. out
end

-- 3725 segundos -> "1h 2m 5s"
function strutil.duration(secs)
    secs = math.floor(tonumber(secs) or 0)
    local d = math.floor(secs / 86400)
    local h = math.floor(secs % 86400 / 3600)
    local m = math.floor(secs % 3600 / 60)
    local s = secs % 60
    if d > 0 then return string.format("%dd %dh", d, h) end
    if h > 0 then return string.format("%dh %dm", h, m) end
    if m > 0 then return string.format("%dm %ds", m, s) end
    return s .. "s"
end

function strutil.round(n, places)
    local mult = 10 ^ (places or 0)
    return math.floor((tonumber(n) or 0) * mult + 0.5) / mult
end

function strutil.percent(part, total)
    total = tonumber(total) or 0
    if total <= 0 then return 0 end
    return math.max(0, math.min(100, (tonumber(part) or 0) / total * 100))
end

-- Nome bonito para itens do jogo: "minecraft:iron_ingot" -> "Iron Ingot"
function strutil.itemName(id)
    local name = tostring(id):match("[^:]+$") or tostring(id)
    name = name:gsub("_", " ")
    return (name:gsub("(%a)([%w]*)", function(a, b) return a:upper() .. b end))
end

return strutil
