-- Boot do Mosaic OS. Roda dentro do shell da ROM (via /startup.lua).
package.path = "/os/?.lua;/os/?/init.lua;" .. package.path

local version = require("version")

-- Configuracoes persistentes (settings API da ROM, salvas em /.settings)
settings.define("mosaic.theme", { description = "Tema visual: win95, classic ou dark", type = "string", default = "win95" })
settings.define("mosaic.palette", { description = "Remapear as cores do CC para os tons do Win95 (volta ao normal ao sair)", type = "boolean", default = true })
settings.define("mosaic.clock", { description = "Relogio da taskbar: real ou game", type = "string", default = "real" })
settings.define("mosaic.relay.url", { description = "URL websocket do relay (ws://host:porta/ws/computer)", type = "string" })
settings.define("mosaic.relay.token", { description = "Token de acesso do relay", type = "string" })
settings.define("mosaic.relay.events", { description = "Eventos do jogo encaminhados ao relay", type = "table",
    default = { "redstone", "peripheral", "peripheral_detach", "chat", "playerJoin", "playerLeave", "playerClick", "disk", "disk_eject" } })
settings.define("mosaic.net.enabled", { description = "Ativar rede rednet entre computadores Mosaic", type = "boolean", default = true })
settings.define("mosaic.net.password", { description = "Senha para comandos remotos via rednet", type = "string" })
settings.define("mosaic.net.name", { description = "Nome deste computador na rede", type = "string" })
settings.define("mosaic.som.enabled", { description = "Sons do sistema (precisa de um alto-falante ao lado)", type = "boolean", default = true })
settings.define("mosaic.som.volume", { description = "Volume geral, de 0 a 3", type = "number", default = 1 })
settings.define("mosaic.autostart", { description = "Programas abertos ao ligar", type = "table", default = {} })
settings.define("mosaic.wallpaper", { description = "Imagem .nfp de fundo", type = "string" })
settings.load()

local theme = require("kernel.theme")
theme.load(settings.get("mosaic.theme"))

local root = term.current()
-- A paleta tem que vir ANTES do wm.init: o canvas fotografa a paleta do pai ao ser criado
-- e a reempurra a cada quadro, desfazendo qualquer mudanca feita depois.
local palette = require("kernel.palette")
if palette.enabled() then palette.apply(root) end

local wm = require("kernel.wm")
wm.init(root)

-- Splash rapido
root.setBackgroundColor(theme.desktopBg)
root.setTextColor(theme.desktopFg)
root.clear()
local W, H = root.getSize()
local banner = version.name .. " " .. version.version
root.setCursorPos(math.floor((W - #banner) / 2) + 1, math.floor(H / 2))
root.write(banner)
root.setCursorBlink(false)

local proc = require("kernel.proc")
proc.api.ui = require("kernel.ui")
proc.parentShell = shell
proc.init()

-- Sem acento em nome de pasta: a fonte do CC mapeia byte a byte e UTF-8 vira lixo na tela.
for _, d in ipairs({ "/os/var", "/os/var/log", "/apps", "/home",
                     "/home/desktop", "/home/programas", "/home/downloads",
                     "/home/imagens", "/home/documentos" }) do
    if not fs.exists(d) then fs.makeDir(d) end
end

-- Semeia os atalhos das pastas recem-criadas. E' idempotente e tem memoria: atalho que
-- voce apagou nao volta no proximo update (registry.SEED_FILE guarda o que ja foi semeado).
require("apps.registry").seed()

-- Area de trabalho: janela sem titulo, sempre ao fundo, nao fecha.
proc.launch("/os/apps/desktop.lua", {}, {
    title = "Area de trabalho", chrome = false, bottom = true, noclose = true,
    x = 1, y = 1, w = wm.W, h = wm.H - 1, holdOnError = true, bg = theme.desktopBg, fg = theme.desktopFg,
})

-- Servicos
if settings.get("mosaic.relay.url") then
    proc.daemon("relay", "/os/net/relay.lua")
end
if settings.get("mosaic.net.enabled") then
    proc.daemon("netd", "/os/net/netd.lua")
end

-- Autostart do usuario
for _, path in ipairs(settings.get("mosaic.autostart") or {}) do
    if fs.exists(path) then proc.launch(path) end
end

-- Ligou. Sem alto-falante ao lado isso e' silencio, nao erro.
pcall(function() require("lib.audio").sfx("boot") end)

proc.run()

-- Saiu do kernel (mosaic.exitToShell): devolve as cores de fabrica e volta ao shell da ROM.
palette.restore(root)
root.setBackgroundColor(colors.black)
root.setTextColor(colors.white)
root.clear()
root.setCursorPos(1, 1)
print(version.name .. ": voltando ao shell da ROM. Digite 'reboot' para reiniciar o OS.")
