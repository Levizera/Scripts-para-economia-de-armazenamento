#!/bin/bash

# 1. Configuração Inicial
echo "---------------------------------------------------"
echo "   OTIMIZADOR ABSOLUTO (REDUÇÃO FORÇADA)"
echo "---------------------------------------------------"
read -p "Cole o caminho COMPLETO da pasta original: " PASTA_ORIGEM

# Limpeza e verificações
PASTA_ORIGEM=$(echo "$PASTA_ORIGEM" | tr -d '"' | sed 's:/*$::')

if [ ! -d "$PASTA_ORIGEM" ]; then
    echo "Erro: A pasta '$PASTA_ORIGEM' não foi encontrada."
    exit 1
fi

PASTA_DESTINO="${PASTA_ORIGEM}_OTIMIZADA_FINAL"

echo "---------------------------------------------------"
echo "Origem:  $PASTA_ORIGEM"
echo "Destino: $PASTA_DESTINO"
echo "Estratégia: Teto 720p + CRF 30 + Audio 56k Mono"
echo "---------------------------------------------------"
sleep 1

cd "$PASTA_ORIGEM" || exit

# 2. Loop de Processamento
find . -type f -regextype posix-extended -iregex ".*\.(mp4|mkv|mov|avi|flv|webm|m4v|wmv)" | sort | while read -r ARQUIVO; do
    
    CAMINHO_RELATIVO="${ARQUIVO#./}"
    DIRETORIO_BASE=$(dirname "$CAMINHO_RELATIVO")
    NOME_SEM_EXT="${CAMINHO_RELATIVO%.*}"
    
    # Define nomes
    NOVO_ARQUIVO="$PASTA_DESTINO/$NOME_SEM_EXT.mp4"
    ARQUIVO_TEMP="$PASTA_DESTINO/$NOME_SEM_EXT.temp.mp4"

    # Cria pasta
    mkdir -p "$PASTA_DESTINO/$DIRETORIO_BASE"

    if [ -f "$NOVO_ARQUIVO" ]; then
        echo "Pulando (já existe): $CAMINHO_RELATIVO"
        continue
    fi

    echo "Processando: $CAMINHO_RELATIVO"

    # --- O COMANDO FFMPEG ---
    # scale='min(iw,1280):-2' -> A MÁGICA. 
    # Significa: "Se a largura for maior que 1280, diminua para 1280. Se for menor, mantenha a original."
    # O -2 calcula a altura automaticamente para não distorcer a imagem.
    
    ffmpeg -nostdin -v error -stats -i "$ARQUIVO" \
    -vf "scale='min(iw,1280):-2'" \
    -c:v libx264 -crf 30 -preset medium \
    -c:a aac -b:a 56k -ac 1 \
    -movflags +faststart \
    "$ARQUIVO_TEMP"

    # Verificação de Sucesso
    if [ $? -eq 0 ]; then
        mv "$ARQUIVO_TEMP" "$NOVO_ARQUIVO"
        echo ">> Sucesso."
    else
        echo ">> ERRO ou INTERRUPÇÃO em: $CAMINHO_RELATIVO"
        rm -f "$ARQUIVO_TEMP"
    fi

done

echo "---------------------------------------------------"
echo "CONCLUÍDO!"
echo "---------------------------------------------------"
