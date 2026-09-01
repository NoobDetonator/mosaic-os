-- Toolkit de widgets (retained-mode) + dialogos modais.
-- Tudo desenha em term.current() (a janela do processo). Coordenadas de mouse ja chegam locais.
-- Uso basico:
--   local ui = mosaic.ui
--   local f = ui.form()
--   f:add(ui.label{ x = 2, y = 2, text = "Ola" })
--   f:add(ui.button{ x = 2, y = 4, text = "Sair", onClick = function() f:stop() end })
--   f:run()
local theme = require("kernel.theme")

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
    if self.disabled then bg, fg = theme.mutedFg, theme.dialogBg end
    t.setCursorPos(self.x, self.y)
    t.setBackgroundColor(bg)
    t.setTextColor(fg)
    local label = " " .. tostring(self.text) .. " "
    if self.w then label = pad(self.text, self.w, "center") end
    if focused and not self.disabled then label = "[" .. label:sub(2, -2) .. "]" end
    t.write(label)
end
function Button:width() return self.w or (#tostring(self.text) + 2) end
function Button:onMouse(ev)
    if ev == "mouse_click" and not self.disabled and self.onClick then self.onClick(self) end
end
function Button:onKey(code)
    if (code == keys.enter or code == keys.space) and not self.disabled and self.onClick then self.onClick(self) end
end
function ui.button(o)
    local b = newWidget(Button, o, { h = 1, focusable = true })
    b.w = b.w or (#tostring(b.text) + 2)
    return b
end

-- ---------------------------------------------------------------- Textbox
local Textbox = setmetatable({}, Widget) Textbox.__index = Textbox
function Textbox:draw(t)
    self.text = self.text or ""
    self.cursor = math.max(0, math.min(self.cursor or #self.text, #self.text))
    local inner = self.w
    if self.cursor - (self.scroll or 0) >= inner then self.scroll = self.cursor - inner + 1 end
    if self.cursor < (self.scroll or 0) then self.scroll = self.cursor end
    self.scroll = self.scroll or 0
    t.setCursorPos(self.x, self.y)
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
end
function Textbox:placeCursor(t)
    t.setTextColor(self.fg or theme.inputFg)
    t.setCursorPos(self.x + self.cursor - self.scroll, self.y)
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
        self.cursor = math.min(#(self.text or ""), (self.scroll or 0) + lx - 1)
        self:invalidate()
    end
end
function ui.textbox(o) return newWidget(Textbox, o, { w = 16, h = 1, focusable = true, text = "" }) end

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
            t.setBackgroundColor(self.bg or self.form.bg)
            t.setTextColor(self.fg or self.form.fg)
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
            t.setBackgroundColor(on and theme.accent or theme.mutedFg)
            t.write(" ")
        end
    end
end
function List:select(idx, activate)
    if #self.items == 0 then self.selected = nil return end
    idx = math.max(1, math.min(idx, #self.items))
    local item = self.items[idx]
    if type(item) == "table" and item.separator then return end
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
        if idx > #(self.items or {}) then return end
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
    local l = newWidget(List, o, { w = 20, h = 5, focusable = true, scrollable = true, items = {} })
    if l.selected == nil and #l.items > 0 then l.selected = 1 end
    return l
end

-- ---------------------------------------------------------------- Checkbox
local Checkbox = setmetatable({}, Widget) Checkbox.__index = Checkbox
function Checkbox:draw(t)
    t.setCursorPos(self.x, self.y)
    t.setBackgroundColor(self.bg or self.form.bg)
    t.setTextColor(self.fg or self.form.fg)
    local box = self.checked and "[x] " or "[ ] "
    if self.form.focused == self then t.setTextColor(theme.accent) end
    t.write(box .. tostring(self.text or ""))
end
function Checkbox:toggle()
    self.checked = not self.checked
    if self.onChange then self.onChange(self, self.checked) end
    self:invalidate()
end
function Checkbox:onMouse(ev) if ev == "mouse_click" then self:toggle() end end
function Checkbox:onKey(code) if code == keys.space or code == keys.enter then self:toggle() end end
function ui.checkbox(o)
    local c = newWidget(Checkbox, o, { h = 1, focusable = true })
    c.w = c.w or (#tostring(c.text or "") + 4)
    return c
end

-- ---------------------------------------------------------------- Progress
local Progress = setmetatable({}, Widget) Progress.__index = Progress
function Progress:draw(t)
    local max = self.max or 1
    local frac = max > 0 and math.max(0, math.min(1, (self.value or 0) / max)) or 0
    local filled = math.floor(frac * self.w + 0.5)
    t.setCursorPos(self.x, self.y)
    t.setBackgroundColor(self.fg or theme.accent)
    t.write(string.rep(" ", filled))
    t.setBackgroundColor(self.bg or theme.mutedFg)
    t.write(string.rep(" ", self.w - filled))
    if self.label then
        local s = pad(self.label, self.w, "center")
        t.setCursorPos(self.x, self.y)
        for i = 1, #s do
            t.setBackgroundColor(i <= filled and (self.fg or theme.accent) or (self.bg or theme.mutedFg))
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
    t.setCursorPos(self.x, self.y)
    t.setBackgroundColor(self.bg or theme.inputBg)
    t.setTextColor(self.fg or theme.inputFg)
    t.write(pad(self:current(), self.w - 1) .. "v")
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
function Dropdown:onKey(code) if code == keys.enter or code == keys.space then self:open() end end
function ui.dropdown(o) return newWidget(Dropdown, o, { w = 12, h = 1, focusable = true, items = {}, selected = 1 }) end

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

function Form:contentHeight()
    local bottom = 0
    for _, w in ipairs(self.widgets) do
        if w.visible ~= false then
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
    if not w then return end
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
        t.setBackgroundColor((i >= barY and i < barY + barH) and theme.accent or theme.mutedFg)
        t.write(" ")
    end
end

function Form:draw()
    local t = self.term or term.current()
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
            w.y = y0 - off
            if w.y + (w.h or 1) - 1 >= 1 and w.y <= H then w:draw(t) end
            w.y = y0
        end
    end
    self:drawScrollbar(t, W, H, off)
    if self.focused and self.focused.placeCursor and self.focused.visible ~= false then
        local y0 = self.focused.y
        self.focused.y = y0 - off
        if self.focused.y >= 1 and self.focused.y <= H then self.focused:placeCursor(t) end
        self.focused.y = y0
    end
    self.dirty = false
end

function Form:widgetAt(x, y)
    for i = #self.widgets, 1, -1 do
        local w = self.widgets[i]
        if w.visible ~= false and w:contains(x, y) then return w end
    end
    return nil
end

function Form:handle(ev, a, b, c)
    -- Coordenada do mouse chega na tela; os widgets vivem no espaco do conteudo.
    if ev == "mouse_click" or ev == "mouse_drag" or ev == "mouse_up" or ev == "mouse_scroll" then
        c = (c or 0) + (self.scroll or 0)
    end
    if ev == "mouse_click" then
        local w = self:widgetAt(b, c)
        self.mouseTarget = w
        if w then
            if w.focusable and not w.disabled then self:setFocus(w) end
            w:onMouse(ev, a, b - w.x + 1, c - w.y + 1)
        elseif self.onClickEmpty then
            self.onClickEmpty(self, a, b, c)
        end
        return true
    elseif ev == "mouse_drag" or ev == "mouse_up" then
        local w = self.mouseTarget
        if w then w:onMouse(ev, a, b - w.x + 1, c - w.y + 1) end
        if ev == "mouse_up" then self.mouseTarget = nil end
        return true
    elseif ev == "mouse_scroll" then
        -- So' widget que rola de verdade consome; senao o form inteiro rola (um label
        -- embaixo do cursor nao pode engolir a roda do mouse).
        local w = self:widgetAt(b, c)
        if w and w.scrollable then w:onMouse(ev, nil, b - w.x + 1, c - w.y + 1, a) return true end
        if self:maxScroll() > 0 then self:scrollTo((self.scroll or 0) + a) return true end
    elseif ev == "key" then
        if a == keys.tab then
            self:focusNext(self.shiftHeld and -1 or 1)
            return true
        elseif a == keys.leftShift or a == keys.rightShift then
            self.shiftHeld = true
        end
        if self.focused and not self.focused.disabled then self.focused:onKey(a, b) return true end
    elseif ev == "key_up" then
        if a == keys.leftShift or a == keys.rightShift then self.shiftHeld = false end
    elseif ev == "char" then
        if self.focused and not self.focused.disabled then self.focused:onChar(a) return true end
    elseif ev == "paste" then
        if self.focused and not self.focused.disabled then self.focused:onPaste(a) return true end
    elseif ev == "term_resize" then
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

local function buttonsRow(f, dlg, buttons)
    -- buttons: { {text=, value=, alt=} ... } alinhados a direita na ultima linha; o ultimo e o padrao (focado)
    local total = 0
    for _, b in ipairs(buttons) do total = total + #b.text + 3 end
    local x = dlg.w - total
    local made = {}
    for _, b in ipairs(buttons) do
        made[#made + 1] = f:add(ui.button {
            x = x, y = dlg.h - 1, text = b.text, alt = b.alt,
            onClick = function() dlg.close(b.value) end,
        })
        x = x + #b.text + 3
    end
    f:setFocus(made[#made])
    return made
end

function ui.msgbox(text, title, opts)
    opts = opts or {}
    local pw, ph = term.current().getSize()
    local w = math.min(opts.w or math.max(24, math.min(pw - 2, #tostring(text) + 4)), pw)
    local lines = ui.wrap(text, w - 4)
    local h = math.min(ph, #lines + 5)
    return ui.dialog {
        title = title or "Aviso", w = w, h = h,
        build = function(f, dlg)
            f:add(ui.text { x = 3, y = dlg.contentY + 1, w = w - 4, h = h - 5 + (title and 0 or 1), text = text })
            buttonsRow(f, dlg, { { text = opts.ok or "OK", value = true } })
        end,
    }
end

function ui.confirm(text, title, opts)
    opts = opts or {}
    local pw, ph = term.current().getSize()
    local w = math.min(opts.w or math.max(28, math.min(pw - 2, #tostring(text) + 4)), pw)
    local lines = ui.wrap(text, w - 4)
    local h = math.min(ph, #lines + 5)
    local r = ui.dialog {
        title = title or "Confirmar", w = w, h = h,
        build = function(f, dlg)
            f:add(ui.text { x = 3, y = dlg.contentY + 1, w = w - 4, h = h - 5, text = text })
            buttonsRow(f, dlg, {
                { text = opts.no or "Nao", value = false, alt = true },
                { text = opts.yes or "Sim", value = true },
            })
        end,
    }
    return r == true
end

function ui.prompt(text, default, title, opts)
    opts = opts or {}
    local pw = term.current().getSize()
    local w = math.min(opts.w or 34, pw)
    return ui.dialog {
        title = title or "Digite", w = w, h = 7,
        build = function(f, dlg)
            f:add(ui.label { x = 3, y = dlg.contentY + 1, text = tostring(text):sub(1, w - 4) })
            local tb = f:add(ui.textbox {
                x = 3, y = dlg.contentY + 2, w = w - 4, text = default or "", mask = opts.mask,
                onEnter = function(self) dlg.close(self.text) end,
            })
            buttonsRow(f, dlg, {
                { text = "Cancelar", value = nil, alt = true },
                { text = "OK", value = "__ok" },
            })
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
