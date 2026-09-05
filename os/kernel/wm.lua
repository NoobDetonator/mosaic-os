-- Window manager / compositor.
-- Modelo: canvas invisivel do tamanho da tela; cada janela de app e uma window (invisivel, so buffer)
-- filha do canvas. A cada frame desenhamos titulo + conteudo de cada janela no canvas (bottom->top),
-- a taskbar, e entao mandamos o canvas para a tela linha a linha, so o que mudou.
-- Geometria de um processo p: p.x, p.y (linha do titulo), p.w, p.h (linhas do cliente).
-- Se p.chrome == false nao ha titulo: o cliente comeca em p.y.
local theme = require("kernel.theme")
local draw = require("kernel.draw")

local wm = {}
wm.W, wm.H = 0, 0
wm.slots = {}          -- taskbar: { {x1=, x2=, p=}, ... }
wm.toasts = {}         -- { {text=, expires=}, ... }
wm.last = {}           -- ultimo quadro enviado a tela, por linha: { text, fg, bg }
-- Cursor por teclado. O CC nao manda evento de movimento do mouse (so clique e arrasto), entao
-- um cursor que segue o mouse e impossivel. Este aqui anda com as setas e clica com Enter,
-- e serve tambem como caminho de teclado para tudo que so tinha mouse.
wm.pointer = { on = false, x = 1, y = 1 }
wm.MIN_W, wm.MIN_H = 10, 3
wm.startLabel = " Iniciar "

local root, canvas

local function clientTop(p) return p.chrome and p.y + 1 or p.y end
wm.clientTop = clientTop

function wm.init(rootTerm)
    root = rootTerm
    wm.root = root
    wm.W, wm.H = root.getSize()
    canvas = window.create(root, 1, 1, wm.W, wm.H, false)
    wm.canvas = canvas
    wm.last = {}
    wm.nullTerm = window.create(canvas, 1, 1, 1, 1, false)
    wm.tiny = wm.W < 40 or wm.H < 15 or pocket ~= nil
end

-- Area disponivel para janelas: linhas 1 .. H-1 (H = taskbar).
function wm.workArea() return 1, 1, wm.W, wm.H - 1 end

function wm.clamp(p)
    if p.chrome == false and p.bottom then return end
    p.w = math.max(wm.MIN_W, math.min(p.w, wm.W))
    local maxH = wm.H - 1 - (p.chrome and 1 or 0)
    p.h = math.max(wm.MIN_H, math.min(p.h, maxH))
    local totalH = p.h + (p.chrome and 1 or 0)
    p.x = math.max(1, math.min(p.x, wm.W - p.w + 1))
    p.y = math.max(1, math.min(p.y, wm.H - totalH))
end

function wm.apply(p)
    if not p.win then return end
    wm.clamp(p)
    p.win.reposition(p.x, clientTop(p), p.w, p.h)
end

local cascade = 0
function wm.defaultGeometry(p, spec)
    if wm.tiny or spec.maximized then
        p.x, p.y, p.w, p.h = 1, 1, wm.W, wm.H - 1 - (p.chrome and 1 or 0)
        p.maximized = true
        return
    end
    p.w = spec.w or math.max(wm.MIN_W, math.floor(wm.W * 0.7))
    p.h = spec.h or math.max(wm.MIN_H, math.floor((wm.H - 2) * 0.7))
    if spec.x and spec.y then
        p.x, p.y = spec.x, spec.y
    else
        cascade = (cascade % 4)
        p.x = 2 + cascade * 2
        p.y = 1 + cascade
        cascade = cascade + 1
    end
    wm.clamp(p)
end

function wm.toggleMax(p)
    if p.chrome == false then return end
    if p.maximized then
        if p.saved then p.x, p.y, p.w, p.h = p.saved.x, p.saved.y, p.saved.w, p.saved.h end
        p.maximized = false
    else
        p.saved = { x = p.x, y = p.y, w = p.w, h = p.h }
        p.x, p.y, p.w, p.h = 1, 1, wm.W, wm.H - 2
        p.maximized = true
    end
    wm.apply(p)
end

function wm.resize()
    local nw, nh = root.getSize()
    if nw == wm.W and nh == wm.H then return false end
    wm.W, wm.H = nw, nh
    wm.tiny = nw < 40 or nh < 15 or pocket ~= nil
    wm.pointer.x, wm.pointer.y = math.min(wm.pointer.x, nw), math.min(wm.pointer.y, nh)
    canvas.reposition(1, 1, nw, nh)
    wm.last = {}       -- sem isso a tela guarda linhas velhas depois do resize
    return true
end

-- Hit test: devolve {kind=, p=, lx=, ly=}
-- kind: "start" | "taskbar" | "client" | "title" | "min" | "max" | "close" | "desktop"
function wm.hitTest(procs, x, y)
    if y == wm.H then
        if x <= (wm.startW or #wm.startLabel) then return { kind = "start" } end
        for _, s in ipairs(wm.slots) do
            if x >= s.x1 and x <= s.x2 then return { kind = "taskbar", p = s.p } end
        end
        return { kind = "taskbar" }
    end
    for i = #procs, 1, -1 do
        local p = procs[i]
        if p.win and not p.minimized and not p.hidden and not p.monitor then
            local top = clientTop(p)
            if x >= p.x and x <= p.x + p.w - 1 then
                if p.chrome and y == p.y then
                    local col = x - p.x + 1
                    if col == p.w then return { kind = "close", p = p }
                    elseif col == p.w - 1 and not wm.tiny then return { kind = "max", p = p }
                    elseif col == p.w - 2 then return { kind = "min", p = p }
                    else return { kind = "title", p = p } end
                elseif y >= top and y <= top + p.h - 1 then
                    return { kind = "client", p = p, lx = x - p.x + 1, ly = y - top + 1 }
                end
            end
        end
    end
    return { kind = "desktop" }
end

-- Janela mais alta cobrindo a celula (x,y), ou nil.
function wm.topAt(procs, x, y)
    for i = #procs, 1, -1 do
        local p = procs[i]
        if p.win and not p.minimized and not p.hidden and not p.monitor then
            local top = clientTop(p)
            local y1 = p.chrome and p.y or top
            if x >= p.x and x <= p.x + p.w - 1 and y >= y1 and y <= top + p.h - 1 then return p end
        end
    end
    return nil
end

-- drag = { p=, resize=bool, ox=, oy=, w0=, h0=, x0=, y0= }
function wm.dragTo(drag, x, y)
    local p = drag.p
    if wm.tiny or p.maximized then return end
    if drag.resize then
        p.w = drag.w0 + (x - drag.x0)
        p.h = drag.h0 + (y - drag.y0)
    else
        p.x = x - drag.ox
        p.y = y - drag.oy
    end
    wm.apply(p)
end

-- Notificacoes rapidas (toasts) desenhadas acima da taskbar.
function wm.toast(text, secs)
    table.insert(wm.toasts, { text = tostring(text), expires = os.clock() + (secs or 4) })
    if #wm.toasts > 3 then table.remove(wm.toasts, 1) end
end

local function pad(s, w)
    s = tostring(s)
    if #s > w then return s:sub(1, w) end
    return s .. string.rep(" ", w - #s)
end

local function drawTitle(c, p, focused)
    local bg = focused and theme.titleBg or theme.titleBgInactive
    local fg = focused and theme.titleFg or theme.titleFgInactive
    -- Ultimas 3 colunas: minimizar, maximizar/restaurar, fechar. No Win95 esses sao botoezinhos
    -- em relevo, com a cor da face, e nao letras soltas sobre a barra.
    local right = wm.tiny and "_ x" or "_+x"
    if not wm.tiny and p.maximized then right = "_-x" end
    local titleW = math.max(0, p.w - #right - 1)
    local text = (" " .. pad(p.title or "", titleW) .. right):sub(1, p.w)

    local titlePart = #text - #right
    local fgs = string.rep(colors.toBlit(fg), titlePart) .. string.rep(colors.toBlit(theme.faceFg), #right)
    local bgs = string.rep(colors.toBlit(bg), titlePart) .. string.rep(colors.toBlit(theme.face), #right)
    fgs, bgs = fgs:sub(1, #text), bgs:sub(1, #text)
    c.setCursorPos(p.x, p.y)
    c.blit(text, fgs, bgs)
end

local function clockText()
    if settings.get("mosaic.clock", "real") == "game" then
        return textutils.formatTime(os.time(), true)
    end
    return os.date("%H:%M")
end

function wm.drawTaskbar(procs, focus)
    local c = canvas
    c.setCursorPos(1, wm.H)
    c.setBackgroundColor(theme.taskbarBg)
    c.setTextColor(theme.taskbarFg)
    c.clearLine()

    -- Botao Iniciar: sempre em relevo alto, como no Win95.
    local label = wm.tiny and " M " or wm.startLabel
    c.setCursorPos(1, wm.H)
    c.setBackgroundColor(theme.startBg)
    c.setTextColor(theme.startFg)
    c.write(label)
    draw.caps(c, 1, wm.H, #label, theme.startBg, true)
    wm.startW = #label

    local clock = clockText()
    local clockX = wm.W - #clock
    local x = #label + 2
    wm.slots = {}
    local visible = {}
    for _, p in ipairs(procs) do
        if p.win and not p.hidden and not p.bottom and not p.popup then table.insert(visible, p) end
    end
    if #visible > 0 then
        local avail = clockX - 1 - x
        local slotW = math.max(4, math.min(14, math.floor(avail / #visible) - 1))
        for _, p in ipairs(visible) do
            if x + slotW > clockX - 1 then break end
            -- Janela em foco = botao afundado. E' o unico jeito de mostrar qual esta ativa
            -- sem depender de hover, que o CC nao tem.
            local active = p == focus and not p.minimized
            c.setCursorPos(x, wm.H)
            c.setBackgroundColor(active and theme.taskbarActiveBg or theme.taskbarBg)
            c.setTextColor(active and theme.taskbarActiveFg or theme.taskbarFg)
            -- App na parede leva o numero do monitor na frente: sem isso ele some da tela e
            -- o botao nao explica para onde foi. Com dois monitores o numero e' a resposta.
            local rotulo = p.title or "?"
            if p.monitor then rotulo = p.monitor.label .. ":" .. rotulo end
            c.setCursorPos(x + 1, wm.H)
            c.write(pad(rotulo, slotW - 2))
            draw.caps(c, x, wm.H, slotW, active and theme.taskbarActiveBg or theme.taskbarBg, not active)
            table.insert(wm.slots, { x1 = x, x2 = x + slotW - 1, p = p })
            x = x + slotW + 1
        end
    end
    if wm.pointer.on and clockX - 4 > x then
        -- O modo nunca pode ficar invisivel: ele engole as setas dos apps enquanto esta ligado.
        c.setCursorPos(clockX - 4, wm.H)
        c.setBackgroundColor(theme.selBg)
        c.setTextColor(theme.selFg)
        c.write(" " .. wm.POINTER_CHAR .. " ")
    end
    c.setCursorPos(clockX, wm.H)
    c.setBackgroundColor(theme.taskbarBg)
    c.setTextColor(theme.taskbarFg)
    c.write(clock)
end

local function drawToasts()
    local now = os.clock()
    local i = 1
    while i <= #wm.toasts do
        if wm.toasts[i].expires < now then table.remove(wm.toasts, i) else i = i + 1 end
    end
    local y = wm.H - 1
    for k = #wm.toasts, 1, -1 do
        local t = wm.toasts[k]
        local text = " " .. t.text:sub(1, wm.W - 2) .. " "
        canvas.setCursorPos(wm.W - #text + 1, y)
        canvas.setBackgroundColor(theme.toastBg)
        canvas.setTextColor(theme.toastFg)
        canvas.write(text)
        y = y - 1
        if y < 1 then break end
    end
end

function wm.hasToasts() return #wm.toasts > 0 end

-- Desenhado por ultimo, invertendo as cores da propria celula: assim ele aparece sobre
-- qualquer fundo e continua respeitando o limite de duas cores por celula.
local function drawPointer()
    local p = wm.pointer
    if not p.on then return end
    local ok, text, fg, bg = pcall(canvas.getLine, p.y)
    if not ok or not text then return end
    local i = p.x
    if i < 1 or i > #text then return end
    local f, b = fg:sub(i, i), bg:sub(i, i)
    if f == b then f = (b == "0") and "f" or "0" end   -- celula lisa: garante contraste
    canvas.setCursorPos(i, p.y)
    canvas.blit(wm.POINTER_CHAR, b, f)
end

-- Seta cheia. Se a fonte do jogo nao trouxer esse caractere, troque por "+".
wm.POINTER_CHAR = string.char(16)

-- Sombra da janela, em MEIA celula.
--
-- Celula inteira dava 6 pixels de sombra numa tela de 306: uma tarja preta, nao uma sombra.
-- Com os caracteres de teletexto ela cai para 3 pixels na lateral e 3 na base. O resto da
-- celula fica com a cor do que ja estava desenhado ali, lida do proprio canvas, para a sombra
-- nao abrir um buraco quando cai em cima de outra janela.
--
-- Fica dentro do mesmo laco do compositor, entao janela de cima cobre a sombra da de baixo
-- sem precisar de z-order proprio.
local HALF_LEFT = string.char(128 + 1 + 4 + 16)   -- metade esquerda acesa
local THIRD_TOP = string.char(128 + 1 + 2)        -- terco de cima aceso

local function drawShadow(c, p)
    local bottom = p.y + (p.chrome and 1 or 0) + p.h - 1
    local maxY = wm.H - 1   -- nunca invade a taskbar
    local shadow = colors.toBlit(theme.shadowBg)

    local sx = p.x + p.w
    if sx <= wm.W then
        for y = p.y + 1, math.min(bottom + 1, maxY) do
            local _, _, bg = c.getLine(y)
            c.setCursorPos(sx, y)
            c.blit(HALF_LEFT, shadow, bg:sub(sx, sx))
        end
    end

    local n = math.min(p.w, wm.W - p.x)
    if bottom + 1 <= maxY and n > 0 then
        local _, _, bg = c.getLine(bottom + 1)
        c.setCursorPos(p.x + 1, bottom + 1)
        c.blit(string.rep(THIRD_TOP, n), string.rep(shadow, n), bg:sub(p.x + 1, p.x + n))
    end
end

function wm.render(procs, focus)
    local c = canvas
    c.setBackgroundColor(theme.desktopBg)
    c.setTextColor(theme.desktopFg)
    c.clear()
    -- `p.monitor` = o app esta desenhando numa parede, e o terminal dele nao e' mais a
    -- janela. Compor a janela aqui mostraria o ultimo quadro dela, congelado.
    local function desenha(p)
        -- Sem sombra na area de trabalho (e' o fundo) nem em tela pequena, onde
        -- cada coluna conta.
        if not p.bottom and not wm.tiny then drawShadow(c, p) end
        if p.chrome then drawTitle(c, p, p == focus) end
        p.win.setVisible(true)
        p.win.setVisible(false)
    end
    local function visivel(p)
        return p.win and not p.minimized and not p.hidden and not p.monitor
    end
    for _, p in ipairs(procs) do
        if visivel(p) and not p.popup then desenha(p) end
    end
    wm.drawTaskbar(procs, focus)
    drawToasts()
    -- Popup (menu Iniciar, menu de janela) vem DEPOIS do aviso, nao antes.
    -- Menu e aviso nascem no mesmo canto - em cima da barra de tarefas - e um aviso de
    -- passagem tapava um menu que a pessoa acabou de abrir e esta esperando para clicar.
    -- Entre informar e deixar clicar, ganha deixar clicar.
    for _, p in ipairs(procs) do
        if visivel(p) and p.popup then desenha(p) end
    end
    drawPointer()
    -- Canvas -> tela, linha a linha, so o que mudou.
    --
    -- O caminho obvio seria `c.setVisible(true); c.setVisible(false)`, mas a API window
    -- reempurra a paleta que ela fotografou do pai a cada redraw: seriam 16 setPaletteColour
    -- por quadro, desfazendo a paleta do Win95. Comparar as linhas evita isso e, de quebra,
    -- um quadro parado custa 1 blit (a linha do relogio) em vez de 19.
    for y = 1, wm.H do
        local text, fg, bg = c.getLine(y)
        local prev = wm.last[y]
        if not prev or prev[1] ~= text or prev[2] ~= fg or prev[3] ~= bg then
            root.setCursorPos(1, y)
            root.blit(text, fg, bg)
            wm.last[y] = { text, fg, bg }
        end
    end
    -- Cursor: so da janela focada, e so se a celula nao estiver coberta.
    local blink = false
    if not wm.pointer.on and focus and focus.win and not focus.minimized and not focus.hidden and not focus.monitor then
        local cx, cy = focus.win.getCursorPos()
        local ax, ay = focus.x + cx - 1, clientTop(focus) + cy - 1
        if cx >= 1 and cx <= focus.w and cy >= 1 and cy <= focus.h
            and ay < wm.H and wm.topAt(procs, ax, ay) == focus and focus.win.getCursorBlink() then
            root.setTextColor(focus.win.getTextColor())
            root.setCursorPos(ax, ay)
            blink = true
        end
    end
    root.setCursorBlink(blink)
end

-- Captura da tela composta (para o relay / dashboard).
function wm.screenshot()
    local lines = {}
    for y = 1, wm.H do
        local t, f, b = canvas.getLine(y)
        lines[y] = { t, f, b }
    end
    return { w = wm.W, h = wm.H, lines = lines }
end

function wm.screenshotText()
    local out = {}
    for y = 1, wm.H do out[y] = (canvas.getLine(y)) end
    return table.concat(out, "\n")
end

return wm
