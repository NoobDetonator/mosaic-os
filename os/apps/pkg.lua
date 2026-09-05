local ui,theme=mosaic.ui,mosaic.theme
local fsx,update=mosaic.lib("fsx"),mosaic.lib("update")
local f=ui.form()
local installed=fsx.readJSON("/os/var/installed.json",{})
local plan,list,status
f:add(ui.label{x=2,y=1,w=-2,text="Instalado: "..mosaic.version.version})
f:add(ui.label{x=2,y=2,text="Repositorio (raw do GitHub):"})
local url=f:add(ui.textbox{x=2,y=3,w=-3,text=installed.base or mosaic.version.repo})
local bar=ui.row(f,{bottom=0,items={
    {text="&Verificar",onClick=function()
        plan=nil
        list:setItems({})
        local ok,result=pcall(update.prepare,url.text,false,function(i,n,path)
            status.text=string.format(" Verificando %d/%d: %s",i,n,path)
            f:draw()
        end)
        if ok then
            plan=result
            list:setItems(plan.files)
            status.text=" "..#plan.files.." arquivos; hashes conferidos."
        else status.text=" Falhou: "..tostring(result) end
        f.dirty=true
    end},
    {text="&Atualizar",onClick=function()
        if not plan then ui.msgbox("Verifique os arquivos primeiro.","Atualizador") return end
        if url.text~=plan.base then plan=nil;ui.msgbox("Repositorio mudou. Verifique novamente.","Atualizador") return end
        if not ui.confirm("Aplicar "..#plan.files.." arquivos com backup?","Atualizador") then return end
        local busy=ui.busy("Atualizando","")
        local called,ok,err=pcall(update.apply,plan,function(i,n,path) busy.set(i/n,path) end)
        busy.close()
        plan=nil
        if not called or not ok then
            ui.msgbox(tostring(called and err or ok),"Atualizacao nao concluida")
            status.text=" Falhou. Verifique novamente antes de tentar."
        else
            status.text=" Atualizacao concluida. Reinicie para aplicar."
            if ui.confirm("Reiniciar agora?","Atualizado") then mosaic.reboot() end
        end
        f.dirty=true
    end},
}})
status=f:add(ui.label{x=1,above=bar,w="fill",text=" Clique em Verificar para comecar.",bg=theme.taskbarBg,fg=theme.taskbarFg})
list=f:add(ui.list{x=1,y=5,w="fill",fillTo=status,render=function(it) return it.target end})
f:run()
