-- Casos reais encontrados na auditoria. Nao depende de rede nem de periferico real.
package.path="/os/?.lua;"..package.path
local results={}
local function check(value,msg) assert(value,msg);results[#results+1]=msg end
local function put(p,s) fs.makeDir(fs.getDir(p));local h=assert(fs.open(p,"w"));h.write(s);h.close() end
local function read(p) local h=fs.open(p,"r");if not h then return nil end;local s=h.readAll();h.close();return s end
local update=require("lib.update")
check(update.sha1("")=="da39a3ee5e6b4b0d3255bfef95601890afd80709","sha1 vazio")
check(update.sha1("abc")=="a9993e364706816aba3e25717850c26c9cd0d89d","sha1 abc")
check(update.sha1(string.rep("a",1000))=="291e9a6c66994949b57ba5e650361e98fc36b1ba","sha1 multibloco")
local oldFetch=update.fetch
local manifest={version="test",files={{path="os/regression.txt",size=3,sha1=update.sha1("new")},
    {path="os/extra-regression.txt",optional=true,sha1=update.sha1("new")}}}
update.fetch=function(_,p) return p=="manifest.json" and textutils.serialiseJSON(manifest) or "new" end
put("/os/regression.txt","old")
local plan=update.prepare("https://example.invalid",false)
check(#plan.files==1,"extras ausentes nao sao instalados")
manifest.files[1].sha1=string.rep("0",40)
check(not pcall(update.prepare,"https://example.invalid",false),"hash errado aborta verificacao")
manifest.files[1].path="os/../home/wrong"
check(not pcall(update.prepare,"https://example.invalid",false),"path traversal recusado")
update.fetch=oldFetch
local oldFree=fs.getFreeSpace
fs.getFreeSpace=function() return 0 end
check(not update.apply(plan),"falta de espaco recusa antes de gravar")
check(read("/os/regression.txt")=="old","recusa preserva arquivo")
fs.getFreeSpace=oldFree
local oldMove=fs.move
local failed=false
fs.move=function(a,b)
    if a=="/.mosaic-update/new/1" and not failed then failed=true;error("falha injetada") end
    return oldMove(a,b)
end
local applied=update.apply(plan)
fs.move=oldMove
check(not applied and read("/os/regression.txt")=="old","falha no commit restaura original")
check(not fs.exists("/.mosaic-update"),"rollback limpa journal")
check(update.apply(plan),"commit valido conclui")
check(read("/os/regression.txt")=="new","commit grava conteudo verificado")
check(textutils.unserialiseJSON(read("/os/var/installed.json")).version=="test","versao gravada apos commit")
-- Simula queda apos mover original mas antes de mover arquivo novo.
put("/.mosaic-update/plan.json",textutils.serialiseJSON({files={{target="/os/regression.txt",existed=true}}}))
fs.makeDir("/.mosaic-update/old")
fs.move("/os/regression.txt","/.mosaic-update/old/1")
update.recover()
check(read("/os/regression.txt")=="new","recuperacao de queda restaura backup")
fs.delete("/os/regression.txt")

local root=term.current()
local wm=require("kernel.wm")
local proc=require("kernel.proc")
local ui=require("kernel.ui")
proc.api.ui=ui;proc.parentShell=shell;wm.init(root);proc.init()
local p=proc.spawn{title="ghost",x=3,y=3,w=20,h=5,fn=function() while true do os.pullEvent() end end}
p.monitor={name="fake",p=window.create(root,1,1,20,5,false)}
check(wm.hitTest(proc.list(),4,4).p~=p,"monitor nao captura clique do desktop")
check(wm.topAt(proc.list(),4,4)~=p,"monitor nao oculta cursor do desktop")
proc.kill(p)
check(p.monitor==nil,"fechar limpa monitor")
local mini=window.create(root,1,1,51,19,false)
wm.init(mini);mini.reposition(1,1,26,10);wm.resize()
check(wm.tiny,"resize recalcula modo compacto")
wm.init(root)
local failing=proc.spawn{title="error",hidden=true,fn=function() os.pullEvent();error("app failure") end}
local oldOpen=fs.open
fs.open=function(path,mode) if path:find("/log/",1,true) then error("disco cheio") end;return oldOpen(path,mode) end
local safe=pcall(proc.resume,failing,"test")
fs.open=oldOpen
check(safe and failing.dead,"falha de log nao escapa do scheduler")

local realForm,realMenu,realPrompt=ui.form,ui.menu,ui.prompt
local form,prompt
ui.form=function(opts) local f=realForm(opts);f.run=function() end;form=f;return f end
settings.define("mosaic.theme",{type="string",default="win95"})
ui.menu=function() return 1 end
ui.prompt=function(label) prompt=label;return nil end
os.run(setmetatable({},{__index=_G}),"/os/apps/settings.lua")
local expected
for _,name in ipairs(settings.getNames()) do if name:match("^mosaic%.") then expected=name;break end end
for _,w in ipairs(form.widgets) do if w.text=="Ver &todas as opcoes" then w.onClick();break end end
check(prompt==expected..":","configuracao filtrada edita chave certa")
form:layout(51,17)
for _,w in ipairs(form.widgets) do if w.x==17 and w.onChange then check(w.x+w.w-1<=51,"campo de rede cabe na janela") end end
ui.menu,ui.prompt=realMenu,realPrompt
os.run(setmetatable({},{__index=_G}),"/os/apps/help.lua")
for _,w in ipairs(form.widgets) do
    if w.items and #w.items>0 and w.onActivate then w.onActivate(w,w.items[1]);check(w.visible==false,"guia esconde indice da Ajuda");break end
end
ui.form=realForm
term.redirect(root);root.clear();root.setCursorPos(1,1)
print("Regression self-check: "..#results.." ok, 0 falhas")
put("/regression-result.txt","Regression self-check: "..#results.." ok, 0 falhas")
os.shutdown()
