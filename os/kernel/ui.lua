-- Toolkit de widgets (retained-mode) + dialogos modais.
-- Tudo desenha em term.current() (a janela do processo). Coordenadas de mouse ja chegam locais.
-- Uso basico:
--   local ui = mosaic.ui
--   local f = ui.form()
--   f:add(ui.label{ x = 2, y = 2, text = "Ola" })
--   f:add(ui.button{ x = 2, y = 4, text = "Sair", onClick = function() f:stop() end })
--   f:run()
local theme = require("kernel.theme")
local draw = require("kernel.draw")

local ui = {}

-- ---------------------------------------------------------------- helpers de texto
local function pad(s, w, align)
    s = tostring(s == nil and "" or s)
    if #s >= w then return s:sub(1, w) end
    local space = w - #s
    if align == "right" then return string.rep(" ", space) .. s end
    if align == "center" then
        local l = math.floor(space / 2)
        return string.rep(" ", l) .. s .. string.rep(" ", space - l)
    end
    return s .. string.rep(" ", space)
end
ui.pad = pad

function ui.wrap(text, w)
    local lines = {}
    for para in (tostring(text) .. "\n"):gmatch("(.-)\n") do
        local line = ""
        for word in para:gmatch("%S+") do
            while #word > w do
                if #line > 0 then lines[#lines + 1] = line line = "" end
                lines[#lines + 1] = word:sub(1, w)
                word = word:sub(w + 1)
            end
            if #line == 0 then line = word
            elseif #line + 1 + #word <= w then line = line .. " " .. word
            else lines[#lines + 1] = line line = word end
        end
        lines[#lines + 1] = line
    end
    return lines
end

local function pack(...) return { n = select("#", ...), ... } end

-- ---------------------------------------------------------------- atalhos por letra
-- O texto aceita "&": "&Salvar" marca o S. Nao existe sublinhado na grade de caracteres, entao
-- a letra so muda de cor ENQUANTO o Alt esta segurado, como no Windows moderno. Assim nao ha
-- ruido visual o tempo todo.
function ui.mnemonic(text)
    text = tostring(text or "")
    local at = text:find("&", 1, true)
    if not at or at >= #text then return (text:gsub("&&", "&")), nil, nil end
    local letter = text:sub(at + 1, at + 1)
    return text:sub(1, at - 1) .. text:sub(at + 1), letter:lower(), at
end

function ui.altHeld()
    return mosaic and mosaic.altHeld and mosaic.altHeld() or false
end

-- Escreve um rotulo destacando a letra do atalho quando o Alt esta segurado.
function ui.writeLabel(t, label, mark, fg, hotFg)
    if not mark or not ui.altHeld() then t.write(label) return end
    t.write(label:sub(1, mark - 1))
    t.setTextColor(hotFg or theme.accentFg)
    t.write(label:sub(mark, mark))
    t.setTextColor(fg)
    t.write(label:sub(mark + 1))
end


-- ---------------------------------------------------------------- ancoragem e layout
--
-- Antes disto, todo app reposicionava os widgets na mao no term_resize, e quem esquecia (ou
-- errava a conta) ficava com botao fora da tela. Agora o widget DECLARA onde quer ficar e o
-- form resolve sozinho sempre que o tamanho muda.
--
--   w = 20        20 colunas
--   w = -3        largura da janela menos 3
--   w = "fill"     largura inteira
--   right = 0     encosta na borda direita   (right = 2 fica 2 colunas antes)
--   bottom = 0    ultima linha               (bottom = 1 fica uma linha acima)
--   above = outro    a linha logo acima do widget `outro`
--   fillTo = outro   altura ate onde o widget `outro` comeca
--
-- As declaracoes ficam guardadas a parte, porque resolver em cima do valor ja resolvido
-- encolheria o widget a cada redimensionamento.
local function resolveSize(v, total)
    if v == "fill" then return total end
    if type(v) == "number" and v < 0 then return math.max(1, total + v) end
    return v
end

local LAYOUT_KEYS = { "right", "bottom", "above", "fillTo" }

local function captureLayout(w)
    local lay
    for _, k in ipairs(LAYOUT_KEYS) do
        if w[k] ~= nil then lay = lay or {} lay[k] = w[k] end
    end
    if w.w == "fill" or (type(w.w) == "number" and w.w < 0) then lay = lay or {} lay.w = w.w end
    if w.h == "fill" or (type(w.h) == "number" and w.h < 0) then lay = lay or {} lay.h = w.h end
    w._lay = lay
end

-- ---------------------------------------------------------------- base
local Widget = {}
Widget.__index = Widget
function Widget:contains(x, y)
    return x >= self.x and x < self.x + (self.w or 1) and y >= self.y and y < self.y + (self.h or 1)
end
function Widget:draw() end
function Widget:onMouse() end
function Widget:onKey() end
function Widget:onChar() end
function Widget:onPaste() end
function Widget:invalidate() if self.form then self.form.dirty = true end end

local function newWidget(kind, opts, defaults)
    local w = setmetatable(opts or {}, kind)
    for k, v in pairs(defaults or {}) do if w[k] == nil then w[k] = v end end
    w.x, w.y = w.x or 1, w.y or 1
    return w
end

-- ---------------------------------------------------------------- Label
local Label = setmetatable({}, Widget) Label.__index = Label
function Label:draw(t)
    t.setCursorPos(self.x, self.y)
    t.setTextColor(self.fg or self.form.fg)
    t.setBackgroundColor(self.bg or self.form.bg)
    local s = tostring(self.text or "")
    if self.w then s = pad(s, self.w, self.align) end
    t.write(s)
end
function ui.label(o) return newWidget(Label, o, { h = 1 }) end

-- ---------------------------------------------------------------- Text (paragrafo com wrap)
local Text = setmetatable({}, Widget) Text.__index = Text
function Text:draw(t)
    t.setTextColor(self.fg or self.form.fg)
    t.setBackgroundColor(self.bg or self.form.bg)
    local lines = ui.wrap(self.text or "", self.w)
    self.scroll = math.max(0, math.min(self.scroll or 0, #lines - self.h))
    for i = 1, self.h do
        t.setCursorPos(self.x, self.y + i - 1)
        t.write(pad(lines[i + self.scroll] or "", self.w))
    end
    -- Texto rolavel e focavel, mas nao tinha nenhum sinal de foco. A barra na ultima coluna
    -- acende quando ele esta com o foco, e so aparece se houver o que rolar.
    if #lines > self.h then
        local focused = self.form and self.form.focused == self
        local barH = math.max(1, math.floor(self.h * self.h / #lines))
        local barY = math.floor(self.scroll / math.max(1, #lines - self.h) * (self.h - barH) + 0.5)
        for i = 0, self.h - 1 do
            t.setCursorPos(self.x + self.w - 1, self.y + i)
            local on = i >= barY and i < barY + barH
            t.setBackgroundColor(on and (focused and theme.accent or theme.face) or theme.shadow)
            t.write(" ")
        end
    end
end
function Text:onMouse(ev, btn, lx, ly, dir)
    if ev == "mouse_scroll" then self.scroll = (self.scroll or 0) + dir self:invalidate() end
end
function Text:onKey(code)
    if code == keys.down then self.scroll = (self.scroll or 0) + 1 self:invalidate()
    elseif code == keys.up then self.scroll = (self.scroll or 0) - 1 self:invalidate() end
end
function ui.text(o) return newWidget(Text, o, { w = 20, h = 3, focusable = true, scrollable = true }) end

-- ---------------------------------------------------------------- Button
local Button = setmetatable({}, Widget) Button.__index = Button
function Button:draw(t)
    local focused = self.form.focused == self
    local bg = self.bg or (self.alt and theme.buttonAltBg or theme.buttonBg)
    local fg = self.fg or (self.alt and theme.buttonAltFg or theme.buttonFg)
    if self.disabled then bg, fg = theme.face, theme.shadow end
    -- Sem hover no CC, o foco tem que aparecer de outro jeito. Inverter as cores custa zero
    -- celula, enquanto os colchetes de antes roubavam duas do texto.
    if focused and not self.disabled then bg, fg = theme.selBg, theme.selFg end
    t.setCursorPos(self.x, self.y)
    t.setBackgroundColor(bg)
    t.setTextColor(fg)
    -- O texto ocupa o miolo; as duas pontas ficam para o relevo.
    local label, _, mark = ui.mnemonic(self.text)
    local padded = pad(label, self.w - 2, "center")
    local shift = padded:find(label, 1, true)
    t.write(" ")
    ui.writeLabel(t, padded, mark and shift and (mark + shift - 1) or nil, fg, theme.toastBg)
    t.setTextColor(fg)
    t.write(" ")
    draw.caps(t, self.x, self.y, self.w, bg, not self.pressed)
end
function Button:width() return self.w or (#tostring(self.text) + 2) end
function Button:onMouse(ev)
    if ev == "mouse_click" and not self.disabled then
        -- Pintar o estado pressionado tem que passar pelo form: o Form:draw desloca w.y pelo
        -- scroll, e desenhar direto daqui erraria a linha num formulario rolado.
        self.pressed = true
        if self.form then self.form:draw() end
        if self.onClick then self.onClick(self) end
        -- Se o onClick abriu um modal, o mouse_up foi para o modal e nunca chega aqui.
        self.pressed = false
        self:invalidate()
    elseif ev == "mouse_up" then
        self.pressed = false
        self:invalidate()
    end
end
function Button:onKey(code)
    if (code == keys.enter or code == keys.numPadEnter or code == keys.space)
        and not self.disabled and self.onClick then self.onClick(self) end
end
function Button:activate() if not self.disabled and self.onClick then self.onClick(self) end end
function ui.button(o)
    local b = newWidget(Button, o, { h = 1, focusable = true })
    b.w = b.w or (#(ui.mnemonic(b.text)) + 2)   -- as duas pontas viram o relevo
    return b
end

-- ---------------------------------------------------------------- Textbox
local Textbox = setmetatable({}, Widget) Textbox.__index = Textbox
function Textbox:draw(t)
    self.text = self.text or ""
    self.cursor = math.max(0, math.min(self.cursor or #self.text, #self.text))
    local inner = self.w - 2       -- as pontas ficam para o relevo afundado
    if self.cursor - (self.scroll or 0) >= inner then self.scroll = self.cursor - inner + 1 end
    if self.cursor < (self.scroll or 0) then self.scroll = self.cursor end
    self.scroll = self.scroll or 0
    t.setCursorPos(self.x + 1, self.y)
    t.setBackgroundColor(self.bg or theme.inputBg)
    t.setTextColor(self.fg or theme.inputFg)
    local shown = self.text
    if self.mask then shown = string.rep(self.mask, #shown) end
    shown = shown:sub(self.scroll + 1, self.scroll + inner)
    if #self.text == 0 and self.placeholder and self.form.focused ~= self then
        t.setTextColor(theme.mutedFg)
        shown = self.placeholder
    end
    t.write(pad(shown, inner))
    -- Campo de texto no Win95 e sempre afundado.
    draw.caps(t, self.x, self.y, self.w, self.bg or theme.inputBg, false)
end
function Textbox:placeCursor(t)
    t.setTextColor(self.fg or theme.inputFg)
    t.setCursorPos(self.x + 1 + self.cursor - self.scroll, self.y)
    t.setCursorBlink(true)
end
function Textbox:setText(s)
    self.text = tostring(s or "")
    self.cursor = #self.text
    self:invalidate()
end
function Textbox:insert(s)
    s = tostring(s):gsub("[\r\n]", "")
    if self.maxLen and #self.text + #s > self.maxLen then s = s:sub(1, self.maxLen - #self.text) end
    self.text = self.text:sub(1, self.cursor) .. s .. self.text:sub(self.cursor + 1)
    self.cursor = self.cursor + #s
    if self.onChange then self.onChange(self, self.text) end
    self:invalidate()
end
function Textbox:onChar(ch) self:insert(ch) end
function Textbox:onPaste(s) self:insert(s) end
function Textbox:onKey(code)
    local changed = false
    if code == keys.backspace and self.cursor > 0 then
        self.text = self.text:sub(1, self.cursor - 1) .. self.text:sub(self.cursor + 1)
        self.cursor = self.cursor - 1 changed = true
    elseif code == keys.delete and self.cursor < #self.text then
        self.text = self.text:sub(1, self.cursor) .. self.text:sub(self.cursor + 2) changed = true
    elseif code == keys.left then self.cursor = math.max(0, self.cursor - 1)
    elseif code == keys.right then self.cursor = math.min(#self.text, self.cursor + 1)
    elseif code == keys.home then self.cursor = 0
    elseif code == keys["end"] then self.cursor = #self.text
    elseif code == keys.enter or code == keys.numPadEnter then
        if self.onEnter then self.onEnter(self, self.text) end
    else return end
    if changed and self.onChange then self.onChange(self, self.text) end
    self:invalidate()
end
function Textbox:onMouse(ev, btn, lx)
    if ev == "mouse_click" then
        self.cursor = math.max(0, math.min(#(self.text or ""), (self.scroll or 0) + lx - 2))
        self:invalidate()
    end
end
function ui.textbox(o)
    -- takesEnter: o Enter e' do widget, nao do botao padrao do formulario.
    return newWidget(Textbox, o, { w = 16, h = 1, focusable = true, text = "", takesEnter = true })
end

-- ---------------------------------------------------------------- List
local List = setmetatable({}, Widget) List.__index = List
function List:itemText(item)
    if self.render then return self.render(item) end
    if type(item) == "table" then return tostring(item.text or item.name or item.label or item[1] or "?") end
    return tostring(item)
end
function List:setItems(items, keepSelection)
    self.items = items or {}
    if not keepSelection then self.selected = #self.items > 0 and 1 or nil end
    if self.selected and self.selected > #self.items then self.selected = #self.items end
    if self.selected == 0 then self.selected = nil end
    self:invalidate()
end
function List:getSelected() return self.selected and self.items[self.selected] or nil end
function List:ensureVisible()
    self.scroll = self.scroll or 0
    if not self.selected then return end
    if self.selected - 1 < self.scroll then self.scroll = self.selected - 1 end
    if self.selected > self.scroll + self.h then self.scroll = self.selected - self.h end
end
function List:draw(t)
    self.items = self.items or {}
    self.scroll = math.max(0, math.min(self.scroll or 0, math.max(0, #self.items - self.h)))
    local focused = self.form.focused == self
    for i = 1, self.h do
        local idx = i + self.scroll
        local item = self.items[idx]
        t.setCursorPos(self.x, self.y + i - 1)
        local sel = idx == self.selected
        if sel then
            t.setBackgroundColor(focused and theme.selBg or theme.mutedFg)
            t.setTextColor(theme.selFg)
        else
            t.setBackgroundColor(self.bg or theme.inputBg)
            t.setTextColor(self.fg or theme.inputFg)
            -- Cabecalho de secao no fundo do chrome: destaca sem parecer selecionado.
            if type(item) == "table" and item.header then t.setBackgroundColor(theme.face) end
            if type(item) == "table" and item.fg then t.setTextColor(item.fg) end
        end
        local s = item ~= nil and self:itemText(item) or ""
        if type(item) == "table" and item.separator then s = string.rep("-", self.w) end
        t.write(pad(s, self.w))
    end
    if #self.items > self.h then
        -- barra de rolagem simples na ultima coluna
        local barH = math.max(1, math.floor(self.h * self.h / #self.items))
        local barY = math.floor(self.scroll / math.max(1, #self.items - self.h) * (self.h - barH) + 0.5)
        for i = 0, self.h - 1 do
            t.setCursorPos(self.x + self.w - 1, self.y + i)
            local on = i >= barY and i < barY + barH
            t.setBackgroundColor(on and theme.face or theme.shadow)
            t.write(" ")
        end
    end
end
-- Separador e cabecalho de secao existem para ler, nao para escolher.
local function selectable(item)
    return not (type(item) == "table" and (item.separator or item.header))
end

function List:select(idx, activate)
    if #self.items == 0 then self.selected = nil return end
    idx = math.max(1, math.min(idx, #self.items))
    if not selectable(self.items[idx]) then
        -- So' recusar o indice travava a seta em cima do separador: o usuario apertava
        -- para baixo e nada acontecia. Anda na mesma direcao ate achar item de verdade,
        -- e se nao houver, volta procurando para o outro lado.
        local step = (self.selected and idx < self.selected) and -1 or 1
        local j = idx + step
        while j >= 1 and j <= #self.items and not selectable(self.items[j]) do j = j + step end
        if j < 1 or j > #self.items then
            j = idx - step
            while j >= 1 and j <= #self.items and not selectable(self.items[j]) do j = j - step end
        end
        if j < 1 or j > #self.items then return end
        idx = j
    end
    local item = self.items[idx]
    local changed = idx ~= self.selected
    self.selected = idx
    self:ensureVisible()
    if changed and self.onSelect then self.onSelect(self, item, idx) end
    if activate and self.onActivate then self.onActivate(self, item, idx) end
    self:invalidate()
end
function List:onMouse(ev, btn, lx, ly, dir)
    if ev == "mouse_scroll" then
        self.scroll = (self.scroll or 0) + dir
        self:invalidate()
    elseif ev == "mouse_click" then
        local idx = (self.scroll or 0) + ly
        if idx > #(self.items or {}) then
            -- Espaco vazio depois do ultimo item: e' onde vai o menu "colar / nova pasta".
            -- Sem isto o clique morria aqui e o app nem ficava sabendo. (Mesmo papel do
            -- onEmpty do iconview.)
            if self.onEmpty then self.onEmpty(self, btn, lx, ly) end
            return
        end
        local now = os.clock()
        local dbl = self.lastClick and self.lastClickIdx == idx and now - self.lastClick < 0.5
        self.lastClick, self.lastClickIdx = now, idx
        if btn == 2 and self.onContext then
            self:select(idx)
            self.onContext(self, self.items[idx], idx, lx, ly)
        else
            self:select(idx, dbl or self.activateOnClick)
        end
    end
end
function List:onKey(code)
    if not self.selected then if #(self.items or {}) > 0 then self:select(1) end return end
    if code == keys.down then self:select(self.selected + 1)
    elseif code == keys.up then self:select(self.selected - 1)
    elseif code == keys.pageDown then self:select(self.selected + self.h)
    elseif code == keys.pageUp then self:select(self.selected - self.h)
    elseif code == keys.home then self:select(1)
    elseif code == keys["end"] then self:select(#self.items)
    elseif code == keys.enter or code == keys.numPadEnter then self:select(self.selected, true) end
end
function ui.list(o)
    local l = newWidget(List, o, { w = 20, h = 5, focusable = true, scrollable = true, items = {}, takesEnter = true })
    if l.selected == nil and #l.items > 0 then l.selected = 1 end
    return l
end

-- ---------------------------------------------------------------- IconView
-- Grade de icones. Desenha a area de trabalho e as janelas de pasta: as duas mostram a
-- mesma coisa (o conteudo de uma pasta), entao mostram do mesmo jeito.
--
-- Cada entrada e' { name = , icon = , path = , isDir = , spec = }. Quem monta a lista e' o
-- app; este widget so' posiciona, seleciona e avisa.
local icons = require("lib.icons")

local IconView = setmetatable({}, Widget) IconView.__index = IconView
-- 12 de largura deixa 11 colunas para o nome, o suficiente para "Perifericos".
-- Altura: 4 linhas de icone + 1 de nome.
IconView.ICON_W, IconView.ICON_H = 12, 5
local ICON_DX = math.floor((IconView.ICON_W - 1 - icons.COLS) / 2)

function IconView:cols() return math.max(1, math.floor(self.w / self.ICON_W)) end
function IconView:visibleRows() return math.max(1, math.floor(self.h / self.ICON_H)) end
function IconView:rowCount() return math.ceil(#(self.entries or {}) / self:cols()) end
function IconView:maxScroll() return math.max(0, self:rowCount() - self:visibleRows()) end

function IconView:setEntries(list, keepSelection)
    self.entries = list or {}
    if not keepSelection then self.selected = #self.entries > 0 and 1 or nil end
    if self.selected and self.selected > #self.entries then self.selected = #self.entries end
    if self.selected == 0 then self.selected = nil end
    self:ensureVisible()
    self:invalidate()
end

function IconView:getSelected() return self.selected and self.entries[self.selected] or nil end

function IconView:ensureVisible()
    self.scroll = self.scroll or 0
    if not self.selected then return end
    local row = math.floor((self.selected - 1) / self:cols())
    if row < self.scroll then self.scroll = row end
    if row >= self.scroll + self:visibleRows() then self.scroll = row - self:visibleRows() + 1 end
end

function IconView:select(idx, activate)
    if #(self.entries or {}) == 0 then self.selected = nil return end
    idx = math.max(1, math.min(idx, #self.entries))
    local changed = idx ~= self.selected
    self.selected = idx
    self:ensureVisible()
    if changed and self.onSelect then self.onSelect(self, self.entries[idx], idx) end
    if activate and self.onActivate then self.onActivate(self, self.entries[idx], idx) end
    self:invalidate()
end

-- Canto do icone `i` na tela, ou nil se ele estiver fora da parte visivel.
function IconView:slotAt(i)
    local cols = self:cols()
    local row = math.floor((i - 1) / cols) - (self.scroll or 0)
    if row < 0 or row >= self:visibleRows() then return nil end
    return self.x + ((i - 1) % cols) * self.ICON_W, self.y + row * self.ICON_H
end

-- x, y em coordenadas do formulario.
function IconView:indexAt(x, y)
    for i = 1, #(self.entries or {}) do
        local ix, iy = self:slotAt(i)
        -- A area clicavel inclui a linha do nome: e' o alvo maior e o mais obvio de acertar.
        if ix and x >= ix and x < ix + self.ICON_W - 1 and y >= iy and y <= iy + icons.ROWS then
            return i
        end
    end
    return nil
end

function IconView:draw(t)
    self.entries = self.entries or {}
    self.scroll = math.max(0, math.min(self.scroll or 0, self:maxScroll()))
    local focused = self.form.focused == self
    local bg = self.bg or self.form.bg
    for i, e in ipairs(self.entries) do
        local ix, iy = self:slotAt(i)
        if ix then
            icons.draw(t, e.icon, ix + ICON_DX, iy, bg)
            t.setCursorPos(ix, iy + icons.ROWS)
            local sel = i == self.selected
            t.setBackgroundColor(sel and (focused and theme.selBg or theme.mutedFg) or bg)
            t.setTextColor(sel and theme.selFg or (self.fg or self.form.fg))
            t.write(pad(e.name, self.ICON_W - 1, "center"))
        end
    end
end

function IconView:onMouse(ev, btn, lx, ly, dir)
    if ev == "mouse_scroll" then
        self.scroll = math.max(0, math.min((self.scroll or 0) + dir, self:maxScroll()))
        self:invalidate()
        return
    end
    if ev ~= "mouse_click" then return end
    local x, y = self.x + lx - 1, self.y + ly - 1
    local i = self:indexAt(x, y)
    if not i then
        self:invalidate()
        if self.onEmpty then self.onEmpty(self, btn, x, y) end
        return
    end
    -- Clique duplo abre, clique simples so' seleciona: sem isso nao da para escolher um
    -- icone para renomear ou apagar sem abrir o programa junto.
    local now = os.clock()
    local dbl = self.lastClick and self.lastClickIdx == i and now - self.lastClick < 0.5
    self.lastClick, self.lastClickIdx = now, i
    if btn == 2 then
        self:select(i)
        if self.onContext then self.onContext(self, self.entries[i], i, x, y) end
    else
        self:select(i, dbl or self.activateOnClick)
    end
end

function IconView:onKey(code)
    local n = #(self.entries or {})
    if n == 0 then return end
    if not self.selected then self:select(1) return end
    local cols, page = self:cols(), self:cols() * self:visibleRows()
    if code == keys.left then self:select(self.selected - 1)
    elseif code == keys.right then self:select(self.selected + 1)
    elseif code == keys.up then self:select(self.selected - cols)
    elseif code == keys.down then self:select(self.selected + cols)
    elseif code == keys.pageUp then self:select(self.selected - page)
    elseif code == keys.pageDown then self:select(self.selected + page)
    elseif code == keys.home then self:select(1)
    elseif code == keys["end"] then self:select(n)
    elseif code == keys.enter or code == keys.numPadEnter then self:select(self.selected, true)
    end
end

function ui.iconview(o)
    local v = newWidget(IconView, o, { w = 20, h = 10, focusable = true, scrollable = true,
        entries = {}, takesEnter = true, scroll = 0 })
    if v.selected == nil and #v.entries > 0 then v.selected = 1 end
    return v
end

-- ---------------------------------------------------------------- Checkbox
local Checkbox = setmetatable({}, Widget) Checkbox.__index = Checkbox
function Checkbox:draw(t)
    local focused = self.form.focused == self
    t.setCursorPos(self.x, self.y)
    -- Foco = cores invertidas, a mesma regra do botao e da lista.
    local bg = focused and theme.selBg or (self.bg or self.form.bg)
    local fg = focused and theme.selFg or (self.fg or self.form.fg)
    t.setBackgroundColor(bg)
    t.setTextColor(fg)
    local label, _, mark = ui.mnemonic(self.text or "")
    t.write(self.checked and "[x] " or "[ ] ")
    ui.writeLabel(t, label, mark, fg, theme.toastBg)
end
function Checkbox:toggle()
    self.checked = not self.checked
    if self.onChange then self.onChange(self, self.checked) end
    self:invalidate()
end
function Checkbox:onMouse(ev) if ev == "mouse_click" then self:toggle() end end
function Checkbox:onKey(code)
    if code == keys.space or code == keys.enter or code == keys.numPadEnter then self:toggle() end
end
function Checkbox:activate() self:toggle() end
function ui.checkbox(o)
    local c = newWidget(Checkbox, o, { h = 1, focusable = true })
    c.w = c.w or (#(ui.mnemonic(c.text or "")) + 4)
    return c
end

-- ---------------------------------------------------------------- Group (caixa de grupo)
-- Agrupa campos que tratam do mesmo assunto, com titulo na borda. Nao captura clique nem
-- foco: e so a moldura; os campos continuam sendo filhos do form, posicionados por dentro.
local Group = setmetatable({}, Widget) Group.__index = Group
function Group:draw(t)
    draw.etched(t, self.x, self.y, self.w, self.h, self.bg or self.form.bg, self.text)
end
function ui.group(o) return newWidget(Group, o, { w = 20, h = 3 }) end

-- ---------------------------------------------------------------- Progress
local Progress = setmetatable({}, Widget) Progress.__index = Progress
function Progress:draw(t)
    local max = self.max or 1
    local frac = max > 0 and math.max(0, math.min(1, (self.value or 0) / max)) or 0
    local filled = math.floor(frac * self.w + 0.5)
    t.setCursorPos(self.x, self.y)
    t.setBackgroundColor(self.fg or theme.accent)
    t.write(string.rep(" ", filled))
    t.setBackgroundColor(self.bg or theme.face)
    t.write(string.rep(" ", self.w - filled))
    draw.caps(t, self.x, self.y, self.w, self.bg or theme.face, false)
    if self.label then
        local s = pad(self.label, self.w, "center")
        t.setCursorPos(self.x, self.y)
        for i = 1, #s do
            t.setBackgroundColor(i <= filled and (self.fg or theme.accent) or (self.bg or theme.face))
            t.setTextColor(colors.white)
            t.write(s:sub(i, i))
        end
    end
end
function ui.progress(o) return newWidget(Progress, o, { w = 10, h = 1, value = 0, max = 1 }) end

-- ---------------------------------------------------------------- Dropdown
local Dropdown = setmetatable({}, Widget) Dropdown.__index = Dropdown
function Dropdown:current()
    local item = self.items[self.selected or 1]
    return item ~= nil and List.itemText(self, item) or ""
end
function Dropdown:draw(t)
    local focused = self.form and self.form.focused == self
    t.setCursorPos(self.x + 1, self.y)
    t.setBackgroundColor(self.bg or theme.inputBg)
    t.setTextColor(self.fg or theme.inputFg)
    t.write(pad(self:current(), self.w - 3))
    -- A seta e' o botao: relevo alto, e acesa quando o widget tem o foco.
    t.setCursorPos(self.x + self.w - 2, self.y)
    t.setBackgroundColor(focused and theme.selBg or theme.face)
    t.setTextColor(focused and theme.selFg or theme.faceFg)
    t.write("v")
    draw.caps(t, self.x, self.y, self.w, self.bg or theme.inputBg, false)
end
function Dropdown:open()
    local idx = ui.menu(self.items, self.x, self.y + 1, self.w, { render = self.render })
    if idx then
        self.selected = idx
        if self.onChange then self.onChange(self, self.items[idx], idx) end
        self:invalidate()
    end
    if self.form then self.form.dirty = true end
end
function Dropdown:onMouse(ev) if ev == "mouse_click" then self:open() end end
function Dropdown:onKey(code)
    if code == keys.enter or code == keys.numPadEnter or code == keys.space then self:open() end
end
function Dropdown:activate() self:open() end
function ui.dropdown(o) return newWidget(Dropdown, o, { w = 12, h = 1, focusable = true, items = {}, selected = 1 }) end

-- ---------------------------------------------------------------- fila de botoes
-- Uma fila que se ajusta sozinha: quando os botoes nao cabem na largura, ela quebra para
-- CIMA, empilhando linhas a partir da ancora de baixo. Antes disso cada app montava a fila
-- na mao somando larguras, e o que passava da borda simplesmente sumia — foi assim que o
-- botao "Ir para" do Arquivos desapareceu numa tela de 51 colunas.
--
--   local barra = ui.row(f, { bottom = 1, items = {
--       { text = "&Abrir", onClick = abrir },
--       { text = "&Nova pasta", onClick = nova, alt = true },
--   } })
--   f:add(ui.list { x = 1, y = 2, w = "fill", fillTo = barra })
--
-- A fila entra no form antes da lista, porque o fillTo so enxerga quem ja foi adicionado.
local Row = setmetatable({}, Widget) Row.__index = Row

function Row:onLayout(W, H)
    local gap = self.gap or 1
    local x, lines = self.x, 1
    -- Primeira passada: descobre quantas linhas a fila vai ocupar.
    for _, b in ipairs(self.buttons) do
        if x > self.x and x + b.w - 1 > W then lines = lines + 1 x = self.x end
        x = x + b.w + gap
    end
    self.lines = lines
    self.h = lines
    self.y = math.max(1, H - (self.bottomAnchor or 0) - (lines - 1))
    -- Segunda: posiciona de verdade, agora que a altura e conhecida.
    local y = self.y
    x = self.x
    for _, b in ipairs(self.buttons) do
        if x > self.x and x + b.w - 1 > W then y = y + 1 x = self.x end
        b.x, b.y = x, y
        x = x + b.w + gap
    end
end

function Row:draw() end   -- quem desenha sao os botoes, que estao no form

function ui.row(f, opts)
    local r = newWidget(Row, {
        x = opts.x or 1, y = 1, w = 1, h = 1,
        gap = opts.gap, bottomAnchor = opts.bottom or 0,
        buttons = {}, lines = 1,
    })
    f:add(r)
    for _, spec in ipairs(opts.items or {}) do
        r.buttons[#r.buttons + 1] = f:add(ui.button(spec))
    end
    -- Posiciona ja, para quem consultar r.y logo depois (o fillTo da lista) ver o valor certo.
    local W, H = (f.term or term.current()).getSize()
    r:onLayout(W, H)
    return r
end

-- ---------------------------------------------------------------- Form
local Form = {}
Form.__index = Form

function ui.form(o)
    local f = setmetatable(o or {}, Form)
    f.widgets = {}
    f.bg = f.bg or theme.appBg
    f.fg = f.fg or theme.appFg
    f.dirty = true
    f.running = false
    f.term = f.term   -- opcional: desenhar em outro redirect
    return f
end

function Form:add(w)
    w.form = self
    captureLayout(w)
    self.widgets[#self.widgets + 1] = w
    if w.focusable and not self.focused and w.visible ~= false then self.focused = w end
    self.dirty = true
    return w
end

function Form:remove(w)
    for i, q in ipairs(self.widgets) do if q == w then table.remove(self.widgets, i) break end end
    if self.focused == w then self.focused = nil end
    self.dirty = true
end

-- Resolve as ancoras contra o tamanho atual. Roda na ordem em que os widgets foram
-- adicionados, entao `fillTo` so enxerga quem entrou antes — e por isso a barra de botoes
-- do rodape e adicionada antes da lista que vai ate ela.
function Form:layout(W, H)
    if not W then W, H = (self.term or term.current()).getSize() end
    self.lastW, self.lastH = W, H
    for _, w in ipairs(self.widgets) do
        local lay = w._lay
        if lay then
            if lay.w then w.w = resolveSize(lay.w, W) end
            if lay.h then w.h = resolveSize(lay.h, H) end
            if lay.bottom then w.y = math.max(1, H - lay.bottom) end
            if lay.above then w.y = math.max(1, lay.above.y - (w.h or 1)) end
            if lay.right then w.x = math.max(1, W - (w.w or 1) + 1 - lay.right) end
            if lay.fillTo then w.h = math.max(1, lay.fillTo.y - w.y) end
        end
        if w.onLayout then w:onLayout(W, H) end
    end
    -- Widget escondido nao pode ficar com o foco: o teclado sumiria dentro dele sem
    -- nenhum sinal na tela. Acontece com a barra lateral do Arquivos, que some no F9 e
    -- em tela estreita — e o `visible` dela e decidido agora, dentro do onLayout acima.
    local foc = self.focused
    if foc and (foc.visible == false or foc.disabled) then
        self.focused = nil
        self:focusNext(1)
    end
end

function Form:clear()
    self.widgets = {}
    self.focused = nil
    self.dirty = true
end

-- Rolagem do form: os widgets continuam com coordenadas absolutas, o form e' que tem
-- um viewport. Serve para formularios mais altos que a janela (ex.: Configuracoes).
function Form:viewHeight()
    local _, h = (self.term or term.current()).getSize()
    return h
end

-- Widget com `pinned = true` fica preso na tela: nao rola com o conteudo e nao
-- conta para a altura rolavel. Serve para barra de navegacao e rodape.
function Form:contentHeight()
    local bottom = 0
    for _, w in ipairs(self.widgets) do
        if w.visible ~= false and not w.pinned then
            local b = w.y + (w.h or 1) - 1
            if b > bottom then bottom = b end
        end
    end
    return bottom
end

function Form:maxScroll(H)
    return math.max(0, self:contentHeight() - (H or self:viewHeight()))
end

function Form:scrollTo(n, H)
    local s = math.max(0, math.min(n, self:maxScroll(H)))
    if s ~= (self.scroll or 0) then self.scroll = s self.dirty = true end
    return s
end

-- Traz o widget para dentro do viewport; sem isso o Tab manda o foco para fora da tela.
function Form:reveal(w)
    if not w or w.pinned then return end
    local H = self:viewHeight()
    local off = self.scroll or 0
    if w.y - off < 1 then self:scrollTo(w.y - 1, H)
    elseif w.y + (w.h or 1) - 1 - off > H then self:scrollTo(w.y + (w.h or 1) - 1 - H, H) end
end

function Form:setFocus(w)
    if self.focused == w then return end
    self.focused = w
    self:reveal(w)
    self.dirty = true
end

function Form:focusNext(dir)
    dir = dir or 1
    local n = #self.widgets
    if n == 0 then return end
    local start = 1
    for i, w in ipairs(self.widgets) do if w == self.focused then start = i break end end
    for k = 1, n do
        local i = ((start - 1 + dir * k) % n) + 1
        local w = self.widgets[i]
        if w.focusable and w.visible ~= false and not w.disabled then self:setFocus(w) return end
    end
end

-- Barra de rolagem do form, na ultima coluna. Mesmo desenho que o ui.list usa.
function Form:drawScrollbar(t, W, H, off)
    local content = self:contentHeight()
    if content <= H then return end
    local barH = math.max(1, math.floor(H * H / content))
    local barY = math.floor(off / math.max(1, content - H) * (H - barH) + 0.5)
    for i = 0, H - 1 do
        t.setCursorPos(W, i + 1)
        -- Face sobre sombra, igual a barra da lista: com o azul de destaque a barra pesava
        -- mais que o conteudo do formulario.
        t.setBackgroundColor((i >= barY and i < barY + barH) and theme.face or theme.shadow)
        t.write(" ")
    end
end

function Form:draw()
    local t = self.term or term.current()
    local W, H = t.getSize()
    if W ~= self.lastW or H ~= self.lastH then self:layout(W, H) end
    local W, H = t.getSize()
    t.setCursorBlink(false)
    if self.clear ~= false then
        t.setBackgroundColor(self.bg)
        t.setTextColor(self.fg)
        t.clear()
    end
    if self.onDraw then self.onDraw(self, t) end
    local off = math.max(0, math.min(self.scroll or 0, self:maxScroll(H)))
    self.scroll = off
    -- ponytail: desloca o y do widget so' durante o desenho e devolve em seguida. Custa uma
    -- mutacao temporaria, mas nenhum widget precisa saber que o form rola.
    for _, w in ipairs(self.widgets) do
        if w.visible ~= false then
            local y0 = w.y
            w.y = y0 - (w.pinned and 0 or off)
            if w.y + (w.h or 1) - 1 >= 1 and w.y <= H then w:draw(t) end
            w.y = y0
        end
    end
    self:drawScrollbar(t, W, H, off)
    if self.focused and self.focused.placeCursor and self.focused.visible ~= false then
        local y0 = self.focused.y
        self.focused.y = y0 - (self.focused.pinned and 0 or off)
        if self.focused.y >= 1 and self.focused.y <= H then self.focused:placeCursor(t) end
        self.focused.y = y0
    end
    self.dirty = false
end

-- y = coordenada no espaco do conteudo; rawY = coordenada na tela. Widget preso
-- (pinned) vive na tela, os outros no conteudo.
function Form:widgetAt(x, y, rawY)
    for i = #self.widgets, 1, -1 do
        local w = self.widgets[i]
        if w.visible ~= false and w:contains(x, w.pinned and (rawY or y) or y) then return w end
    end
    return nil
end

-- Linha do widget para traduzir o clique: preso usa a da tela, o resto a do conteudo.
local function localY(w, y, rawY)
    return (w.pinned and (rawY or y) or y) - w.y + 1
end

-- Alt+letra: procura o widget visivel com aquele atalho e aciona.
-- O casamento e' pelo codigo da tecla e nao pelo evento char, porque Alt+letra nem sempre
-- gera char no CC.
function Form:pressMnemonic(code)
    for _, w in ipairs(self.widgets) do
        if w.visible ~= false and not w.disabled and w.activate and w.text then
            local _, letter = ui.mnemonic(w.text)
            if letter and keys[letter] == code then
                if w.focusable then self:setFocus(w) end
                w:activate()
                return true
            end
        end
    end
    return false
end

function Form:handle(ev, a, b, c)
    -- Coordenada do mouse chega na tela; os widgets vivem no espaco do conteudo.
    local rawC = c
    if ev == "mouse_click" or ev == "mouse_drag" or ev == "mouse_up" or ev == "mouse_scroll" then
        c = (c or 0) + (self.scroll or 0)
    end
    if ev == "mouse_click" then
        local w = self:widgetAt(b, c, rawC)
        self.mouseTarget = w
        if w then
            if w.focusable and not w.disabled then self:setFocus(w) end
            w:onMouse(ev, a, b - w.x + 1, localY(w, c, rawC))
        elseif self.onClickEmpty then
            self.onClickEmpty(self, a, b, c)
        end
        return true
    elseif ev == "mouse_drag" or ev == "mouse_up" then
        local w = self.mouseTarget
        if w then w:onMouse(ev, a, b - w.x + 1, localY(w, c, rawC)) end
        if ev == "mouse_up" then self.mouseTarget = nil end
        return true
    elseif ev == "mouse_scroll" then
        -- So' widget que rola de verdade consome; senao o form inteiro rola (um label
        -- embaixo do cursor nao pode engolir a roda do mouse).
        local w = self:widgetAt(b, c, rawC)
        if w and w.scrollable then w:onMouse(ev, nil, b - w.x + 1, localY(w, c, rawC), a) return true end
        if self:maxScroll() > 0 then self:scrollTo((self.scroll or 0) + a) return true end
    elseif ev == "key" then
        if a == keys.tab then
            self:focusNext(self.shiftHeld and -1 or 1)
            return true
        elseif a == keys.leftShift or a == keys.rightShift then
            self.shiftHeld = true
        elseif a == keys.leftAlt or a == keys.rightAlt then
            self.dirty = true          -- as letras de atalho acendem enquanto o Alt esta preso
        elseif ui.altHeld() and self:pressMnemonic(a) then
            return true
        elseif (a == keys.enter or a == keys.numPadEnter) and self.defaultButton
            and not (self.focused and self.focused.takesEnter) then
            self.defaultButton:activate()
            return true
        elseif a == keys.escape and self.cancelButton then
            self.cancelButton:activate()
            return true
        end
        if self.focused and not self.focused.disabled then self.focused:onKey(a, b) return true end
    elseif ev == "key_up" then
        if a == keys.leftShift or a == keys.rightShift then self.shiftHeld = false end
        if a == keys.leftAlt or a == keys.rightAlt then self.dirty = true end
    elseif ev == "char" then
        if self.focused and not self.focused.disabled then self.focused:onChar(a) return true end
    elseif ev == "paste" then
        if self.focused and not self.focused.disabled then self.focused:onPaste(a) return true end
    elseif ev == "term_resize" then
        self:layout()
        if self.onResize then self.onResize(self) end
        self.dirty = true
        return true
    end
    return false
end

-- Loop principal. onEvent(f, ev, ...) recebe TODOS os eventos (timers, rednet, etc) antes dos widgets.
function Form:run()
    self.running = true
    while self.running do
        if self.dirty then self:draw() end
        local ev = pack(os.pullEvent())
        if self.onEvent then
            if self.onEvent(self, table.unpack(ev, 1, ev.n)) == true then
                -- consumido
            else
                self:handle(table.unpack(ev, 1, ev.n))
            end
        else
            self:handle(table.unpack(ev, 1, ev.n))
        end
    end
end

function Form:stop() self.running = false end

-- ---------------------------------------------------------------- Dialogos modais
-- Abre uma janela filha centralizada em term.current(), roda um form nela e restaura o fundo.
-- opts: { title, w, h, build = function(f, win, dlg) end, x, y }
-- Retorna o que dlg.result contiver ao fechar.
function ui.dialog(opts)
    local parent = term.current()
    local pw, ph = parent.getSize()
    local w = math.min(opts.w or 30, pw)
    local h = math.min(opts.h or 8, ph)
    local x = opts.x or math.floor((pw - w) / 2) + 1
    local y = opts.y or math.floor((ph - h) / 2) + 1
    -- salva o fundo
    local saved
    if parent.getLine then
        saved = {}
        for i = 0, h - 1 do
            if y + i <= ph then saved[i] = { parent.getLine(y + i) } end
        end
    end
    local win = window.create(parent, x, y, w, h, true)
    local dlg = { x = x, y = y, w = w, h = h, win = win }
    local f = ui.form { bg = opts.bg or theme.dialogBg, fg = opts.fg or theme.dialogFg, term = win }
    dlg.form = f
    local titleH = opts.title and 1 or 0
    f.onDraw = function(_, t)
        if opts.title then
            t.setCursorPos(1, 1)
            t.setBackgroundColor(theme.dialogTitleBg)
            t.setTextColor(theme.dialogTitleFg)
            t.write(pad(" " .. opts.title, w))
        end
    end
    dlg.contentY = titleH + 1
    function dlg.close(result) dlg.result = result f:stop() end
    if opts.build then opts.build(f, dlg) end
    -- loop proprio para converter coordenadas do mouse
    local prev = term.redirect(win)
    f.running = true
    while f.running do
        if f.dirty then f:draw() end
        local ev = pack(os.pullEvent())
        local name = ev[1]
        if name == "mouse_click" or name == "mouse_up" or name == "mouse_drag" or name == "mouse_scroll" then
            local mx, my = ev[3] - x + 1, ev[4] - y + 1
            local inside = mx >= 1 and mx <= w and my >= 1 and my <= h
            if inside then
                f:handle(name, ev[2], mx, my)
            elseif name == "mouse_click" and opts.closeOnOutside then
                dlg.close(nil)
            end
        elseif name == "key" and ev[2] == keys.escape and opts.escape ~= false then
            dlg.close(nil)
        else
            if not (opts.onEvent and opts.onEvent(f, dlg, table.unpack(ev, 1, ev.n))) then
                f:handle(table.unpack(ev, 1, ev.n))
            end
        end
    end
    term.redirect(prev)
    win.setVisible(false)
    -- restaura o fundo
    if saved then
        for i = 0, h - 1 do
            local l = saved[i]
            if l then parent.setCursorPos(1, y + i) parent.blit(l[1], l[2], l[3]) end
        end
    end
    return dlg.result
end

-- Posiciona uma fila de botoes numa caixa de `width` colunas, quebrando quando nao cabe.
-- Devolve as posicoes e quantas linhas ocupou. Medir e posicionar tem de sair do MESMO
-- calculo: quando eram dois calculos separados, a estimativa reservava duas linhas e a
-- colocacao usava uma, e a fila subia para o topo do dialogo por cima do texto.
local function layoutButtons(buttons, width)
    local place, x, lines = {}, 1, 1
    for _, b in ipairs(buttons) do
        local bw = #(ui.mnemonic(b.text)) + 2
        if x > 1 and x + bw - 1 > width then lines = lines + 1 x = 1 end
        place[#place + 1] = { b = b, x = x, line = lines, w = bw }
        x = x + bw + 1
    end
    -- Numa unica linha os botoes ficam encostados a direita, como no Windows.
    if lines == 1 then
        local used = x - 2
        local shift = math.max(0, width - used)
        for _, it in ipairs(place) do it.x = it.x + shift end
    end
    return place, lines
end

-- Mede a caixa de um dialogo de texto+botoes, sempre dentro do que a janela comporta.
local function dialogBox(text, title, buttons, wantW)
    local pw, ph = term.current().getSize()
    local minW = 0
    for _, b in ipairs(buttons) do minW = minW + #(ui.mnemonic(b.text)) + 3 end
    local w = math.min(math.max(wantW or 0, math.min(minW, pw), 16), pw)
    local _, rows = layoutButtons(buttons, w)
    local textLines = text and #ui.wrap(text, math.max(1, w - 2)) or 0
    local titleH = title and 1 or 0
    local h = math.min(ph, math.max(titleH + textLines + rows + 1, titleH + rows + 1))
    return w, h, textLines, rows
end

local function buttonsRow(f, dlg, buttons)
    local place, lines = layoutButtons(buttons, dlg.w)
    local top = math.max(1, dlg.h - lines + 1)
    local made = {}
    for _, it in ipairs(place) do
        made[#made + 1] = f:add(ui.button {
            x = it.x, y = top + it.line - 1, text = it.b.text, alt = it.b.alt,
            onClick = function() dlg.close(it.b.value) end,
        })
    end
    f:setFocus(made[#made])
    -- Enter aciona o ultimo (OK/Sim), Esc o primeiro (Cancelar/Nao), como no Windows.
    f.defaultButton = made[#made]
    if #made > 1 then f.cancelButton = made[1] end
    return made
end

function ui.msgbox(text, title, opts)
    opts = opts or {}
    local buttons = { { text = opts.ok or "&OK", value = true } }
    local wanted = opts.w or math.max(24, #tostring(text) + 4)
    local w, h, _, rows = dialogBox(text, title, buttons, wanted)
    return ui.dialog {
        title = title or "Aviso", w = w, h = h,
        build = function(f, dlg)
            local top = dlg.contentY
            -- Altura minima 1: numa janela apertada o dialogo encolhe, mas nunca fica com
            -- area de texto negativa (antes disso o texto ia parar embaixo dos botoes).
            local space = math.max(1, dlg.h - rows - top + 1)
            f:add(ui.text { x = 2, y = top, w = math.max(1, w - 2), h = space, text = text })
            buttonsRow(f, dlg, buttons)
        end,
    }
end

function ui.confirm(text, title, opts)
    opts = opts or {}
    local buttons = {
        { text = opts.no or "&Nao", value = false, alt = true },
        { text = opts.yes or "&Sim", value = true },
    }
    local wanted = opts.w or math.max(28, #tostring(text) + 4)
    local w, h, _, rows = dialogBox(text, title, buttons, wanted)
    local r = ui.dialog {
        title = title or "Confirmar", w = w, h = h,
        build = function(f, dlg)
            local top = dlg.contentY
            local space = math.max(1, dlg.h - rows - top + 1)
            f:add(ui.text { x = 2, y = top, w = math.max(1, w - 2), h = space, text = text })
            buttonsRow(f, dlg, buttons)
        end,
    }
    return r == true
end

function ui.prompt(text, default, title, opts)
    opts = opts or {}
    local buttons = {
        { text = "&Cancelar", value = nil, alt = true },
        { text = "&OK", value = "__ok" },
    }
    -- O rotulo e o campo ocupam duas linhas alem do titulo e dos botoes.
    local w, h, _, rows = dialogBox(nil, title, buttons, opts.w or 34)
    h = math.min(h + 2, select(2, term.current().getSize()))
    return ui.dialog {
        title = title or "Digite", w = w, h = h,
        build = function(f, dlg)
            local top = dlg.contentY
            f:add(ui.label { x = 2, y = top, w = math.max(1, w - 2), text = tostring(text) })
            local tb = f:add(ui.textbox {
                x = 2, y = math.min(top + 1, dlg.h - rows - 1), w = math.max(3, w - 2),
                text = default or "", mask = opts.mask,
                onEnter = function(self) dlg.close(self.text) end,
            })
            buttonsRow(f, dlg, buttons)
            f:setFocus(tb)
            local close = dlg.close
            dlg.close = function(v) if v == "__ok" then v = tb.text end close(v) end
        end,
    }
end

-- Menu popup (lista) em (x, y). Retorna o indice escolhido ou nil.
function ui.menu(items, x, y, w, opts)
    opts = opts or {}
    local pw, ph = term.current().getSize()
    w = w or 16
    for _, it in ipairs(items) do
        local s = type(it) == "table" and tostring(it.text or it.name or it.label or it[1] or "") or tostring(it)
        w = math.max(w, #s + 2)
    end
    w = math.min(w, pw)
    local h = math.min(#items, ph - 1, opts.maxH or 10)
    if y + h - 1 > ph then y = math.max(1, ph - h + 1) end
    if x + w - 1 > pw then x = math.max(1, pw - w + 1) end
    return ui.dialog {
        x = x, y = y, w = w, h = h, closeOnOutside = true, bg = theme.dialogBg,
        build = function(f, dlg)
            local l = f:add(ui.list {
                x = 1, y = 1, w = w, h = h, items = items, render = opts.render, activateOnClick = true,
                bg = theme.face, fg = theme.faceFg,
                onActivate = function(_, _, idx) dlg.close(idx) end,
            })
            f:setFocus(l)
        end,
    }
end

-- Barra de progresso modal simples para tarefas longas: retorna { set(frac, label), close() }.
function ui.busy(title, text)
    local pw = term.current().getSize()
    local w = math.min(36, pw)
    local parent = term.current()
    local _, ph = parent.getSize()
    local x, y = math.floor((pw - w) / 2) + 1, math.floor((ph - 5) / 2) + 1
    local win = window.create(parent, x, y, w, 5, true)
    local f = ui.form { term = win, bg = theme.dialogBg, fg = theme.dialogFg }
    f:add(ui.label { x = 1, y = 1, w = w, text = " " .. (title or "Aguarde"), bg = theme.dialogTitleBg, fg = theme.dialogTitleFg })
    local lbl = f:add(ui.label { x = 2, y = 3, w = w - 2, text = text or "" })
    local bar = f:add(ui.progress { x = 2, y = 4, w = w - 2, value = 0, max = 1 })
    f:draw()
    return {
        set = function(frac, label)
            bar.value = frac or bar.value
            if label then lbl.text = label end
            f:draw()
        end,
        close = function() win.setVisible(false) end,
    }
end

return ui
