-- Gerenciador de tarefas: lista processos, foca, termina, mata.
local ui = mosaic.ui
local theme = mosaic.theme

local f = ui.form()
local w, h = term.getSize()

local function describe(p)
    local state = p.daemon and "servico" or (p.hidden and "oculto" or (p.minimized and "min" or (p.focused and "foco" or "")))
    return string.format("%3d %-14s %s", p.id, tostring(p.title):sub(1, 14), state)
end

local list = f:add(ui.list { x = 1, y = 2, w = w, h = h - 4, render = describe })
f:add(ui.label { x = 1, y = 1, w = w, text = " ID  Nome           Estado", bg = theme.accent, fg = theme.accentFg })
local info = f:add(ui.label { x = 1, y = h - 1, w = w, text = "" })

local function refresh()
    local items = mosaic.list()
    local keep = list.selected
    list:setItems(items, true)
    if keep and keep > #items then list.selected = #items end
    info.text = string.format("%d proc | %d KB livres | ligado ha %ds", #items,
        math.floor(fs.getFreeSpace("/") / 1024), math.floor(os.clock()))
    f.dirty = true
end

local function selectedId()
    local it = list:getSelected()
    return it and it.id
end

local bx = 1
local function addBtn(text, fn, alt)
    local b = f:add(ui.button { x = bx, y = h, text = text, alt = alt, onClick = fn })
    bx = bx + b:width() + 1
end
addBtn("&Focar", function() local id = selectedId() if id then mosaic.focus(id) end end)
addBtn("&Terminar", function() local id = selectedId() if id then mosaic.terminate(id) refresh() end end)
addBtn("&Matar", function()
    local id = selectedId()
    if id and id ~= mosaic.current() and ui.confirm("Matar o processo " .. id .. " sem aviso?") then mosaic.kill(id) end
    refresh()
end, true)
addBtn("&Atualizar", refresh, true)

local timer = os.startTimer(1)
f.onEvent = function(_, ev, id)
    if ev == "timer" and id == timer then
        timer = os.startTimer(1)
        refresh()
        return true
    elseif ev == "proc_exit" then
        refresh()
        return true
    end
end

refresh()
f:run()
