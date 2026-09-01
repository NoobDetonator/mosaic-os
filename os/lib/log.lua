-- Log em arquivo com rotacao simples. `local log = mosaic.lib("log").open("meuapp")`
local log = {}
local DIR = "/os/var/log"
local MAX = 16 * 1024

local Logger = {}
Logger.__index = Logger

function Logger:write(level, ...)
    local parts = {}
    for i = 1, select("#", ...) do
        local v = select(i, ...)
        parts[#parts + 1] = type(v) == "table" and textutils.serialise(v) or tostring(v)
    end
    local msg = string.format("%s [%s] %s", os.date("%H:%M:%S"), level, table.concat(parts, " "))
    if self.echo then print(msg) end
    if not fs.exists(DIR) then fs.makeDir(DIR) end
    if fs.exists(self.path) and fs.getSize(self.path) > MAX then
        if fs.exists(self.path .. ".old") then fs.delete(self.path .. ".old") end
        fs.move(self.path, self.path .. ".old")
    end
    local h = fs.open(self.path, "a")
    if h then h.writeLine(msg) h.close() end
    return msg
end

function Logger:info(...) return self:write("info", ...) end
function Logger:warn(...) return self:write("aviso", ...) end
function Logger:error(...) return self:write("erro", ...) end
function Logger:debug(...) if self.verbose then return self:write("debug", ...) end end
function Logger:clear() if fs.exists(self.path) then fs.delete(self.path) end end
function Logger:tail(n)
    local out = {}
    local h = fs.open(self.path, "r")
    if not h then return out end
    for line in h.readLine do out[#out + 1] = line end
    h.close()
    while #out > (n or 50) do table.remove(out, 1) end
    return out
end

function log.open(name, opts)
    opts = opts or {}
    return setmetatable({
        path = fs.combine(DIR, name .. ".log"),
        echo = opts.echo, verbose = opts.verbose,
    }, Logger)
end

function log.list()
    if not fs.isDir(DIR) then return {} end
    return fs.list(DIR)
end

return log
