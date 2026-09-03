-- Gerenciador de arquivos.
local ui = mosaic.ui
local theme = mosaic.theme
local fsx = mosaic.lib("fsx")
local strutil = mosaic.lib("strutil")
local registry = mosaic.require("apps.registry")
local fileops = mosaic.lib("fileops")

local dir = ""   -- convencao do fs.combine: raiz e "", nunca "/"
local f = ui.form()

-- Tudo ancorado: o form resolve as posicoes a cada mudanca de tamanho, e nenhum widget
-- precisa ser reposicionado na mao no term_resize.
local pathLabel = f:add(ui.label { x = 1, y = 1, w = "fill", text = "",
    bg = theme.inputBg, fg = theme.inputFg })
local status = f:add(ui.label { x = 1, bottom = 0, w = "fill", text = "",
    bg = theme.taskbarBg, fg = theme.taskbarFg })

local list, refresh, open

-- A fila entra antes da lista: o fillTo da lista precisa saber onde a fila comeca, e a fila
-- so sabe disso depois de descobrir se quebrou em uma ou duas linhas.
local bar = ui.row(f, { bottom = 1, items = {
    { text = "&Abrir", onClick = function() open(list:getSelected()) end },
    { text = "Nova &pasta", alt = true, onClick = function()
        local name = ui.prompt("Nome da pasta:", "", "Nova pasta")
        if name and #name > 0 then fs.makeDir(fs.combine(dir, name)) refresh() end
    end },
    { text = "&Novo arquivo", alt = true, onClick = function()
        local name = ui.prompt("Nome do arquivo:", "novo.lua", "Novo arquivo")
        if name and #name > 0 then
            local path = fs.combine(dir, name)
            if not fs.exists(path) then fsx.write(path, "") end
            mosaic.launchWith({ title = "Editor" }, "/rom/programs/edit.lua", path)
            refresh()
        end
    end },
    { text = "&Ir para", alt = true, onClick = function()
        local p = ui.prompt("Caminho:", "/" .. dir, "Ir para")
        if p then
            local clean = p:gsub("^/", "")
            if fs.isDir(clean) then dir = clean refresh() else ui.msgbox("Pasta nao encontrada.", "Ops") end
        end
    end },
} })

-- ---------------------------------------------------------------- barra lateral
-- Lugares fixos e discos, como no Explorer. Ela entra ANTES do painel: o fillTo do painel
-- so enxerga widget ja adicionado.
local SIDE_W = 13
local sideWanted = true    -- F9 liga e desliga

-- Abaixo de 46 colunas a lateral come metade da tela e o painel fica inutilizavel
-- (a 51 sobrariam 38, e o tools/debug.js roda a 36). Ai ela some sozinha.
local function sideVisible(W)
    return sideWanted and W >= 46
end

local PLACES = {
    { name = "Inicio", path = "home" },
    { name = "Area trab.", path = "home/desktop" },
    { name = "Programas", path = "home/programas" },
    { name = "Downloads", path = "home/downloads" },
    { name = "Imagens", path = "home/imagens" },
    { name = "Documentos", path = "home/documentos" },
    { name = "Apps", path = "apps" },
}

local side = f:add(ui.list { x = 1, y = 2, w = SIDE_W, fillTo = bar, activateOnClick = true })
side.onLayout = function(self, W) self.visible = sideVisible(W) end

local function sideItems()
    local items = { { header = true, text = " Lugares" } }
    for _, p in ipairs(PLACES) do
        items[#items + 1] = { text = " " .. p.name, path = p.path }
    end
    items[#items + 1] = { separator = true }
    items[#items + 1] = { header = true, text = " Discos" }
    items[#items + 1] = { text = " Disco /", path = "" }
    -- hal.drives() devolve os drives vazios tambem; so' o que tem disquete montado abre.
    for _, d in ipairs(mosaic.lib("hal").drives()) do
        if d.present and d.mount then
            items[#items + 1] = { text = " " .. strutil.ellipsis(d.label or "Disquete", SIDE_W - 2),
                                  path = d.mount:gsub("^/", ""), mount = d.mount }
        end
    end
    return items
end

list = f:add(ui.list {
    x = 1, y = 2, w = "fill", fillTo = bar,
    render = function(item)
        if item.up then return " .. (voltar)" end
        local mark = item.isDir and "/" or " "
        local size = item.isDir and "" or strutil.bytes(item.size)
        local width = list.w
        local name = strutil.ellipsis(item.name, width - #size - 4)
        return mark .. strutil.pad(name, width - #size - 3) .. size
    end,
})

-- O painel ocupa o que a lateral deixar. Anchor nao resolve isso sozinho porque o x muda
-- junto: quando a lateral some, ele volta a comecar na coluna 1.
list.onLayout = function(self, W)
    self.x = sideVisible(W) and (SIDE_W + 1) or 1
    self.w = math.max(4, W - self.x + 1)
end

side.onActivate = function(_, item)
    if not item or not item.path then return end
    if not fs.isDir(item.path) and item.path ~= "" then
        ui.msgbox("Essa pasta nao existe:\n/" .. item.path, "Lugares")
        return
    end
    dir = item.path
    refresh()
end

-- ctx do fileops: e' por ele que a area de trabalho, a janela de pasta e este app
-- compartilham os mesmos menus e as mesmas acoes.
local ctx = { dir = dir, refresh = function(onlyDraw) refresh(true, onlyDraw) end }

function refresh(keep, onlyDraw)
    ctx.dir = dir
    if onlyDraw then f.dirty = true return end
    side:setItems(sideItems(), true)
    local items = {}
    if dir ~= "" then items[1] = { up = true, name = "..", path = fs.getDir(dir), isDir = true } end
    -- fileops.entries e nao fsx.listDetailed: ele resolve o nome amigavel do .lnk e
    -- entrega o `spec`, que o menu de contexto usa para saber que e' atalho.
    for _, it in ipairs(fileops.entries(dir)) do items[#items + 1] = it end
    list:setItems(items, keep)
    pathLabel.text = " /" .. dir
    status.text = string.format(" %d itens | %s livres", #items - (items[1] and items[1].up and 1 or 0),
        strutil.bytes(fs.getFreeSpace("/")))
    f.dirty = true
end

function open(item, x, y)
    if not item then return end
    if item.isDir then
        dir = item.path
        refresh()
        return
    end
    registry.openFile(item.path, x, y)
end

list.onActivate = function(_, item) open(item) end

-- Os menus sao os do fileops, os mesmos da area de trabalho e das janelas de pasta.
-- Antes daqui este app tinha a propria copia, com nomes parecidos mas nao iguais, e ela
-- ja tinha comecado a divergir (nao sabia de atalho, nem de recortar e colar).
list.onContext = function(_, item, _, lx, ly)
    if not item or item.up then return end
    fileops.itemMenu(ctx, item, list.x + lx - 1, list.y + ly - 1)
end

list.onEmpty = function(_, btn, lx, ly)
    if btn == 2 then fileops.emptyMenu(ctx, list.x + lx - 1, list.y + ly - 1) end
end

-- Teclas de arquivo. Ctrl+X/C/V sao livres; os que o CC rouba sao Ctrl+T, Ctrl+R e Ctrl+S.
local function selected()
    local it = list:getSelected()
    if it and not it.up then return it end
end

f.onEvent = function(_, ev, code)
    if ev == "key" and mosaic.ctrlHeld() then
        local it = selected()
        if code == keys.x and it then mosaic.lib("clip").cut(it.path) return true
        elseif code == keys.c and it then mosaic.lib("clip").copy(it.path) return true
        elseif code == keys.v then
            if fileops.paste(dir) then refresh(true) end
            return true
        end
    elseif ev == "key" and code == keys.f2 then
        local it = selected()
        if it and fileops.rename(it) then refresh(true) end
        return true
    elseif ev == "key" and code == keys.delete then
        local it = selected()
        if it and fileops.remove(it) then refresh(true) end
        return true
    elseif ev == "key" and code == keys.backspace and dir ~= "" then
        dir = fs.getDir(dir)
        refresh()
        return true
    elseif ev == "key" and code == keys.f9 then
        sideWanted = not sideWanted
        f:layout()
        f.dirty = true
        return true
    elseif ev == "key" and code == keys.f5 then
        refresh(true)
        return true
    elseif ev == "disk" or ev == "disk_eject" then
        -- Disquete entrou ou saiu: a lateral muda. Se voce estava DENTRO do que foi
        -- ejetado, ficar la e' um beco sem saida — volta para casa.
        if ev == "disk_eject" and dir ~= "" and not fs.isDir(dir) then dir = "home" end
        refresh(true)
        return true
    elseif ev == "term_resize" then
        refresh(true)   -- o form ja reposicionou tudo; aqui so o texto do rodape muda
        return true
    end
end

refresh()
f:run()
