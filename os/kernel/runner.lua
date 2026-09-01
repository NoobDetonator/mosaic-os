-- Executado pelo shell da ROM dentro de cada janela: roda o programa com argumentos exatos
-- e, se der erro, segura a janela aberta para o usuario ler a mensagem.
local args = { ... }
local path = table.remove(args, 1)
if not path then return end
local ok = shell.execute(path, table.unpack(args))
if not ok and mosaic and mosaic.holdOnError() then
    print("")
    term.setTextColor(colors.yellow)
    print("Pressione qualquer tecla para fechar.")
    os.pullEvent("key")
end
