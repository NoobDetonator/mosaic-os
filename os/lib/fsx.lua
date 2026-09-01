-- Atalhos de arquivo. `local fsx = mosaic.lib("fsx")`
local fsx = {}

function fsx.read(path)
    local h = fs.open(path, "r")
    if not h then return nil end
    local data = h.readAll()
    h.close()
    return data
end

function fsx.readBinary(path)
    local h = fs.open(path, "rb")
    if not h then return nil end
    local data = h.readAll()
    h.close()
    return data
end

function fsx.lines(path)
    local data = fsx.read(path)
    if not data then return nil end
    local out = {}
    for line in (data .. "\n"):gmatch("(.-)\n") do out[#out + 1] = line end
    if out[#out] == "" then table.remove(out) end
    return out
end

function fsx.write(path, data)
    local dir = fs.getDir(path)
    if dir ~= "" and not fs.exists(dir) then fs.makeDir(dir) end
    local h = fs.open(path, "w")
    if not h then return false, "nao consegui escrever em " .. path end
    h.write(data)
    h.close()
    return true
end

function fsx.append(path, data)
    local dir = fs.getDir(path)
    if dir ~= "" and not fs.exists(dir) then fs.makeDir(dir) end
    local h = fs.open(path, "a")
    if not h then return false end
    h.write(data)
    h.close()
    return true
end

-- Tabela <-> JSON em disco (usados por configs de apps).
function fsx.readJSON(path, default)
    local data = fsx.read(path)
    if not data then return default end
    local ok, v = pcall(textutils.unserialiseJSON, data)
    if ok and v ~= nil then return v end
    return default
end

function fsx.writeJSON(path, value)
    local ok, s = pcall(textutils.serialiseJSON, value)
    if not ok then return false, s end
    return fsx.write(path, s)
end

-- Tabela <-> formato Lua (aceita funcoes nao, mas preserva numeros com precisao).
function fsx.readTable(path, default)
    local data = fsx.read(path)
    if not data then return default end
    local v = textutils.unserialise(data)
    if v == nil then return default end
    return v
end

function fsx.writeTable(path, value)
    return fsx.write(path, textutils.serialise(value))
end

-- Lista com detalhes, pastas primeiro, ordem alfabetica.
function fsx.listDetailed(dir)
    local out = {}
    if not fs.isDir(dir) then return out end
    for _, name in ipairs(fs.list(dir)) do
        local path = fs.combine(dir, name)
        out[#out + 1] = {
            name = name, path = path, isDir = fs.isDir(path),
            size = fs.isDir(path) and 0 or fs.getSize(path),
            readOnly = fs.isReadOnly(path),
        }
    end
    table.sort(out, function(a, b)
        if a.isDir ~= b.isDir then return a.isDir end
        return a.name:lower() < b.name:lower()
    end)
    return out
end

-- Tamanho total de uma pasta (recursivo).
function fsx.treeSize(path)
    if not fs.isDir(path) then return fs.exists(path) and fs.getSize(path) or 0 end
    local total = 0
    for _, name in ipairs(fs.list(path)) do total = total + fsx.treeSize(fs.combine(path, name)) end
    return total
end

-- Todos os arquivos abaixo de `path` (recursivo), ignorando /rom por padrao.
function fsx.walk(path, out, includeRom)
    out = out or {}
    if not fs.isDir(path) then out[#out + 1] = path return out end
    for _, name in ipairs(fs.list(path)) do
        local p = fs.combine(path, name)
        if includeRom or p:sub(1, 3) ~= "rom" then
            if fs.isDir(p) then fsx.walk(p, out, includeRom) else out[#out + 1] = p end
        end
    end
    return out
end

-- Nome livre: "copia.lua" -> "copia (2).lua"
function fsx.uniqueName(path)
    if not fs.exists(path) then return path end
    local slash = path:sub(1, 1) == "/" and "/" or ""
    local dir, name = fs.getDir(path), fs.getName(path)
    local base, ext = name:match("^(.*)(%.[^.]*)$")
    base, ext = base or name, ext or ""
    for i = 2, 999 do
        local candidate = slash .. fs.combine(dir, base .. " (" .. i .. ")" .. ext)
        if not fs.exists(candidate) then return candidate end
    end
    return path
end

return fsx
