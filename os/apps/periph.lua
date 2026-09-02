-- Navegador de perifericos: lista, mostra metodos e permite chamar.
local ui = mosaic.ui
local theme = mosaic.theme
local hal = mosaic.lib("hal")
local strutil = mosaic.lib("strutil")

local w, h = term.getSize()
local f = ui.form()

local list = f:add(ui.list {
    x = 1, y = 1, w = w, h = h - 2,
    render = function(it) return string.format(" %-22s %s", strutil.ellipsis(it.name, 22), it.type) end,
})
local info = f:add(ui.label { x = 1, y = h, w = w, text = "", bg = theme.taskbarBg, fg = theme.taskbarFg })

local function refresh()
    local items = hal.list()
    list:setItems(items, true)
    info.text = string.format(" %d perifericos | clique direito = acoes", #items)
    f.dirty = true
end

local function callMethod(name, method)
    local argstr = ui.prompt("Argumentos (Lua, separados por virgula):", "", method)
    if argstr == nil then return end
    local chunk, err = load("return " .. (argstr == "" and "" or argstr), "=args", "t", {})
    local args = {}
    if argstr ~= "" then
        if not chunk then ui.msgbox("Argumentos invalidos: " .. tostring(err), "Erro") return end
        local ok, res = pcall(function() return table.pack(chunk()) end)
        if not ok then ui.msgbox("Argumentos invalidos: " .. tostring(res), "Erro") return end
        args = res
    end
    local ok, res = pcall(function()
        return table.pack(peripheral.call(name, method, table.unpack(args, 1, args.n or #args)))
    end)
    if not ok then ui.msgbox(tostring(res), "Erro na chamada") return end
    local parts = {}
    for i = 1, (res.n or #res) do
        local v = res[i]
        parts[#parts + 1] = type(v) == "table" and textutils.serialise(v) or tostring(v)
    end
    ui.msgbox(#parts > 0 and table.concat(parts, "\n") or "(sem retorno)", method)
end

local function showMethods(item)
    local methods = peripheral.getMethods(item.name)
    if not methods then ui.msgbox("Periferico sumiu.", "Ops") refresh() return end
    table.sort(methods)
    local opts = {}
    for _, m in ipairs(methods) do opts[#opts + 1] = { text = " " .. m } end
    local idx = ui.menu(opts, 2, 3, math.min(w - 4, 28), { maxH = h - 5 })
    f.dirty = true
    if idx then callMethod(item.name, methods[idx]) f.dirty = true end
end

list.onActivate = function(_, item) if item then showMethods(item) end end
list.onContext = function(_, item, _, lx, ly)
    if not item then return end
    local actions = {
        { text = "Metodos", run = function() showMethods(item) end },
        { text = "Copiar nome", run = function()
            ui.msgbox('peripheral.wrap("' .. item.name .. '")', "Use no seu programa")
        end },
        { text = "Espelhar monitor", run = function()
            if item.type ~= "monitor" then ui.msgbox("Isso nao e um monitor.", "Ops") return end
            mosaic.launchWith({ title = "Monitor" }, "/os/apps/mirror.lua", item.name)
        end },
    }
    local idx = ui.menu(actions, lx + 2, ly + 2, 18)
    f.dirty = true
    if idx then actions[idx].run() end
end

local bx = 1
local function addBtn(text, fn, alt)
    local b = f:add(ui.button { x = bx, y = h - 1, text = text, alt = alt, onClick = fn })
    bx = bx + b:width() + 1
end
addBtn("&Metodos", function() local it = list:getSelected() if it then showMethods(it) end end)
addBtn("&Atualizar", refresh, true)
addBtn("&Resumo", function()
    local lines = {}
    local e = hal.energy()
    if e then lines[#lines + 1] = string.format("Energia: %s / %s (%.0f%%)", strutil.short(e.stored), strutil.short(e.capacity), e.percent) end
    local st = hal.storage()
    if st then lines[#lines + 1] = "Storage: bridge " .. st.kind:upper() .. " conectada" end
    local players = hal.players()
    if #players > 0 then lines[#lines + 1] = "Jogadores online: " .. table.concat(players, ", ") end
    local env = hal.environment()
    if env then
        lines[#lines + 1] = string.format("Ambiente: %s, chuva=%s", tostring(env.biome), tostring(env.raining))
    end
    if hal.has("chatBox") then lines[#lines + 1] = "Chat Box pronto (hal.chat)" end
    ui.msgbox(#lines > 0 and table.concat(lines, "\n") or "Nenhum periferico especial detectado.", "Resumo")
end, true)

f.onEvent = function(_, ev)
    if ev == "peripheral" or ev == "peripheral_detach" then refresh() return true end
    if ev == "term_resize" then
        w, h = term.getSize()
        list.w, list.h = w, h - 3
        info.y, info.w = h, w
        f.dirty = true
        return true
    end
end

refresh()
f:run()
