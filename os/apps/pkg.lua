-- Atualizador: compara os arquivos locais com o manifest do repositorio e baixa o que mudou.
local ui = mosaic.ui
local theme = mosaic.theme
local fsx = mosaic.lib("fsx")
local httpx = mosaic.lib("httpx")
local strutil = mosaic.lib("strutil")

local w, h = term.getSize()
local f = ui.form()
local installed = fsx.readJSON("/os/var/installed.json", {}) or {}
local base = installed.base or mosaic.version.repo

local infoLabel = f:add(ui.label { x = 2, y = 1, w = w - 2,
    text = "Instalado: " .. mosaic.version.version .. (installed.version and (" (pacote " .. installed.version .. ")") or "") })
local urlBox = f:add(ui.textbox { x = 2, y = 3, w = w - 3, text = base })
f:add(ui.label { x = 2, y = 2, text = "Repositorio (raw do GitHub):", fg = theme.mutedFg })
local list = f:add(ui.list { x = 1, y = 5, w = w, h = h - 7, render = function(it) return " " .. it.mark .. " " .. it.path end })
local status = f:add(ui.label { x = 1, y = h, w = w, text = " Clique em Verificar para comecar.", bg = theme.taskbarBg, fg = theme.taskbarFg })

local pending = {}

local function verify()
    status.text = " Baixando manifest..."
    f:draw()
    local manifest, err = httpx.getJSON(urlBox.text .. "/manifest.json")
    if not manifest or not manifest.files then
        status.text = " Falhou: " .. tostring(err)
        f.dirty = true
        return
    end
    pending = {}
    local items = {}
    for i, entry in ipairs(manifest.files) do
        status.text = string.format(" Verificando %d/%d...", i, #manifest.files)
        f:draw()
        local target = entry.path == "startup.lua" and "/startup.lua" or ("/" .. entry.path)
        local remote = httpx.get(urlBox.text .. "/" .. entry.path)
        local localData = fsx.read(target)
        local mark
        if not remote then mark = "!"
        elseif localData == nil then mark = "+" pending[#pending + 1] = { path = entry.path, target = target, data = remote }
        elseif localData ~= remote then mark = "~" pending[#pending + 1] = { path = entry.path, target = target, data = remote }
        else mark = "=" end
        items[#items + 1] = { path = entry.path, mark = mark }
    end
    list:setItems(items)
    status.text = string.format(" versao %s | %d arquivo(s) para atualizar (+ novo, ~ mudou, = igual)",
        tostring(manifest.version), #pending)
    infoLabel.text = "Instalado: " .. mosaic.version.version .. " | disponivel: " .. tostring(manifest.version)
    f.newVersion = manifest.version
    f.dirty = true
end

local function apply()
    if #pending == 0 then
        ui.msgbox("Nada para atualizar.", "Atualizador")
        return
    end
    if not ui.confirm("Atualizar " .. #pending .. " arquivo(s)?", "Confirmar") then return end
    local busy = ui.busy("Atualizando", "")
    for i, item in ipairs(pending) do
        busy.set(i / #pending, item.path)
        fsx.write(item.target, item.data)
    end
    busy.close()
    fsx.writeJSON("/os/var/installed.json", { version = f.newVersion, base = urlBox.text, at = os.epoch("utc") })
    if ui.confirm("Pronto. Reiniciar agora para aplicar?", "Atualizado") then mosaic.reboot() end
    pending = {}
    f.dirty = true
end

local bx = 1
local function addBtn(text, fn, alt)
    local b = f:add(ui.button { x = bx, y = h - 1, text = text, alt = alt, onClick = fn })
    bx = bx + b:width() + 1
end
addBtn("Verificar", verify)
addBtn("Atualizar", apply)
addBtn("Espaco", function()
    ui.msgbox(string.format("Livre: %s\nMosaic OS ocupa: %s",
        strutil.bytes(fs.getFreeSpace("/")), strutil.bytes(fsx.treeSize("/os"))), "Disco")
end, true)

f.onEvent = function(_, ev)
    if ev == "term_resize" then
        w, h = term.getSize()
        list.w, list.h = w, h - 9
        status.y, status.w = h, w
        f.dirty = true
        return true
    end
end

f:run()
