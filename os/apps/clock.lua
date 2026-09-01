-- Relogio: hora do jogo, hora real, dia e tempo ligado. Tambem serve de alarme.
local ui = mosaic.ui
local theme = mosaic.theme
local strutil = mosaic.lib("strutil")

local w, h = term.getSize()
local f = ui.form()
local alarmAt, alarmId

f.onDraw = function(_, t)
    local game = textutils.formatTime(os.time(), true)
    local real = os.date("%H:%M:%S")
    local day = os.day()
    t.setTextColor(theme.appFg)
    local function center(y, s, color)
        t.setTextColor(color or theme.appFg)
        t.setCursorPos(math.max(1, math.floor((w - #s) / 2) + 1), y)
        t.write(s)
    end
    center(2, "Hora do jogo", theme.mutedFg)
    center(3, game, theme.accent)
    center(5, "Hora real", theme.mutedFg)
    center(6, real)
    center(8, "Dia " .. day .. "  |  ligado ha " .. strutil.duration(os.clock()), theme.mutedFg)
    if alarmAt then
        center(10, "Alarme as " .. textutils.formatTime(alarmAt, true), theme.errorBg)
    end
end

f:add(ui.button { x = 2, y = h - 1, text = "Alarme", onClick = function()
    local s = ui.prompt("Hora do jogo (0-24, ex 6 = amanhecer):", "6", "Alarme")
    local n = tonumber(s)
    if n and n >= 0 and n < 24 then
        if alarmId then os.cancelAlarm(alarmId) end
        alarmAt = n
        alarmId = os.setAlarm(n)
        mosaic.notify("Alarme marcado para " .. textutils.formatTime(n, true))
    elseif s then
        ui.msgbox("Digite um numero entre 0 e 24.", "Ops")
    end
    f.dirty = true
end })
f:add(ui.button { x = 12, y = h - 1, text = "Cancelar", alt = true, onClick = function()
    if alarmId then os.cancelAlarm(alarmId) alarmId, alarmAt = nil, nil end
    f.dirty = true
end })

local timer = os.startTimer(1)
f.onEvent = function(_, ev, id)
    if ev == "timer" and id == timer then
        timer = os.startTimer(1)
        f.dirty = true
        return true
    elseif ev == "alarm" and id == alarmId then
        alarmId, alarmAt = nil, nil
        mosaic.notify("Alarme! " .. textutils.formatTime(os.time(), true), 10)
        local speaker = peripheral.find("speaker")
        if speaker then pcall(speaker.playNote, "bell", 3, 12) end
        f.dirty = true
        return true
    elseif ev == "term_resize" then
        w, h = term.getSize()
        f.dirty = true
        return true
    end
end

f:run()
