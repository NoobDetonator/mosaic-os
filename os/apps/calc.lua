-- Calculadora: avalia expressoes Lua num ambiente com a biblioteca math.
local ui = mosaic.ui
local theme = mosaic.theme

local w, h = term.getSize()
local history = {}

-- Ambiente restrito: so matematica, sem acesso ao resto do sistema.
local env = { math = math, abs = math.abs, floor = math.floor, ceil = math.ceil, sqrt = math.sqrt,
    min = math.min, max = math.max, pi = math.pi, e = math.exp(1), sin = math.sin, cos = math.cos,
    tan = math.tan, log = math.log, exp = math.exp, random = math.random, tonumber = tonumber, ans = 0 }

local f = ui.form()
local list = f:add(ui.list { x = 1, y = 1, w = w, h = h - 3, items = history, render = function(x) return " " .. x end })
f:add(ui.label { x = 1, y = h - 2, w = w, text = " Expressao (Enter, ans = ultimo):" })
local box = f:add(ui.textbox { x = 2, y = h - 1, w = w - 2 })

local function calc()
    local expr = box.text
    if expr == "" then return end
    local chunk, err = load("return " .. expr, "=calc", "t", env)
    local result
    if not chunk then
        result = "erro: " .. tostring(err):gsub("^.-:%d+:%s*", "")
    else
        local ok, v = pcall(chunk)
        result = ok and tostring(v) or ("erro: " .. tostring(v):gsub("^.-:%d+:%s*", ""))
        if ok and tonumber(v) then env.ans = tonumber(v) end
    end
    history[#history + 1] = expr .. " = " .. result
    while #history > 200 do table.remove(history, 1) end
    list:setItems(history)
    list.selected = #history
    list:ensureVisible()
    box:setText("")
    f.dirty = true
end

box.onEnter = calc
f:add(ui.button { x = w - 3, y = h - 2, text = "=", onClick = calc })
f:setFocus(box)

f.onEvent = function(_, ev)
    if ev == "term_resize" then
        w, h = term.getSize()
        list.w, list.h = w, h - 4
        box.y, box.w = h - 1, w - 2
        f.dirty = true
        return true
    end
end

f:run()
