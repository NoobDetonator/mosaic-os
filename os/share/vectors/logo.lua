-- logo: desenho vetorial, convertido de SVG por tools/svg.js.
-- As coordenadas vivem na caixa vb; o os/lib/vector escala para o tamanho pedido.
return {
    vb = { 0, 0, 32, 32 },
    { rect = { 2, 2, 28, 28 }, fill = colors.blue },
    { fill = colors.lightGray, d = { "M", 4, 4, "L", 14, 4, "L", 14, 14, "L", 4, 14, "Z" } },
    { fill = colors.cyan, d = { "M", 18, 4, "L", 28, 4, "L", 28, 14, "L", 18, 14, "Z" } },
    { fill = colors.yellow, d = { "M", 4, 18, "L", 14, 18, "L", 14, 28, "L", 4, 28, "Z" } },
    { fill = colors.white, d = { "M", 18, 18, "L", 28, 18, "L", 28, 28, "L", 18, 28, "Z" } },
    { circle = { 16, 16, 4 }, fill = colors.red },
}
