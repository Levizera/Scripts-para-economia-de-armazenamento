#!/bin/bash

# Garante que o script rode no diretório onde ele está salvo
cd "$(dirname "$0")"

echo "---------------------------------------------------"
echo "   BAIXADOR UNIVERSAL DE TIKTOK (Modo Manual)"
echo "---------------------------------------------------"

# Verifica se o arquivo do cookie existe
if [ ! -f "cookie_raw.txt" ]; then
    echo "ERRO: O arquivo 'cookie_raw.txt' nao foi encontrado!"
    echo "Por favor, crie esse arquivo na mesma pasta colando o valor do cookie."
    echo ""
    read -p "Pressione Enter para sair..."
    exit 1
fi

echo "Arquivo de cookie encontrado!"
echo ""

echo "Cole o link do perfil que voce quer baixar."
echo "Exemplo: https://www.tiktok.com/@olavodecarvalho"
echo ""

read -p "Link do Perfil: " LINK

echo ""
echo "Lendo cookie e iniciando download..."
echo "Os arquivos ficarao na pasta 'Videos_Baixados'."
echo ""

mkdir -p "Videos_Baixados"

# Lê o conteúdo do arquivo de texto para uma variável
COOKIE_VAL=$(cat cookie_raw.txt)

# Usa o parâmetro --add-header para enviar o cookie bruto
yt-dlp -o 'Videos_Baixados/%(uploader)s/%(upload_date)s - %(title)s.%(ext)s' \
--ignore-errors \
--add-header "Cookie: $COOKIE_VAL" \
--user-agent "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" \
"$LINK"

echo ""
echo "---------------------------------------------------"
echo "CONCLUIDO!"
echo "---------------------------------------------------"

read -p "Pressione Enter para sair..."
