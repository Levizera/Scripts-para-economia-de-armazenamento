#!/bin/bash

# --- FUNÇÕES AUXILIARES ---

format_time() {
    local T=$1
    local H=$((T / 3600))
    local M=$(( (T % 3600) / 60 ))
    local S=$((T % 60))
    if [ "$H" -gt 0 ]; then printf "%02d:%02d:%02d" $H $M $S; else printf "%02d:%02d" $M $S; fi
}

format_size() {
    local B=${1:-0}
    if [ "$B" -ge 1073741824 ]; then awk "BEGIN {printf \"%.2f GB\", $B/1073741824}";
    elif [ "$B" -ge 1048576 ]; then awk "BEGIN {printf \"%.2f MB\", $B/1048576}";
    elif [ "$B" -ge 1024 ]; then awk "BEGIN {printf \"%.2f KB\", $B/1024}";
    else echo "${B} B"; fi
}

# --- CONFIGURAÇÕES ---
PDF_SETTINGS="/ebook" # /ebook (150dpi) ou /screen (72dpi)
ARQUIVO_LOG_TEMP="log_pdfs_temp.tmp"
LISTA_PARA_PROCESSAR="lista_arquivos.tmp"

# --- MENU DE ESCOLHA ---
clear
echo "=== Otimizador de PDFs v8.0 (Correção de Acentos e Erros) ==="
echo "Escolha o modo de operação:"
echo "  [1] Pasta Inteira (Processa tudo recursivamente)"
echo "  [2] Selecionar Arquivo Único em uma Pasta"
echo -n "Opção: "
read -r OPCAO_MODO

INPUT_PATH=""
PASTA_RAIZ_REF="" 

if [ "$OPCAO_MODO" == "1" ]; then
    # --- MODO 1: PASTA INTEIRA ---
    echo -e "\nCole o caminho completo da PASTA com os PDFs:"
    read -r INPUT_RAW
    INPUT_PATH=$(echo "$INPUT_RAW" | tr -d "'\"")
    INPUT_PATH="${INPUT_PATH%/}" 

    if [ ! -d "$INPUT_PATH" ]; then
        echo "ERRO: A pasta '$INPUT_PATH' não foi encontrada."
        exit 1
    fi
    
    PASTA_RAIZ_REF="$INPUT_PATH"
    PASTA_DESTINO="${INPUT_PATH}_otimizados"
    
    echo "Buscando arquivos na pasta..."
    find "$INPUT_PATH" -type f | grep -E -i '\.pdf$' > "$LISTA_PARA_PROCESSAR"

elif [ "$OPCAO_MODO" == "2" ]; then
    # --- MODO 2: SELEÇÃO DE ARQUIVO ---
    echo -e "\nCole o caminho da PASTA onde está o arquivo:"
    read -r INPUT_RAW
    PASTA_ALVO=$(echo "$INPUT_RAW" | tr -d "'\"")
    PASTA_ALVO="${PASTA_ALVO%/}"

    if [ ! -d "$PASTA_ALVO" ]; then
        echo "ERRO: A pasta '$PASTA_ALVO' não foi encontrada."
        exit 1
    fi

    mapfile -t ARQUIVOS_ENCONTRADOS < <(find "$PASTA_ALVO" -maxdepth 1 -type f -iname "*.pdf" | sort)
    QTD_ENCONTRADA=${#ARQUIVOS_ENCONTRADOS[@]}

    if [ "$QTD_ENCONTRADA" -eq 0 ]; then
        echo "Nenhum arquivo PDF encontrado nesta pasta."
        exit 1
    fi

    echo -e "\n--- Arquivos encontrados em: $(basename "$PASTA_ALVO") ---"
    i=1
    for arquivo in "${ARQUIVOS_ENCONTRADOS[@]}"; do
        echo "  [$i] $(basename "$arquivo")"
        ((i++))
    done
    echo "------------------------------------------------"
    echo -n "Digite o NÚMERO do arquivo que deseja processar: "
    read -r NUMERO_ESCOLHIDO

    if ! [[ "$NUMERO_ESCOLHIDO" =~ ^[0-9]+$ ]] || [ "$NUMERO_ESCOLHIDO" -lt 1 ] || [ "$NUMERO_ESCOLHIDO" -gt "$QTD_ENCONTRADA" ]; then
        echo "Opção inválida."
        exit 1
    fi

    ARQUIVO_SELECIONADO="${ARQUIVOS_ENCONTRADOS[$((NUMERO_ESCOLHIDO-1))]}"
    
    INPUT_PATH="$ARQUIVO_SELECIONADO"
    PASTA_RAIZ_REF=$(dirname "$ARQUIVO_SELECIONADO")
    PASTA_DESTINO="${PASTA_RAIZ_REF}_otimizados"
    
    echo "$ARQUIVO_SELECIONADO" > "$LISTA_PARA_PROCESSAR"

else
    echo "Opção inválida."
    exit 1
fi

# --- PREPARAÇÃO DO AMBIENTE ---
mkdir -p "$PASTA_DESTINO"
ARQUIVO_LOG="$PASTA_DESTINO/relatorio_pdfs.txt"

START_GLOBAL=$(date +%s)
TOTAL_BYTES_ORIGINAL=0
TOTAL_BYTES_NOVO=0
BYTES_ECONOMIZADOS=0
FILES_PROCESSED_COUNT=0
TOTAL_ARQUIVOS=$(wc -l < "$LISTA_PARA_PROCESSAR")

echo "========================================================" > "$ARQUIVO_LOG_TEMP"
echo "RELATÓRIO DE OTIMIZAÇÃO DE PDF" >> "$ARQUIVO_LOG_TEMP"
echo "Data: $(date)" >> "$ARQUIVO_LOG_TEMP"
echo "Origem: $INPUT_PATH" >> "$ARQUIVO_LOG_TEMP"
echo "========================================================" >> "$ARQUIVO_LOG_TEMP"
echo "DETALHES:" >> "$ARQUIVO_LOG_TEMP"

if [ "$TOTAL_ARQUIVOS" -eq 0 ]; then
    echo "Nenhum PDF encontrado."
    rm "$LISTA_PARA_PROCESSAR" "$ARQUIVO_LOG_TEMP"
    exit 0
fi

# --- LOOP PRINCIPAL ---
while read -r ARQUIVO; do
    
    FILES_PROCESSED_COUNT=$((FILES_PROCESSED_COUNT+1))
    
    # Define caminhos
    CAMINHO_RELATIVO="${ARQUIVO#$PASTA_RAIZ_REF/}"
    DIRETORIO_RELATIVO=$(dirname "$CAMINHO_RELATIVO")
    
    if [ "$DIRETORIO_RELATIVO" == "." ]; then
        PASTA_FINAL="$PASTA_DESTINO"
    else
        PASTA_FINAL="$PASTA_DESTINO/$DIRETORIO_RELATIVO"
    fi
    mkdir -p "$PASTA_FINAL"
    
    NOME_ARQUIVO=$(basename "$ARQUIVO")
    CAMINHO_SAIDA_OTIMIZADO="$PASTA_FINAL/$NOME_ARQUIVO"
    
    TAMANHO_ATUAL_ARQ=$(wc -c < "$ARQUIVO")
    TOTAL_BYTES_ORIGINAL=$(echo "$TOTAL_BYTES_ORIGINAL + $TAMANHO_ATUAL_ARQ" | bc)
    
    # ETA
    NOW=$(date +%s)
    ELAPSED=$((NOW - START_GLOBAL))
    if [ "$FILES_PROCESSED_COUNT" -gt 1 ]; then
        AVG_TIME_PER_FILE=$(echo "$ELAPSED / ($FILES_PROCESSED_COUNT - 1)" | bc)
        if [ "$AVG_TIME_PER_FILE" -eq 0 ]; then AVG_TIME_PER_FILE=1; fi
        FILES_REMAINING=$((TOTAL_ARQUIVOS - FILES_PROCESSED_COUNT + 1))
        ETA_SEC=$((FILES_REMAINING * AVG_TIME_PER_FILE))
        ETA_STR=$(format_time $ETA_SEC)
    else
        ETA_STR="Calculando..."
    fi
    if [ "$TOTAL_ARQUIVOS" -eq 1 ]; then ETA_STR="< 1 min"; fi

    SAVED_STR=$(format_size $BYTES_ECONOMIZADOS)

    echo -e "\n---------------------------------------------------"
    echo -e "Arq: [$FILES_PROCESSED_COUNT/$TOTAL_ARQUIVOS] $NOME_ARQUIVO"
    echo -e "Status: Econ. Acumulada: \033[1;32m$SAVED_STR\033[0m | ETA: \033[1;33m$ETA_STR\033[0m"
    echo -e "Otimizando..." 

    # --- ESTRATÉGIA BLINDADA (SAFE FILENAMES) ---
    # 1. Cria nomes temporários seguros (sem espaços/acentos) no /tmp
    SAFE_INPUT="/tmp/safe_input_$$.pdf"
    SAFE_OUTPUT="/tmp/safe_output_$$.pdf"

    # Copia o original para o temp seguro
    cp "$ARQUIVO" "$SAFE_INPUT"

    # 2. Executa Ghostscript no arquivo seguro
    gs -sDEVICE=pdfwrite -dCompatibilityLevel=1.4 -dPDFSETTINGS=$PDF_SETTINGS \
       -dNOPAUSE -dQUIET -dBATCH \
       -sOutputFile="$SAFE_OUTPUT" "$SAFE_INPUT"

    GS_EXIT_CODE=$?

    # 3. Verifica Resultado e Move
    RESULTADO_TIPO=""
    TAMANHO_FINAL_ARQ=0

    # Se GS falhou ou arquivo de saída não existe ou é vazio
    if [ $GS_EXIT_CODE -ne 0 ] || [ ! -s "$SAFE_OUTPUT" ]; then
        echo " -> Aviso: Método padrão falhou. Tentando reparo de estrutura..."
        
        # Tenta método alternativo (Reparo)
        gs -o "$SAFE_OUTPUT" -sDEVICE=pdfwrite -dPDFSETTINGS=/screen "$SAFE_INPUT" > /dev/null 2>&1
        
        if [ ! -s "$SAFE_OUTPUT" ]; then
            # Se falhar de novo, desiste e copia original
            cp -p "$ARQUIVO" "$CAMINHO_SAIDA_OTIMIZADO"
            TAMANHO_FINAL_ARQ=$TAMANHO_ATUAL_ARQ
            RESULTADO_TIPO="ERRO (Copiado Original)"
        fi
    fi

    # Se ainda não definimos o resultado (ou seja, se o processo acima gerou algo)
    if [ -z "$RESULTADO_TIPO" ]; then
        TAMANHO_NOVO=$(wc -c < "$SAFE_OUTPUT")
        
        if [ "$TAMANHO_NOVO" -ge "$TAMANHO_ATUAL_ARQ" ]; then
            cp -p "$ARQUIVO" "$CAMINHO_SAIDA_OTIMIZADO"
            TAMANHO_FINAL_ARQ=$TAMANHO_ATUAL_ARQ
            RESULTADO_TIPO="DESCARTADO (Não reduziu)"
        else
            # SUCESSO! Move do temp para o destino final
            mv "$SAFE_OUTPUT" "$CAMINHO_SAIDA_OTIMIZADO"
            TAMANHO_FINAL_ARQ=$TAMANHO_NOVO
            RESULTADO_TIPO="OTIMIZADO"
        fi
    fi

    # Limpeza dos temps
    rm -f "$SAFE_INPUT" "$SAFE_OUTPUT"

    # Stats
    TOTAL_BYTES_NOVO=$(echo "$TOTAL_BYTES_NOVO + $TAMANHO_FINAL_ARQ" | bc)
    DIFERENCA=$(echo "$TAMANHO_ATUAL_ARQ - $TAMANHO_FINAL_ARQ" | bc)
    if [ "$DIFERENCA" -gt 0 ]; then
        BYTES_ECONOMIZADOS=$(echo "$BYTES_ECONOMIZADOS + $DIFERENCA" | bc)
    fi

    REDUCAO_PC=$(awk "BEGIN {printf \"%.1f\", 100 - ($TAMANHO_FINAL_ARQ * 100 / $TAMANHO_ATUAL_ARQ)}")
    echo "[$FILES_PROCESSED_COUNT/$TOTAL_ARQUIVOS] $NOME_ARQUIVO | $RESULTADO_TIPO | Redução: $REDUCAO_PC%" >> "$ARQUIVO_LOG_TEMP"

done < "$LISTA_PARA_PROCESSAR"

rm "$LISTA_PARA_PROCESSAR"

# --- RELATÓRIO FINAL ---
END_GLOBAL=$(date +%s)
TEMPO_TOTAL_SEC=$((END_GLOBAL - START_GLOBAL))
TEMPO_TOTAL_FMT=$(format_time $TEMPO_TOTAL_SEC)
STR_ORIGINAL=$(format_size $TOTAL_BYTES_ORIGINAL)
STR_NOVO=$(format_size $TOTAL_BYTES_NOVO)
STR_ECONOMIA=$(format_size $BYTES_ECONOMIZADOS)

if [ "$TOTAL_BYTES_ORIGINAL" -gt 0 ]; then
    PC_GLOBAL=$(awk "BEGIN {printf \"%.2f\", 100 - ($TOTAL_BYTES_NOVO * 100 / $TOTAL_BYTES_ORIGINAL)}")
else
    PC_GLOBAL="0.00"
fi

echo "" >> "$ARQUIVO_LOG_TEMP"
echo "========================================================" >> "$ARQUIVO_LOG_TEMP"
echo "RESUMO FINAL" >> "$ARQUIVO_LOG_TEMP"
echo "========================================================" >> "$ARQUIVO_LOG_TEMP"
echo "Tempo Total:                  $TEMPO_TOTAL_FMT" >> "$ARQUIVO_LOG_TEMP"
echo "Arquivos Processados:         $TOTAL_ARQUIVOS" >> "$ARQUIVO_LOG_TEMP"
echo "--------------------------------------------------------" >> "$ARQUIVO_LOG_TEMP"
echo "Tamanho Original Total:       $STR_ORIGINAL" >> "$ARQUIVO_LOG_TEMP"
echo "Tamanho Final Total:          $STR_NOVO" >> "$ARQUIVO_LOG_TEMP"
echo "--------------------------------------------------------" >> "$ARQUIVO_LOG_TEMP"
echo "ESPAÇO ECONOMIZADO:           $STR_ECONOMIA" >> "$ARQUIVO_LOG_TEMP"
echo "REDUÇÃO GERAL:                $PC_GLOBAL%" >> "$ARQUIVO_LOG_TEMP"
echo "========================================================" >> "$ARQUIVO_LOG_TEMP"

mv "$ARQUIVO_LOG_TEMP" "$ARQUIVO_LOG"

echo -e "\n\n========================================================"
echo -e "CONCLUÍDO!"
echo -e "Tempo Total: \033[1;34m$TEMPO_TOTAL_FMT\033[0m"
echo -e "Economia Total: \033[1;32m$STR_ECONOMIA\033[0m ($PC_GLOBAL% reduzido)"
echo -e "Arquivo(s) em: $PASTA_DESTINO"
echo -e "Relatório salvo em: $ARQUIVO_LOG"
echo "========================================================"
