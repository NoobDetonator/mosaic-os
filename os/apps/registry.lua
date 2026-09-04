-- Registro de aplicativos: o que aparece no menu Iniciar, o que cada tipo de arquivo abre,
-- e a semeadura das pastas padrao (area de trabalho e Programas).
--
-- Apps do usuario: qualquer .lua em /apps entra sozinho na lista e ganha atalho em Programas.
local shortcut = require("lib.shortcut")
local fsx = require("lib.fsx")

local registry = {}

-- `desktop = true` quer dizer "semear o atalho na area de trabalho"; o resto vai para Programas.
registry.builtin = {
    { id = "terminal", name = "Terminal", icon = ">_", color = colors.black, desktop = true, action = "shell" },
    { id = "files", name = "Arquivos", icon = "[]", color = colors.yellow, desktop = true, path = "/os/apps/files.lua" },
    { id = "editor", name = "Editor", icon = "Ed", color = colors.orange, path = "/os/apps/editor.lua" },
    { id = "netcenter", name = "Rede", icon = "()", color = colors.green, path = "/os/apps/netcenter.lua" },
    { id = "periph", name = "Perifericos", icon = "Pf", color = colors.purple, path = "/os/apps/periph.lua" },
    { id = "taskman", name = "Tarefas", icon = "Tk", color = colors.red, path = "/os/apps/taskman.lua" },
    { id = "settings", name = "Config", icon = "Cf", color = colors.gray, desktop = true, path = "/os/apps/settings.lua" },
    { id = "help", name = "Ajuda", icon = "?", color = colors.lightBlue, desktop = true, path = "/os/apps/help.lua" },
    { id = "notes", name = "Notas", icon = "No", color = colors.lime, path = "/os/apps/notes.lua" },
    { id = "calc", name = "Calculadora", icon = "+-", color = colors.cyan, path = "/os/apps/calc.lua", w = 50, h = 17 },
    { id = "clock", name = "Relogio", icon = "()", color = colors.blue, path = "/os/apps/clock.lua" },
    -- Janela mais larga que o padrao: o titulo de uma musica do YouTube e' longo, e cortado
    -- ao meio nao da para saber o que esta na fila.
    { id = "music", name = "Musica", icon = "Mu", color = colors.magenta, path = "/os/apps/music.lua", w = 46, h = 14 },
    -- Janela grande: pagina de texto com 30 colunas nao se le, e a quebra de linha e' feita
    -- pela largura da janela.
    { id = "browser", name = "Navegador", icon = "Wb", color = colors.lightBlue, path = "/os/apps/browser.lua", w = 48, h = 16 },
    { id = "remote", name = "Controle remoto", icon = "Rm", color = colors.magenta, path = "/os/apps/remote.lua" },
    { id = "reactor", name = "Reator", icon = "Re", color = colors.red, path = "/os/apps/reactor.lua" },
    { id = "pkg", name = "Atualizar OS", icon = "Up", color = colors.brown, path = "/os/apps/pkg.lua" },
    { id = "paint", name = "Paint", icon = "Pt", color = colors.pink, path = "/rom/programs/fun/advanced/paint.lua", args = { "/home/desenho.nfp" } },
    { id = "lua", name = "Lua REPL", icon = "Lu", color = colors.lightGray, path = "/rom/programs/lua.lua" },
}

-- Que app abre cada extensao. Antes isso era um if/elseif dentro do Arquivos, e por isso a
-- area de trabalho e o menu Iniciar nao sabiam abrir arquivo nenhum.
registry.assoc = {
    nfp = { id = "paint" },
    nft = { id = "paint" },
    lua = { ask = true },              -- pergunta Executar ou Editar
    txt = { id = "editor" }, md = { id = "editor" }, json = { id = "editor" },
    cfg = { id = "editor" }, log = { id = "editor" }, lst = { id = "editor" },
}

registry.FOLDER_APP = "/os/apps/folder.lua"
registry.EDITOR = "/rom/programs/edit.lua"

registry.DESKTOP_DIR = "/home/desktop"
registry.PROGRAMS_DIR = "/home/programas"
registry.SEED_FILE = "/os/var/seeded.json"

function registry.all()
    local out = {}
    for _, a in ipairs(registry.builtin) do
        if a.action or fs.exists(a.path) then out[#out + 1] = a end
    end
    if fs.isDir("/apps") then
        for _, f in ipairs(fs.list("/apps")) do
            if f:match("%.lua$") then
                local name = f:gsub("%.lua$", "")
                out[#out + 1] = { id = "user:" .. name, name = name, icon = name:sub(1, 2),
                    color = colors.white, path = "/apps/" .. f, user = true }
            end
        end
    end
    return out
end

function registry.byId(id)
    if not id then return nil end
    for _, a in ipairs(registry.all()) do if a.id == id then return a end end
    return nil
end

function registry.open(app)
    if not app then return end
    if app.action == "shell" then return mosaic.shell() end
    if app.path then
        return mosaic.launchWith({ title = app.name, w = app.w, h = app.h }, app.path,
            table.unpack(app.args or {}))
    end
end

function registry.openFolder(path)
    local clean = "/" .. fs.combine(path, "")
    local name = fs.getName(clean)
    -- A janela padrao e 70% da tela, e a grade e 12x5 por icone: a pasta Programas abria
    -- mostrando 4 dos 12 programas. Este tamanho da 4 colunas por 3 linhas, os mesmos 12
    -- lugares em 51x19 e em 80x30.
    local W, H = mosaic.screenSize()
    return mosaic.launchWith({
        title = name ~= "" and name or "Disco",
        w = math.max(26, math.min(W - 2, 50)),
        h = math.max(11, math.min(H - 3, 16)),
    }, registry.FOLDER_APP, clean)
end

function registry.openEditor(path)
    return mosaic.launchWith({ title = "Editor" }, registry.EDITOR, path)
end

-- Abre o que estiver no caminho: pasta, atalho ou arquivo. (x, y) so' serve para o menu
-- Executar/Editar do .lua nascer onde o usuario clicou.
function registry.openFile(path, x, y)
    local ui = mosaic.ui
    local clean = "/" .. fs.combine(path, "")
    if not fs.exists(clean) then ui.msgbox("Esse item nao existe mais.", "Ops") return end
    if fs.isDir(clean) then return registry.openFolder(clean) end

    local spec = shortcut.read(clean)
    if spec then return registry.openShortcut(spec, x, y) end

    local ext = clean:lower():match("%.([^.]+)$") or ""
    local a = registry.assoc[ext]
    if a and a.ask then
        local choices = { { text = "Executar" }, { text = "Editar" }, { text = "Cancelar" } }
        local idx = ui.menu(choices, x or 4, y or 4, 14)
        if idx == 1 then return mosaic.launch(clean)
        elseif idx == 2 then return registry.openEditor(clean) end
        return
    end
    if a and a.id then
        local app = registry.byId(a.id)
        if app and app.path and fs.exists(app.path) then
            return mosaic.launchWith({ title = app.name }, app.path, clean)
        end
    end
    return registry.openEditor(clean)
end

function registry.openShortcut(spec, x, y)
    local ui = mosaic.ui
    if spec.app then
        local app = registry.byId(spec.app)
        if not app then ui.msgbox("O programa desse atalho nao existe mais.", "Atalho") return end
        return registry.open(app)
    end
    if not spec.path then ui.msgbox("Atalho sem alvo.", "Atalho") return end
    local target = "/" .. fs.combine(spec.path, "")
    if not fs.exists(target) then ui.msgbox("O alvo do atalho sumiu:\n" .. target, "Atalho") return end
    if fs.isDir(target) then return registry.openFolder(target) end
    if spec.args and #spec.args > 0 then
        return mosaic.launchWith({ title = spec.name or fs.getName(target) }, target,
            table.unpack(spec.args))
    end
    return registry.openFile(target, x, y)
end

-- Menu "Abrir com".
function registry.openWith(path, x, y)
    local ui = mosaic.ui
    local clean = "/" .. fs.combine(path, "")
    local opts = {
        { text = "Editor", run = function() registry.openEditor(clean) end },
        { text = "Paint", run = function()
            local app = registry.byId("paint")
            if app then mosaic.launchWith({ title = "Paint" }, app.path, clean) end
        end },
        { text = "Executar como programa", run = function() mosaic.launch(clean) end },
    }
    local idx = ui.menu(opts, x or 4, y or 4, 24)
    if idx then opts[idx].run() end
end

-- ---------------------------------------------------------------- semeadura
-- Cria os atalhos padrao uma unica vez por id. O que voce apagar nao volta no proximo
-- update: o /os/var/seeded.json guarda quem ja foi semeado, nao quem existe agora.
function registry.seed()
    local seeded = fsx.readJSON(registry.SEED_FILE, {}) or {}
    local changed = false
    local function put(id, dir, spec)
        if seeded[id] then return end
        if fs.isDir(dir) and shortcut.create(dir, spec) then
            seeded[id] = true
            changed = true
        end
    end

    put("__programas", registry.DESKTOP_DIR,
        { name = "Programas", path = registry.PROGRAMS_DIR, icon = "folder" })
    for _, a in ipairs(registry.builtin) do
        if a.action or fs.exists(a.path) then
            put(a.id, a.desktop and registry.DESKTOP_DIR or registry.PROGRAMS_DIR,
                { name = a.name, app = a.id })
        end
    end
    if fs.isDir("/apps") then
        for _, f in ipairs(fs.list("/apps")) do
            if f:match("%.lua$") then
                local name = f:gsub("%.lua$", "")
                put("user:" .. name, registry.PROGRAMS_DIR, { name = name, app = "user:" .. name })
            end
        end
    end

    if changed then fsx.writeJSON(registry.SEED_FILE, seeded) end
    return changed
end

-- Recomeco do zero: esquece o que ja foi semeado e semeia de novo.
-- So serve para quando a PASTA INTEIRA da area de trabalho sumiu; apagar um atalho
-- continua sendo definitivo, de proposito. Sem isso, quem perdesse /home ficaria com uma
-- area de trabalho vazia para sempre, porque o seeded.json diria que ja foi semeada.
function registry.reseed()
    if fs.exists(registry.SEED_FILE) then fs.delete(registry.SEED_FILE) end
    return registry.seed()
end

return registry
