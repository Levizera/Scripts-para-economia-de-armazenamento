#!/bin/bash

# --- CONFIGURAÇÕES VISUAIS ---
tput civis # Esconde cursor
clear

# Cores
C_RESET='\033[0m'
C_RED='\033[1;31m'
C_GREEN='\033[1;32m'
C_YELLOW='\033[1;33m'
C_WHITE='\033[1;37m'
C_CYAN='\033[1;36m'
C_GRAY='\033[1;30m'
CLR_EOL=$(tput el)

# --- FUNÇÕES ---
format_size() {
    local B=${1:-0}
    if [ "$B" -ge 1073741824 ]; then awk "BEGIN {printf \"%.2f GB\", $B/1073741824}";
    elif [ "$B" -ge 1048576 ]; then awk "BEGIN {printf \"%.2f MB\", $B/1048576}";
    elif [ "$B" -ge 1024 ]; then awk "BEGIN {printf \"%.2f KB\", $B/1024}";
    else echo "${B} B"; fi
}

# --- SETUP ---
echo -e "${C_CYAN}=== Otimizador v6.0 (ADAPTATIVO INTELIGENTE) ===${C_RESET}"

# Configuração de Threads
FFMPEG_THREADS=3 
MAX_JOBS=1

echo "Estratégia: Detecção de Resolução"
echo "  > Vídeos Grandes: Reduz para 720p (Max 1Mbps)"
echo "  > Vídeos Pequenos: Mantém resolução (Max 600kbps)"
echo "Cole o caminho da pasta:"
tput cnorm; read -r INPUT_RAW; tput civis

PASTA_ORIGEM=$(echo "$INPUT_RAW" | tr -d "'\"" | sed 's:/*$::')

if [ ! -d "$PASTA_ORIGEM" ]; then echo "ERRO: Pasta não encontrada."; exit 1; fi

PASTA_DESTINO="${PASTA_ORIGEM}_otimizados"
mkdir -p "$PASTA_DESTINO"

# Temp Dir
DIR_TEMP="temp_vid_smart_$$"
mkdir -p "$DIR_TEMP"

# Inicializa Slots
echo "LIVRE" > "$DIR_TEMP/status_1"
echo "---" > "$DIR_TEMP/file_1"
echo "0" > "$DIR_TEMP/pct_1"
echo "--:-- / --:--" > "$DIR_TEMP/time_1"
echo "---" > "$DIR_TEMP/res_1" # Nova info: Resolução

echo "0" > "$DIR_TEMP/completed"
echo "0" > "$DIR_TEMP/saved"

# Mapeamento
echo "Mapeando vídeos..."
mapfile -t LISTA_ARQUIVOS < <(find "$PASTA_ORIGEM" -type f -regextype posix-extended -iregex ".*\.(mp4|mkv|mov|avi|flv|webm|m4v|wmv)$" | sort)
TOTAL_ARQUIVOS=${#LISTA_ARQUIVOS[@]}

if [ "$TOTAL_ARQUIVOS" -eq 0 ]; then echo "Nenhum vídeo encontrado."; rm -rf "$DIR_TEMP"; exit 0; fi

redraw_interface() { clear; }
trap redraw_interface WINCH

# --- MONITOR ---
monitor_dashboard() {
    while true; do
        tput cup 0 0
        
        DONE=$(cat "$DIR_TEMP/completed")
        SAVED=$(cat "$DIR_TEMP/saved")
        SAVED_STR=$(format_size $SAVED)
        if [ "$TOTAL_ARQUIVOS" -gt 0 ]; then PCT_GLOBAL=$(( (DONE * 100) / TOTAL_ARQUIVOS )); else PCT_GLOBAL=0; fi
        
        echo -e "${C_WHITE}OTIMIZADOR SMART${C_RESET} ${C_GRAY}|${C_RESET} ${PASTA_DESTINO/$HOME/~} ${CLR_EOL}"
        echo -e "Progresso: ${C_WHITE}$PCT_GLOBAL%${C_RESET} ($DONE/$TOTAL_ARQUIVOS)  Economia: ${C_GREEN}$SAVED_STR${C_RESET} ${CLR_EOL}"
        echo -e "${C_GRAY}────────────────────────────────────────────────────────────────────────────────${C_RESET}${CLR_EOL}"
        
        printf "${C_GRAY}%-10s %-8s %-10s %-15s %-s${C_RESET}${CLR_EOL}\n" "STATUS" "PROG" "RES" "DURAÇÃO" "ARQUIVO"
        
        STATUS=$(cat "$DIR_TEMP/status_1" 2>/dev/null)
        FILE=$(cat "$DIR_TEMP/file_1" 2>/dev/null)
        PCT=$(cat "$DIR_TEMP/pct_1" 2>/dev/null)
        TIME=$(cat "$DIR_TEMP/time_1" 2>/dev/null)
        RES=$(cat "$DIR_TEMP/res_1" 2>/dev/null)
        
        C_STAT=$C_WHITE
        if [[ "$STATUS" == "LIVRE" ]]; then C_STAT=$C_GRAY; 
        elif [[ "$STATUS" == "CONCLUIDO" ]]; then C_STAT=$C_GREEN;
        elif [[ "$STATUS" == "OTIMIZANDO" ]]; then C_STAT=$C_CYAN;
        elif [[ "$STATUS" == "IGNORADO" ]]; then C_STAT=$C_YELLOW; fi
        
        if [ ${#FILE} -gt 35 ]; then FILE_SHOW="${FILE:0:32}..."; else FILE_SHOW="$FILE"; fi
        
        if [[ "$STATUS" == "LIVRE" ]]; then
            printf "${C_GRAY}%-10s %-8s %-10s %-15s %-s${C_RESET}${CLR_EOL}\n" "Ocioso" "---" "---" "--:-- / --:--" ""
        else
            printf "${C_STAT}%-10s${C_RESET} %-8s ${C_YELLOW}%-10s${C_RESET} %-15s %-s${CLR_EOL}\n" "${STATUS:0:10}" "${PCT}%" "$RES" "$TIME" "$FILE_SHOW"
        fi
        
        echo -e "${C_GRAY}────────────────────────────────────────────────────────────────────────────────${C_RESET}${CLR_EOL}"
        
        BAR_W=60
        FILLED=$(( (PCT * BAR_W) / 100 ))
        printf "${C_CYAN}"
        printf "%0.s▓" $(seq 1 $FILLED)
        printf "${C_GRAY}"
        printf "%0.s░" $(seq 1 $((BAR_W - FILLED)))
        printf "${C_RESET}${CLR_EOL}\n"
        
        tput ed
        
        if [ "$DONE" -ge "$TOTAL_ARQUIVOS" ]; then break; fi
        sleep 0.2
    done
}

# --- WORKER ---
process_worker() {
    local ARQUIVO="$1"
    local SLOT=1
    local NOME=$(basename "$ARQUIVO")
    
    echo "OTIMIZANDO" > "$DIR_TEMP/status_$SLOT"
    echo "$NOME" > "$DIR_TEMP/file_$SLOT"
    echo "0" > "$DIR_TEMP/pct_$SLOT"
    echo "Calculando..." > "$DIR_TEMP/time_$SLOT"
    echo "..." > "$DIR_TEMP/res_$SLOT"

    local RELATIVO="${ARQUIVO#$PASTA_ORIGEM/}"
    local DIRETORIO_BASE=$(dirname "$RELATIVO")
    local PASTA_FINAL="$PASTA_DESTINO/$DIRETORIO_BASE"
    mkdir -p "$PASTA_FINAL" 2>/dev/null
    
    local NOME_SEM_EXT="${NOME%.*}"
    local SAIDA="$PASTA_FINAL/$NOME_SEM_EXT.mp4"
    local SAIDA_TEMP="$PASTA_FINAL/$NOME_SEM_EXT.temp.mp4"
    
    if [ -f "$SAIDA" ]; then
        echo "IGNORADO" > "$DIR_TEMP/status_$SLOT"
        echo "100" > "$DIR_TEMP/pct_$SLOT"
        sleep 0.1
        read C < "$DIR_TEMP/completed"; echo $((C + 1)) > "$DIR_TEMP/completed"
        return
    fi

    local T_ORIG=$(wc -c < "$ARQUIVO")
    
    # 1. Analisa Vídeo (Duração e Largura)
    eval $(ffprobe -v error -select_streams v:0 -show_entries stream=width,height,duration -of default=noprint_wrappers=1:nokey=1 "$ARQUIVO" | tr '\n' ' ' | awk '{print "IN_W="$1; print "IN_H="$2; print "IN_D="$3}')
    
    local DUR_SEC=${IN_D%.*} # Remove decimais
    [ -z "$DUR_SEC" ] && DUR_SEC=1
    
    local H=$((DUR_SEC/3600)); local M=$(((DUR_SEC%3600)/60)); local S=$((DUR_SEC%60))
    local STR_TOT=$(printf "%02d:%02d:%02d" $H $M $S)

    # 2. Define Estratégia Baseada na Largura (IN_W)
    # Se largura for maior que 1280 (720p), reduz. Senão, mantém.
    if [ "$IN_W" -gt 1280 ]; then
        # MODO HD (Downscale)
        VF_FILTER="scale=1280:-2:flags=bilinear"
        MAX_BITRATE="1M"
        BUF_SIZE="2M"
        LABEL_RES="-> 720p"
    else
        # MODO SD (Mantém Original)
        VF_FILTER="null" # Filtro nulo (não faz nada)
        MAX_BITRATE="600k" # Bitrate menor para garantir redução em arquivos pequenos
        BUF_SIZE="1M"
        LABEL_RES="Original"
    fi
    
    echo "$LABEL_RES" > "$DIR_TEMP/res_$SLOT"

    # --- COMANDO FFMPEG ADAPTATIVO ---
    ffmpeg -y -i "$ARQUIVO" \
    -vf "$VF_FILTER" \
    -c:v libx264 -preset veryfast -b:v "$MAX_BITRATE" -maxrate "$MAX_BITRATE" -bufsize "$BUF_SIZE" \
    -c:a aac -b:a 96k -ac 2 \
    -threads "$FFMPEG_THREADS" \
    -movflags +faststart \
    -nostdin -progress pipe:1 "$SAIDA_TEMP" 2>/dev/null | \
    while IFS= read -r line; do
        if [[ "$line" == "out_time_us="* ]]; then
            CUR_US=${line#*=}
            if [[ "$CUR_US" != "N/A" ]]; then
                CUR_SEC=$((CUR_US / 1000000))
                PCT=$(( (CUR_SEC * 100) / DUR_SEC ))
                
                if (( PCT % 1 == 0 )); then
                    cH=$((CUR_SEC/3600)); cM=$(((CUR_SEC%3600)/60)); cS=$((CUR_SEC%60))
                    STR_CUR=$(printf "%02d:%02d:%02d" $cH $cM $cS)
                    echo "$PCT" > "$DIR_TEMP/pct_$SLOT"
                    echo "$STR_CUR / $STR_TOT" > "$DIR_TEMP/time_$SLOT"
                fi
            fi
        fi
    done
    
    if [ -f "$SAIDA_TEMP" ]; then
        T_NOVO=$(wc -c < "$SAIDA_TEMP")
        if [ "$T_NOVO" -gt 1024 ]; then
             mv "$SAIDA_TEMP" "$SAIDA"
             echo "CONCLUIDO" > "$DIR_TEMP/status_$SLOT"
             D=$((T_ORIG - T_NOVO))
             if [ "$D" -gt 0 ]; then read S < "$DIR_TEMP/saved"; echo $((S + D)) > "$DIR_TEMP/saved"; fi
        else
             rm "$SAIDA_TEMP"; cp "$ARQUIVO" "$SAIDA"
             echo "ERRO" > "$DIR_TEMP/status_$SLOT"
        fi
    else
        echo "ERRO" > "$DIR_TEMP/status_$SLOT"
    fi
    
    echo "100" > "$DIR_TEMP/pct_$SLOT"
    read C < "$DIR_TEMP/completed"; echo $((C + 1)) > "$DIR_TEMP/completed"
}

# --- EXECUÇÃO ---
monitor_dashboard &
PID_MON=$!
cleanup() { kill $PID_MON 2>/dev/null; tput cnorm; rm -rf "$DIR_TEMP"; echo ""; }
trap cleanup EXIT

for ARQUIVO in "${LISTA_ARQUIVOS[@]}"; do
    process_worker "$ARQUIVO" 1
done
wait; sleep 2