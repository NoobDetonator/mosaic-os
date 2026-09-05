-- Ajuda: le os documentos em /os/docs (markdown simples).
local ui = mosaic.ui
local theme = mosaic.theme
local fsx = mosaic.lib("fsx")
local strutil = mosaic.lib("strutil")

local DIR = "/os/docs"
local w, h = term.getSize()
local f = ui.form()
local doc, scroll = nil, 0
local lines = {}
local list

local function titleOf(name)
    local first = (fsx.lines(fs.combine(DIR, name)) or {})[1] or name
    return (first:gsub("^#+%s*", ""))
end

local function loadDoc(name)
    doc = name
    list.visible = false
    scroll = 0
    lines = {}
    for _, raw in ipairs(fsx.lines(fs.combine(DIR, name)) or {}) do
        local level = #(raw:match("^(#+)%s") or "")
        local text = raw:gsub("^#+%s*", ""):gsub("`", ""):gsub("%*%*", "")
        if text == "" then
            lines[#lines + 1] = { text = "" }
        else
            local color = level == 1 and theme.accent or (level == 2 and theme.accent or nil)
            local indent = raw:match("^%s*[-*]%s") and "  " or ""
            for _, wrapped in ipairs(strutil.wrap(indent .. text, w - 1)) do
                lines[#lines + 1] = { text = wrapped, color = color, heading = level > 0 }
            end
        end
    end
    f.dirty = true
end

local function listDocs()
    local items = {}
    if fs.isDir(DIR) then
        for _, name in ipairs(fs.list(DIR)) do
            if name:match("%.md$") then items[#items + 1] = { file = name, text = " " .. titleOf(name) } end
        end
    end
    return items
end

local docs = listDocs()
list = f:add(ui.list { x = 1, y = 2, w = w, h = h - 2, items = docs, activateOnClick = true,
    onActivate = function(_, item) loadDoc(item.file) end })

f.onDraw = function(_, t)
    t.setBackgroundColor(theme.accent)
    t.setTextColor(theme.accentFg)
    t.setCursorPos(1, 1)
    t.write(strutil.pad(doc and (" " .. titleOf(doc)) or " Ajuda do Mosaic OS", w))
    if not doc then return end
    for i = 1, h - 2 do
        local l = lines[i + scroll]
        t.setCursorPos(1, i + 1)
        t.setBackgroundColor(theme.appBg)
        t.setTextColor(l and l.color or theme.appFg)
        t.write(strutil.pad(l and l.text or "", w))
    end
    t.setCursorPos(1, h)
    t.setBackgroundColor(theme.taskbarBg)
    t.setTextColor(theme.taskbarFg)
    local pos = #lines > 0 and math.floor(scroll / math.max(1, #lines - (h - 2)) * 100) or 0
    t.write(strutil.pad(" setas rolam | Backspace volta ao indice | " .. math.min(100, pos) .. "%", w))
end

local function setMode()
    list.visible = doc == nil
    f.dirty = true
end

f.onEvent = function(_, ev, a, b, c)
    if ev == "term_resize" then
        w, h = term.getSize()
        list.w, list.h = w, h - 2
        if doc then loadDoc(doc) end
        f.dirty = true
        return true
    end
    if not doc then return false end
    local maxScroll = math.max(0, #lines - (h - 2))
    if ev == "key" then
        if a == keys.down then scroll = math.min(maxScroll, scroll + 1)
        elseif a == keys.up then scroll = math.max(0, scroll - 1)
        elseif a == keys.pageDown then scroll = math.min(maxScroll, scroll + h - 3)
        elseif a == keys.pageUp then scroll = math.max(0, scroll - h + 3)
        elseif a == keys.home then scroll = 0
        elseif a == keys["end"] then scroll = maxScroll
        elseif a == keys.backspace then doc = nil setMode()
        else return true end
        f.dirty = true
        return true
    elseif ev == "mouse_scroll" then
        scroll = math.max(0, math.min(maxScroll, scroll + a))
        f.dirty = true
        return true
    end
    return true
end

if #docs == 0 then
    f:add(ui.text { x = 2, y = 3, w = w - 3, h = h - 4,
        text = "Nenhum documento encontrado em /os/docs.\n\nO Mosaic OS guarda os guias em /os/docs. Se voce instalou pelo GitHub, rode o app 'Atualizar OS' para baixar a documentacao." })
end
setMode()
f:run()
