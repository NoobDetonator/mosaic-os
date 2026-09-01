-- Instalador / atualizador do Mosaic OS.
-- Uso no jogo:  wget run https://raw.githubusercontent.com/NoobDetonator/mosaic-os/master/install.lua
-- Argumentos opcionais:  install [update] [url-base]
local args = { ... }
local BASE = args[2] or "https://raw.githubusercontent.com/NoobDetonator/mosaic-os/master"
local updateOnly = args[1] == "update"

local function fetch(path)
    local url = BASE .. "/" .. path
    local res, err = http.get(url, nil, true)
    if not res then return nil, err or "falha" end
    local body = res.readAll()
    res.close()
    return body
end

local function readFile(path)
    local h = fs.open(path, "rb")
    if not h then return nil end
    local s = h.readAll()
    h.close()
    return s
end

local function writeFile(path, data)
    local dir = fs.getDir(path)
    if dir ~= "" and not fs.exists(dir) then fs.makeDir(dir) end
    local h = assert(fs.open(path, "wb"), "nao consegui escrever " .. path)
    h.write(data)
    h.close()
end

-- ponytail: sha1 em Lua puro seria lento e grande; comparamos por tamanho+conteudo baixado.
local function installTarget(rel)
    if rel == "startup.lua" then return "/startup.lua" end
    return "/" .. rel
end

term.setTextColor(colors.yellow)
print("== Mosaic OS - instalador ==")
term.setTextColor(colors.white)
if not http then
    printError("A API http esta desativada neste servidor. Peca ao admin para habilitar.")
    return
end

write("Baixando manifest... ")
local raw, err = fetch("manifest.json")
if not raw then printError("falhou: " .. tostring(err)) return end
local manifest = textutils.unserialiseJSON(raw)
if not manifest or not manifest.files then printError("manifest invalido") return end
print("v" .. tostring(manifest.version) .. ", " .. #manifest.files .. " arquivos")

if fs.exists("/startup.lua") and not fs.exists("/os") and not updateOnly then
    print("Ja existe um /startup.lua que nao e do Mosaic. Salvando como /startup.old.lua")
    if fs.exists("/startup.old.lua") then fs.delete("/startup.old.lua") end
    fs.move("/startup.lua", "/startup.old.lua")
end

local free = fs.getFreeSpace("/")
local written, skipped, failed = 0, 0, 0
for i, f in ipairs(manifest.files) do
    local target = installTarget(f.path)
    term.setCursorPos(1, select(2, term.getCursorPos()))
    term.clearLine()
    write(string.format("[%d/%d] %s", i, #manifest.files, f.path))
    local data, ferr = fetch(f.path)
    if not data then
        print("")
        printError("  falhou: " .. tostring(ferr))
        failed = failed + 1
    elseif readFile(target) == data then
        skipped = skipped + 1
    else
        writeFile(target, data)
        written = written + 1
    end
end
print("")

writeFile("/os/var/installed.json", textutils.serialiseJSON({
    version = manifest.version, base = BASE, at = os.epoch("utc"),
}))

term.setTextColor(failed > 0 and colors.red or colors.lime)
print(string.format("Concluido: %d gravados, %d iguais, %d falhas. Espaco livre: %d KB",
    written, skipped, failed, math.floor(fs.getFreeSpace("/") / 1024)))
term.setTextColor(colors.white)
if failed == 0 then
    print("Reinicie o computador (reboot) para entrar no Mosaic OS.")
end
