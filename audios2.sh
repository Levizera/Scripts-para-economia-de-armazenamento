#!/bin/bash

# --- FUNÇÕES AUXILIARES ---

# Formata segundos para MM:SS
format_time() {
    local T=$1
    local H=$((T / 3600))
    local M=$(( (T % 3600) / 60 ))
    local S=$((T % 60))
    
    if [ "$H" -gt 0 ]; then
        printf "%02d:%02d:%02d" $H $M $S
    else
        printf "%02d:%02d" $M $S
    fi
}

# Formata Bytes para KB, MB, GB
format_size() {
    local B=${1:-0}
    if [ "$B" -ge 1073741824 ]; then
        awk "BEGIN {printf \"%.2f GB\", $B/1073741824}"
    elif [ "$B" -ge 1048576 ]; then
        awk "BEGIN {printf \"%.2f MB\", $B/1048576}"
    elif [ "$B" -ge 1024 ]; then
        awk "BEGIN {printf \"%.2f KB\", $B/1024}"
    else
        echo "${B} B"
    fi
}

# Barra de progresso visual
progress_bar() {
    local ATUAL=$1
    local TOTAL=$2
    local WIDTH=25 

    if [ "$TOTAL" -eq 0 ]; then TOTAL=1; fi
    local PERCENT=$(( (ATUAL * 100) / TOTAL ))
    if [ "$PERCENT" -gt 100 ]; then PERCENT=100; fi

    local FILLED=$(( (PERCENT * WIDTH) / 100 ))
    local EMPTY=$(( WIDTH - FILLED ))

    printf "\r   ["
    printf "%0.s#" $(seq 1 $FILLED)
    if [ $EMPTY -gt 0 ]; then printf "%0.s." $(seq 1 $EMPTY); fi
    
    local T_ATUAL=$(format_time $((ATUAL / 1000000)))
    local T_TOTAL=$(format_time $((TOTAL / 1000000)))
    printf "] %3d%% | %s/%s" "$PERCENT" "$T_ATUAL" "$T_TOTAL"
}

# --- SETUP INICIAL ---
echo "=== Otimizador de Áudios v5.0 (Estatísticas Completas) ==="
echo "Cole o caminho completo da pasta raiz dos áudios:"
read -r INPUT_RAW

PASTA_ORIGEM=$(echo "$INPUT_RAW" | tr -d "'\"")
PASTA_ORIGEM="${PASTA_ORIGEM%/}" 

if [ ! -d "$PASTA_ORIGEM" ]; then
    echo "ERRO: A pasta '$PASTA_ORIGEM' não foi encontrada."
    exit 1
fi

PASTA_DESTINO="${PASTA_ORIGEM}_otimizados"
ARQUIVO_LOG="$PASTA_DESTINO/relatorio_otimizacao.txt"
ARQUIVO_LOG_TEMP="log_temp.tmp"
BITRATE_ALVO=32000 
BITRATE_FFMPEG="32k"

mkdir -p "$PASTA_DESTINO"

# --- VARIÁVEIS DE ESTATÍSTICA ---
START_GLOBAL=$(date +%s)
TOTAL_BYTES_ORIGINAL=0
TOTAL_BYTES_NOVO=0
BYTES_ECONOMIZADOS=0
FILES_PROCESSED_COUNT=0

# Inicializa Log
echo "========================================================" > "$ARQUIVO_LOG_TEMP"
echo "RELATÓRIO DE OTIMIZAÇÃO DE ÁUDIO" >> "$ARQUIVO_LOG_TEMP"
echo "Data: $(date)" >> "$ARQUIVO_LOG_TEMP"
echo "Origem: $PASTA_ORIGEM" >> "$ARQUIVO_LOG_TEMP"
echo "========================================================" >> "$ARQUIVO_LOG_TEMP"
echo "" >> "$ARQUIVO_LOG_TEMP"
echo "DETALHES POR ARQUIVO:" >> "$ARQUIVO_LOG_TEMP"

echo "Analisando arquivos..."
TOTAL_ARQUIVOS=$(find "$PASTA_ORIGEM" -type f | grep -E -i '\.(mp3|wav|m4a|ogg|flac|aac)$' | wc -l)

if [ "$TOTAL_ARQUIVOS" -eq 0 ]; then
    echo "Nenhum arquivo encontrado."
    rm "$ARQUIVO_LOG_TEMP"
    exit 0
fi

# --- LOOP PRINCIPAL ---
find "$PASTA_ORIGEM" -type f | grep -E -i '\.(mp3|wav|m4a|ogg|flac|aac)$' | while read -r ARQUIVO; do
    
    FILES_PROCESSED_COUNT=$((FILES_PROCESSED_COUNT+1))
    
    # 1. Cálculos de Caminho
    CAMINHO_RELATIVO="${ARQUIVO#$PASTA_ORIGEM/}"
    DIRETORIO_RELATIVO=$(dirname "$CAMINHO_RELATIVO")
    PASTA_FINAL="$PASTA_DESTINO/$DIRETORIO_RELATIVO"
    mkdir -p "$PASTA_FINAL"
    
    NOME_ARQUIVO=$(basename "$ARQUIVO")
    NOME_BASE="${NOME_ARQUIVO%.*}"
    CAMINHO_SAIDA_OTIMIZADO="$PASTA_FINAL/$NOME_BASE.ogg"
    CAMINHO_SAIDA_COPIA="$PASTA_FINAL/$NOME_ARQUIVO"
    
    TAMANHO_ATUAL_ARQ=$(wc -c < "$ARQUIVO")
    TOTAL_BYTES_ORIGINAL=$(echo "$TOTAL_BYTES_ORIGINAL + $TAMANHO_ATUAL_ARQ" | bc)
    
    # 2. Cálculo de ETA (Tempo Estimado)
    NOW=$(date +%s)
    ELAPSED=$((NOW - START_GLOBAL))
    if [ "$FILES_PROCESSED_COUNT" -gt 1 ]; then
        AVG_TIME_PER_FILE=$(echo "$ELAPSED / ($FILES_PROCESSED_COUNT - 1)" | bc) # Baseado nos anteriores
        if [ "$AVG_TIME_PER_FILE" -eq 0 ]; then AVG_TIME_PER_FILE=1; fi
        FILES_REMAINING=$((TOTAL_ARQUIVOS - FILES_PROCESSED_COUNT + 1))
        ETA_SEC=$((FILES_REMAINING * AVG_TIME_PER_FILE))
        ETA_STR=$(format_time $ETA_SEC)
    else
        ETA_STR="Calculando..."
    fi

    # String de Economia atual formatada
    SAVED_STR=$(format_size $BYTES_ECONOMIZADOS)

    # 3. Exibição do Cabeçalho do Arquivo (Limpa a linha anterior)
    # \033[K limpa do cursor até o fim da linha
    echo -e "\n---------------------------------------------------"
    echo -e "Arq: [$FILES_PROCESSED_COUNT/$TOTAL_ARQUIVOS] $NOME_ARQUIVO"
    echo -e "Status: Econ. Acumulada: \033[1;32m$SAVED_STR\033[0m | ETA: \033[1;33m$ETA_STR\033[0m"

    # 4. Análise e Processamento
    eval $(ffprobe -v quiet -select_streams a:0 -show_entries format=duration -show_entries stream=bit_rate -of default=noprint_wrappers=1:nokey=0 "$ARQUIVO" | tr '\n' ' ')
    BITRATE_CHECK=${bit_rate:-999999} 
    DURACAO_TOTAL_US=$(echo "$duration * 1000000" | bc 2>/dev/null | awk '{print int($1)}')
    if [ -z "$DURACAO_TOTAL_US" ] || [ "$DURACAO_TOTAL_US" -eq 0 ]; then DURACAO_TOTAL_US=1000000; fi

    RESULTADO_TIPO=""
    TAMANHO_FINAL_ARQ=0

    # Lógica de Decisão
    if [ "$BITRATE_CHECK" -le $((BITRATE_ALVO + 2000)) ]; then
        echo "   -> Já otimizado. Copiando..."
        cp -p "$ARQUIVO" "$CAMINHO_SAIDA_COPIA"
        TAMANHO_FINAL_ARQ=$TAMANHO_ATUAL_ARQ
        RESULTADO_TIPO="IGNORADO (Bitrate Baixo)"
    else
        # Conversão com barra
        ffmpeg -y -i "$ARQUIVO" -c:a libopus -b:a "$BITRATE_FFMPEG" -nostdin -progress pipe:1 "$CAMINHO_SAIDA_OTIMIZADO" 2>/dev/null | \
        while IFS= read -r line; do
            if [[ "$line" == "out_time_us="* ]]; then
                CURRENT_US=${line#*=}
                if [[ "$CURRENT_US" != "N/A" ]]; then
                    progress_bar "$CURRENT_US" "$DURACAO_TOTAL_US"
                fi
            fi
        done
        echo "" # Pula linha da barra

        if [ -f "$CAMINHO_SAIDA_OTIMIZADO" ]; then
            TAMANHO_NOVO=$(wc -c < "$CAMINHO_SAIDA_OTIMIZADO")
            if [ "$TAMANHO_NOVO" -ge "$TAMANHO_ATUAL_ARQ" ]; then
                rm "$CAMINHO_SAIDA_OTIMIZADO"
                cp -p "$ARQUIVO" "$CAMINHO_SAIDA_COPIA"
                TAMANHO_FINAL_ARQ=$TAMANHO_ATUAL_ARQ
                RESULTADO_TIPO="DESCARTADO (Ficou Maior)"
            else
                TAMANHO_FINAL_ARQ=$TAMANHO_NOVO
                RESULTADO_TIPO="OTIMIZADO"
            fi
        else
            cp -p "$ARQUIVO" "$CAMINHO_SAIDA_COPIA"
            TAMANHO_FINAL_ARQ=$TAMANHO_ATUAL_ARQ
            RESULTADO_TIPO="ERRO (Copiado Original)"
        fi
    fi

    # Atualiza Estatísticas Globais
    TOTAL_BYTES_NOVO=$(echo "$TOTAL_BYTES_NOVO + $TAMANHO_FINAL_ARQ" | bc)
    DIFERENCA=$(echo "$TAMANHO_ATUAL_ARQ - $TAMANHO_FINAL_ARQ" | bc)
    if [ "$DIFERENCA" -gt 0 ]; then
        BYTES_ECONOMIZADOS=$(echo "$BYTES_ECONOMIZADOS + $DIFERENCA" | bc)
    fi

    # Grava no log temporário
    REDUCAO_PC=$(awk "BEGIN {printf \"%.1f\", 100 - ($TAMANHO_FINAL_ARQ * 100 / $TAMANHO_ATUAL_ARQ)}")
    echo "[$FILES_PROCESSED_COUNT/$TOTAL_ARQUIVOS] $CAMINHO_RELATIVO | $RESULTADO_TIPO | Redução: $REDUCAO_PC%" >> "$ARQUIVO_LOG_TEMP"

done

# --- FINALIZAÇÃO E RELATÓRIO ---
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

# Monta o rodapé do log
echo "" >> "$ARQUIVO_LOG_TEMP"
echo "========================================================" >> "$ARQUIVO_LOG_TEMP"
echo "RESUMO FINAL" >> "$ARQUIVO_LOG_TEMP"
echo "========================================================" >> "$ARQUIVO_LOG_TEMP"
echo "Tempo Total de Processamento: $TEMPO_TOTAL_FMT" >> "$ARQUIVO_LOG_TEMP"
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
echo -e "PROCESSAMENTO CONCLUÍDO COM SUCESSO!"
echo -e "Tempo Total: \033[1;34m$TEMPO_TOTAL_FMT\033[0m"
echo -e "Economia Total: \033[1;32m$STR_ECONOMIA\033[0m ($PC_GLOBAL% reduzido)"
echo -e "Relatório detalhado salvo em: $ARQUIVO_LOG"
echo "========================================================"
