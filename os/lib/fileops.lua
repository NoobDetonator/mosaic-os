-- Operacoes de arquivo e menus de contexto, num lugar so'.
--
-- A area de trabalho, a janela de pasta e o Arquivos fazem as mesmas coisas com os mesmos
-- nomes; se cada um tivesse a sua copia, tres menus iguais sairiam do lugar um por vez.
local fsx = require("lib.fsx")
local shortcut = require("lib.shortcut")
local clip = require("lib.clip")
local props = require("lib.props")
local registry = require("apps.registry")

local fileops = {}
fileops.DESKTOP_DIR = registry.DESKTOP_DIR

-- Entradas de uma pasta prontas para o ui.iconview ou para uma lista.
function fileops.entries(dir)
    local out = {}
    for _, it in ipairs(fsx.listDetailed(dir)) do
        local spec = shortcut.read(it.path)
        out[#out + 1] = {
            name = shortcut.displayName(it.path, spec),
            icon = shortcut.iconFor(it.path, it.isDir, spec),
            path = it.path, isDir = it.isDir, size = it.size, readOnly = it.readOnly, spec = spec,
        }
    end
    return out
end

function fileops.open(entry, x, y)
    if not entry then return end
    registry.openFile(entry.path, x, y)
end

-- ---------------------------------------------------------------- acoes
-- Todas devolvem true quando mexeram em disco, para o app saber que precisa recarregar.

function fileops.newFolder(dir)
    local ui = mosaic.ui
    local name = ui.prompt("Nome da pasta:", "", "Nova pasta")
    if not name or name == "" then return false end
    local path = "/" .. fs.combine(dir, shortcut.sanitize(name))
    if fs.exists(path) then ui.msgbox("Ja existe algo com esse nome.", "Ops") return false end
    local ok, err = pcall(fs.makeDir, path)
    if not ok then ui.msgbox(tostring(err), "Erro") return false end
    return true
end

function fileops.newFile(dir)
    local ui = mosaic.ui
    local name = ui.prompt("Nome do arquivo:", "novo.lua", "Novo arquivo")
    if not name or name == "" then return false end
    local path = "/" .. fs.combine(dir, shortcut.sanitize(name))
    if not fs.exists(path) then fsx.write(path, "") end
    registry.openEditor(path)
    return true
end

function fileops.newShortcut(dir)
    local ui = mosaic.ui
    local p = ui.prompt("Caminho do programa ou pasta:", "/apps/", "Novo atalho")
    if not p or p == "" then return false end
    local target = "/" .. fs.combine(p, "")
    if not fs.exists(target) then ui.msgbox("Nao existe: " .. target, "Ops") return false end
    local sugestao = fs.getName(target):gsub("%.lua$", "")
    local name = ui.prompt("Nome do atalho:", sugestao, "Novo atalho")
    if not name or name == "" then return false end
    local made, err = shortcut.create(dir, { name = name, path = target })
    if not made then ui.msgbox(tostring(err), "Erro") return false end
    return true
end

function fileops.rename(entry)
    local ui = mosaic.ui
    local novo = ui.prompt("Novo nome:", entry.name, "Renomear")
    if not novo or novo == "" or novo == entry.name then return false end
    local dir = fs.getDir(entry.path)

    if entry.spec then
        -- Atalho: o nome mostrado e o nome do arquivo mudam juntos, senao os dois se separam
        -- e a area de trabalho passa a mentir sobre o que esta ali.
        entry.spec.name = novo
        if not shortcut.write(entry.path, entry.spec) then
            ui.msgbox("Nao consegui gravar o atalho.", "Erro")
            return false
        end
        local target = fsx.uniqueName("/" .. fs.combine(dir, shortcut.sanitize(novo) .. shortcut.EXT))
        if target ~= "/" .. fs.combine(entry.path, "") then
            local ok, err = pcall(fs.move, entry.path, target)
            if not ok then ui.msgbox(tostring(err), "Erro") return false end
        end
        return true
    end

    local target = "/" .. fs.combine(dir, shortcut.sanitize(novo))
    if fs.exists(target) then ui.msgbox("Ja existe algo com esse nome.", "Ops") return false end
    local ok, err = pcall(fs.move, entry.path, target)
    if not ok then ui.msgbox(tostring(err), "Erro") return false end
    return true
end

function fileops.remove(entry)
    local ui = mosaic.ui
    local what = entry.spec and "o atalho" or (entry.isDir and "a pasta" or "o arquivo")
    if not ui.confirm("Excluir " .. what .. " " .. entry.name .. "?", "Confirmar") then return false end
    local ok, err = pcall(fs.delete, entry.path)
    if not ok then ui.msgbox(tostring(err), "Erro") return false end
    return true
end

-- Cria um atalho na area de trabalho. `spec` e' a tabela do atalho ja montada.
function fileops.toDesktop(spec)
    local ui = mosaic.ui
    if not fs.isDir(fileops.DESKTOP_DIR) then fs.makeDir(fileops.DESKTOP_DIR) end
    local made, err = shortcut.create(fileops.DESKTOP_DIR, spec)
    if not made then ui.msgbox(tostring(err or "?"), "Erro") return false end
    mosaic.notify("Atalho criado na area de trabalho")
    mosaic.emit("apps_changed")
    return true
end

-- Atalho para uma entrada de pasta: se ela ja e' um atalho, copia o alvo em vez de fazer
-- atalho de atalho.
function fileops.entryToDesktop(entry)
    local spec = entry.spec
    if spec then
        return fileops.toDesktop({ name = spec.name or entry.name, app = spec.app,
            path = spec.path, args = spec.args, icon = spec.icon })
    end
    return fileops.toDesktop({ name = entry.name, path = "/" .. fs.combine(entry.path, "") })
end

function fileops.paste(dir)
    local ui = mosaic.ui
    if not clip.has() then return false end
    local busy = #clip.paths > 1 and ui.busy("Colando", "") or nil
    local ok, err = clip.paste(dir, busy and function(i, n, name) busy.set(i / n, name) end or nil)
    if busy then busy.close() end
    if not ok then ui.msgbox(tostring(err), "Colar") return false end
    return true
end

-- ---------------------------------------------------------------- menus
-- ctx = { dir = , refresh = function, desktop = bool, extra = { {text=, run=}, ... } }

function fileops.itemMenu(ctx, entry, x, y)
    local ui = mosaic.ui
    if not entry then return end
    local acts = {}
    local function add(text, run) acts[#acts + 1] = { text = text, run = run } end

    add("Abrir", function() fileops.open(entry, x, y) end)
    if not entry.isDir and not entry.spec then
        add("Abrir com...", function() registry.openWith(entry.path, x, y) end)
    end
    if entry.isDir and clip.has() then
        add("Colar aqui dentro", function() if fileops.paste(entry.path) then ctx.refresh() end end)
    end
    add("Recortar", function() clip.cut(entry.path) end)
    add("Copiar", function() clip.copy(entry.path) end)
    if not ctx.desktop then
        add("Atalho na area de trabalho", function() fileops.entryToDesktop(entry) end)
    end
    add("Renomear", function() if fileops.rename(entry) then ctx.refresh() end end)
    add("Excluir", function() if fileops.remove(entry) then ctx.refresh() end end)
    add("Propriedades", function() props.show(entry.path, entry.spec) end)

    local idx = ui.menu(acts, x, y, 24, { maxH = #acts })
    ctx.refresh(true)
    if idx then acts[idx].run() end
end

function fileops.emptyMenu(ctx, x, y)
    local ui = mosaic.ui
    local acts = {}
    local function add(text, run) acts[#acts + 1] = { text = text, run = run } end

    add("Nova pasta", function() if fileops.newFolder(ctx.dir) then ctx.refresh() end end)
    add("Novo arquivo", function() if fileops.newFile(ctx.dir) then ctx.refresh() end end)
    add("Novo atalho", function() if fileops.newShortcut(ctx.dir) then ctx.refresh() end end)
    if clip.has() then
        add("Colar (" .. clip.describe() .. ")", function() if fileops.paste(ctx.dir) then ctx.refresh() end end)
    end
    add("Atualizar", function() ctx.refresh() end)
    for _, e in ipairs(ctx.extra or {}) do acts[#acts + 1] = e end

    local idx = ui.menu(acts, x, y, 22, { maxH = #acts })
    ctx.refresh(true)
    if idx then acts[idx].run() end
end

function fileops.demo()
    local dir = "/os/var/fileopsdemo"
    if fs.exists(dir) then fs.delete(dir) end
    fs.makeDir(dir)
    fsx.write(dir .. "/nota.txt", "oi")
    fs.makeDir(dir .. "/pasta")
    assert(shortcut.create(dir, { name = "Atalho", app = "files" }), "atalho de teste nao foi criado")

    local list = fileops.entries(dir)
    assert(#list == 3, "deveriam ser tres entradas, vieram " .. #list)
    local byName = {}
    for _, e in ipairs(list) do byName[e.name] = e end
    assert(byName["pasta"] and byName["pasta"].icon == "folder", "pasta sem o icone de pasta")
    assert(byName["nota.txt"] and byName["nota.txt"].icon == "file", "txt sem o icone generico")
    assert(byName["Atalho"], "o atalho deveria aparecer pelo nome de dentro, sem o .lnk")
    assert(byName["Atalho"].spec.app == "files", "o alvo do atalho nao foi lido")
    assert(byName["Atalho"].icon == "files", "atalho deveria usar o icone do app")

    fs.delete(dir)
    return true
end

return fileops
