-- Menu Iniciar (popup). Fecha sozinho ao perder o foco.
local ui = mosaic.ui
local theme = mosaic.theme
local registry = mosaic.require("apps.registry")

local w, h = term.getSize()
local items = {}
for _, app in ipairs(registry.all()) do
    items[#items + 1] = { text = " " .. app.name, app = app }
end
items[#items + 1] = { separator = true }
items[#items + 1] = { text = " Cursor por teclado", action = function() mosaic.togglePointer() end }
items[#items + 1] = { text = " Desligar", action = function() mosaic.shutdown() end }
items[#items + 1] = { text = " Reiniciar", action = function() mosaic.reboot() end }
items[#items + 1] = { text = " Sair para o shell", action = function()
    if ui.confirm("Fechar o Mosaic OS e voltar ao shell da ROM?", "Sair") then mosaic.exitToShell() end
end }

local f = ui.form { bg = theme.appBg, fg = theme.appFg }
f:add(ui.label { x = 1, y = 1, w = w, text = " " .. mosaic.version.name, bg = theme.accent, fg = theme.accentFg })
local list = f:add(ui.list {
    x = 1, y = 2, w = w, h = h - 1, items = items, activateOnClick = true,
    onActivate = function(_, item)
        f:stop()
        if item.app then registry.open(item.app)
        elseif item.action then item.action() end
    end,
})
-- Clique direito num programa: atalho na area de trabalho e propriedades, sem precisar
-- achar o arquivo dele no Arquivos.
--
-- O menu e' um ui.dialog no MESMO processo. Isso importa: o kernel mata o popup quando o
-- PROCESSO perde o foco (proc.lua, na troca de foco), e uma janela filha aqui dentro nao
-- troca de processo -- entao o Iniciar continua aberto atras do menu.
list.onContext = function(_, item, _, lx, ly)
    if not item or not item.app then return end   -- separador e Desligar nao tem atalho
    local app = item.app
    local acts = {
        { text = "Abrir", run = function() f:stop() registry.open(app) end },
        { text = "Criar atalho", run = function()   -- o popup tem 24 colunas: nome maior seria cortado
            mosaic.lib("fileops").toDesktop({ name = app.name, app = app.id })
        end },
    }
    -- Terminal e' action = "shell": nao tem arquivo, entao nao tem o que mostrar.
    if app.path and fs.exists(app.path) then
        acts[#acts + 1] = { text = "Propriedades", run = function()
            mosaic.lib("props").show(app.path)
        end }
    end
    local idx = ui.menu(acts, list.x + lx - 1, list.y + ly - 1, 24, { maxH = #acts })
    f.dirty = true
    if idx then acts[idx].run() end
end

f:setFocus(list)
f.onEvent = function(_, ev, code)
    if ev == "key" and code == keys.escape then f:stop() return true end
end
f:run()
