-- Gerenciador de tarefas: lista processos, foca, termina, mata.
local ui = mosaic.ui
local theme = mosaic.theme

local f = ui.form()
local w, h = term.getSize()

local function describe(p)
    local state = p.daemon and "servico" or (p.hidden and "oculto" or (p.minimized and "min" or (p.focused and "foco" or "")))
    return string.format("%3d %-14s %s", p.id, tostring(p.title):sub(1, 14), state)
end

f:add(ui.label { x = 1, y = 1, w = "fill", text = " ID  Nome           Estado",
    bg = theme.accent, fg = theme.accentFg })
local list, info, refresh, selectedId

function refresh()
    local items = mosaic.list()
    local keep = list.selected
    list:setItems(items, true)
    if keep and keep > #items then list.selected = #items end
    info.text = string.format("%d proc | %d KB livres | ligado ha %ds", #items,
        math.floor(fs.getFreeSpace("/") / 1024), math.floor(os.clock()))
    f.dirty = true
end

function selectedId()
    local it = list:getSelected()
    return it and it.id
end

-- Ordem importa: a fila descobre quantas linhas ocupa, o rodape se ancora acima dela, e a
-- lista preenche ate o rodape. Cada ancora so enxerga quem ja entrou no form.
local bar = ui.row(f, { bottom = 0, items = {
    { text = "&Focar", onClick = function() local id = selectedId() if id then mosaic.focus(id) end end },
    { text = "&Terminar", onClick = function()
        local id = selectedId()
        if id then mosaic.terminate(id) refresh() end
    end },
    { text = "&Matar", alt = true, onClick = function()
        local id = selectedId()
        if id and id ~= mosaic.current() and ui.confirm("Matar o processo " .. id .. " sem aviso?") then
            mosaic.kill(id)
        end
        refresh()
    end },
    { text = "&Atualizar", alt = true, onClick = function() refresh() end },
} })
info = f:add(ui.label { x = 1, above = bar, w = "fill", text = "" })
list = f:add(ui.list { x = 1, y = 2, w = "fill", fillTo = info, render = describe })

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
