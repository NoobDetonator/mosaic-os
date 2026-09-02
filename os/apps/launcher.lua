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
f:setFocus(list)
f.onEvent = function(_, ev, code)
    if ev == "key" and code == keys.escape then f:stop() return true end
end
f:run()
