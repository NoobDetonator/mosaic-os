-- Espelha esta janela num monitor conectado. Uso: mirror <nome do monitor>
local args = { ... }
local name = args[1] or "monitor"
local mon = peripheral.wrap(name)
if not mon or peripheral.getType(name) ~= "monitor" then
    print("Monitor '" .. tostring(name) .. "' nao encontrado.")
    print("Pressione qualquer tecla.")
    os.pullEvent("key")
    return
end

mosaic.setTitle(nil, "Monitor " .. name)
mon.setTextScale(0.5)
-- O monitor tem paleta propria: sem isso o espelho sai com as cores erradas.
local palette = mosaic.require("kernel.palette")
if palette.enabled() then palette.apply(mon) end
mon.setBackgroundColor(colors.black)
mon.clear()

print("Espelhando a tela do sistema em " .. name .. ".")
print("Feche esta janela para parar.")
print("")
print("Dica: use 'monitor " .. name .. " <programa>' no terminal")
print("para rodar um programa direto no monitor.")

-- ponytail: copia a tela composta do WM a cada segundo. Suficiente para paineis;
-- para jogos no monitor use `monitor <nome> <programa>` do proprio CC.
local mw, mh = mon.getSize()
while true do
    local shot = mosaic.screenshot()
    for y = 1, math.min(mh, shot.h) do
        local l = shot.lines[y]
        mon.setCursorPos(1, y)
        mon.blit(l[1]:sub(1, mw), l[2]:sub(1, mw), l[3]:sub(1, mw))
    end
    sleep(1)
end
