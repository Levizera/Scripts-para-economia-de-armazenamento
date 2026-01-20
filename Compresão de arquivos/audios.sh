#!/bin/bash

# --- CONFIGURAÇÕES VISUAIS ---
tput civis # Esconde cursor
clear

# Cores
C_RESET='\033[0m'
C_GREEN='\033[1;32m'
C_BLUE='\033[1;34m'
C_GRAY='\033[1;30m'
C_CYAN='\033[1;36m'
C_WHITE='\033[1;37m'
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
if [[ "$OSTYPE" == "linux-gnu"* ]] || [[ "$OSTYPE" == "msys" ]]; then
    TOTAL_CORES=$(nproc)
elif [[ "$OSTYPE" == "darwin"* ]]; then
    TOTAL_CORES=$(sysctl -n hw.ncpu)
else
    TOTAL_CORES=2
fi

# REGRA DE OURO: Deixa 1 núcleo livre para o sistema e para evitar gargalo de I/O
if [ "$TOTAL_CORES" -gt 1 ]; then
    MAX_JOBS=$((TOTAL_CORES - 1))
else
    MAX_JOBS=1
fi

echo -e "${C_BLUE}=== Otimizador v15.0 (Balanced Performance) ===${C_RESET}"
echo "CPUs Totais: $TOTAL_CORES | Workers Ativos: $MAX_JOBS (1 Core Livre)"
echo "Otimização: Single-thread per file (Máxima eficiência por núcleo)"
echo "Cole o caminho da pasta:"
tput cnorm; read -r INPUT_RAW; tput civis

PASTA_ORIGEM=$(echo "$INPUT_RAW" | tr -d "'\"")
PASTA_ORIGEM="${PASTA_ORIGEM%/}" 

if [ ! -d "$PASTA_ORIGEM" ]; then echo "ERRO: Pasta não encontrada."; exit 1; fi

PASTA_DESTINO="${PASTA_ORIGEM}_otimizados"
mkdir -p "$PASTA_DESTINO"
BITRATE_ALVO=32000
BITRATE_FFMPEG="32k"

# Temp Dir
DIR_TEMP="temp_opt_$$"
mkdir -p "$DIR_TEMP"

# Inicializa Slots
for ((i=1; i<=MAX_JOBS; i++)); do
    echo "LIVRE" > "$DIR_TEMP/status_$i"
    echo "---" > "$DIR_TEMP/file_$i"
    echo "0" > "$DIR_TEMP/pct_$i"
    echo "--:-- / --:--" > "$DIR_TEMP/time_$i"
done

echo "0" > "$DIR_TEMP/completed"
echo "0" > "$DIR_TEMP/saved"

# Mapeamento
echo "Mapeando arquivos..."
mapfile -t LISTA_ARQUIVOS < <(find "$PASTA_ORIGEM" -type f | grep -E -i '\.(mp3|wav|m4a|ogg|flac|aac)$')
TOTAL_ARQUIVOS=${#LISTA_ARQUIVOS[@]}

if [ "$TOTAL_ARQUIVOS" -eq 0 ]; then echo "Nada encontrado."; rm -rf "$DIR_TEMP"; exit 0; fi

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
        
        echo -e "${C_WHITE}OTIMIZADOR DE ÁUDIO${C_RESET} ${C_GRAY}|${C_RESET} ${PASTA_DESTINO/$HOME/~} ${CLR_EOL}"
        echo -e "Progresso: ${C_WHITE}$PCT_GLOBAL%${C_RESET} ($DONE/$TOTAL_ARQUIVOS)  Economia: ${C_GREEN}$SAVED_STR${C_RESET} ${CLR_EOL}"
        echo -e "${C_GRAY}────────────────────────────────────────────────────────────────────────────────${C_RESET}${CLR_EOL}"
        printf "${C_GRAY}%-5s %-10s %-8s %-17s %-s${C_RESET}${CLR_EOL}\n" "CORE" "STATUS" "PROG" "TEMPO AULA" "ARQUIVO"
        
        for ((i=1; i<=MAX_JOBS; i++)); do
            STATUS=$(cat "$DIR_TEMP/status_$i" 2>/dev/null)
            FILE=$(cat "$DIR_TEMP/file_$i" 2>/dev/null)
            PCT=$(cat "$DIR_TEMP/pct_$i" 2>/dev/null)
            TIME=$(cat "$DIR_TEMP/time_$i" 2>/dev/null)
            
            C_STAT=$C_WHITE
            if [[ "$STATUS" == "LIVRE" ]]; then C_STAT=$C_GRAY; 
            elif [[ "$STATUS" == "CONCLUIDO" ]]; then C_STAT=$C_GREEN;
            elif [[ "$STATUS" == "OTIMIZANDO" ]]; then C_STAT=$C_BLUE;
            elif [[ "$STATUS" == "IGNORADO" ]]; then C_STAT=$C_CYAN; fi
            
            if [ ${#FILE} -gt 35 ]; then FILE_SHOW="${FILE:0:32}..."; else FILE_SHOW="$FILE"; fi
            
            if [[ "$STATUS" == "LIVRE" ]]; then
                printf "%-5s ${C_GRAY}%-10s %-8s %-17s %-s${C_RESET}${CLR_EOL}\n" "#$i" "Ocioso" "---" "--:-- / --:--" ""
            else
                printf "%-5s ${C_STAT}%-10s${C_RESET} %-8s %-17s %-s${CLR_EOL}\n" "#$i" "${STATUS:0:10}" "${PCT}%" "$TIME" "$FILE_SHOW"
            fi
        done
        
        echo -e "${C_GRAY}────────────────────────────────────────────────────────────────────────────────${C_RESET}${CLR_EOL}"
        tput ed
        
        if [ "$DONE" -ge "$TOTAL_ARQUIVOS" ]; then break; fi
        sleep 0.2
    done
}

# --- WORKER ---
process_worker() {
    local ARQUIVO="$1"
    local SLOT="$2"
    local NOME=$(basename "$ARQUIVO")
    
    echo "OTIMIZANDO" > "$DIR_TEMP/status_$SLOT"
    echo "$NOME" > "$DIR_TEMP/file_$SLOT"
    echo "0" > "$DIR_TEMP/pct_$SLOT"
    echo "Calculando..." > "$DIR_TEMP/time_$SLOT"

    local RELATIVO="${ARQUIVO#$PASTA_ORIGEM/}"
    local PASTA_FINAL="$PASTA_DESTINO/$(dirname "$RELATIVO")"
    mkdir -p "$PASTA_FINAL" 2>/dev/null
    
    local BASE="${NOME%.*}"
    local SAIDA="$PASTA_FINAL/$BASE.ogg"
    local COPIA="$PASTA_FINAL/$NOME"
    local T_ORIG=$(wc -c < "$ARQUIVO")
    local T_FINAL=$T_ORIG

    local DUR_SEC=$(ffprobe -v quiet -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$ARQUIVO" | awk '{print int($1)}')
    [ -z "$DUR_SEC" ] && DUR_SEC=1
    
    local H_TOT=$((DUR_SEC/3600))
    local M_TOT=$(((DUR_SEC%3600)/60))
    local S_TOT=$((DUR_SEC%60))
    local STR_TOTAL=$(printf "%02d:%02d" $M_TOT $S_TOT)
    if [ "$H_TOT" -gt 0 ]; then STR_TOTAL=$(printf "%02d:%02d:%02d" $H_TOT $M_TOT $S_TOT); fi

    local BR=$(ffprobe -v quiet -select_streams a:0 -show_entries stream=bit_rate -of default=noprint_wrappers=1:nokey=1 "$ARQUIVO")
    BR=${BR:-999999}

    if [ "$BR" -le $((BITRATE_ALVO + 2000)) ]; then
        cp -p "$ARQUIVO" "$COPIA"
        echo "IGNORADO" > "$DIR_TEMP/status_$SLOT"
        echo "100" > "$DIR_TEMP/pct_$SLOT"
        echo "$STR_TOTAL / $STR_TOTAL" > "$DIR_TEMP/time_$SLOT"
        sleep 0.5
    else
        # --- OTIMIZAÇÃO DE PERFORMANCE ---
        # -threads 1: Evita que um arquivo tente usar todos os núcleos. 
        # Isso reduz o overhead e aumenta a velocidade individual de cada worker.
        nice -n 15 ffmpeg -y -threads 1 -i "$ARQUIVO" -c:a libopus -b:a "$BITRATE_FFMPEG" -nostdin -progress pipe:1 "$SAIDA" 2>/dev/null | \
        while IFS= read -r line; do
            if [[ "$line" == "out_time_us="* ]]; then
                CUR_US=${line#*=}
                if [[ "$CUR_US" != "N/A" ]]; then
                    CUR_SEC=$((CUR_US / 1000000))
                    PCT=$(( (CUR_SEC * 100) / DUR_SEC ))
                    
                    CH=$((CUR_SEC/3600))
                    CM=$(((CUR_SEC%3600)/60))
                    CS=$((CUR_SEC%60))
                    STR_CUR=$(printf "%02d:%02d" $CM $CS)
                    if [ "$H_TOT" -gt 0 ]; then STR_CUR=$(printf "%02d:%02d:%02d" $CH $CM $CS); fi
                    
                    echo "$PCT" > "$DIR_TEMP/pct_$SLOT"
                    echo "$STR_CUR / $STR_TOTAL" > "$DIR_TEMP/time_$SLOT"
                fi
            fi
        done
        
        if [ -f "$SAIDA" ]; then
            T_NOVO=$(wc -c < "$SAIDA")
            if [ "$T_NOVO" -ge "$T_ORIG" ]; then
                rm "$SAIDA"; cp -p "$ARQUIVO" "$COPIA"
                echo "DESCARTADO" > "$DIR_TEMP/status_$SLOT"
            else
                T_FINAL=$T_NOVO
                echo "CONCLUIDO" > "$DIR_TEMP/status_$SLOT"
            fi
        else
            cp -p "$ARQUIVO" "$COPIA"
            echo "ERRO" > "$DIR_TEMP/status_$SLOT"
        fi
    fi
    echo "100" > "$DIR_TEMP/pct_$SLOT"
    
    read C < "$DIR_TEMP/completed"; echo $((C + 1)) > "$DIR_TEMP/completed"
    D=$((T_ORIG - T_FINAL))
    if [ "$D" -gt 0 ]; then read S < "$DIR_TEMP/saved"; echo $((S + D)) > "$DIR_TEMP/saved"; fi
    
    echo "LIVRE" > "$DIR_TEMP/status_$SLOT"
    echo "---" > "$DIR_TEMP/file_$SLOT"
    echo "--:-- / --:--" > "$DIR_TEMP/time_$SLOT"
}

# --- EXECUÇÃO ---
monitor_dashboard &
PID_MON=$!
cleanup() { kill $PID_MON 2>/dev/null; tput cnorm; rm -rf "$DIR_TEMP"; echo ""; }
trap cleanup EXIT

for ARQUIVO in "${LISTA_ARQUIVOS[@]}"; do
    while true; do
        SLOT=0
        for ((i=1; i<=MAX_JOBS; i++)); do
            if mkdir "$DIR_TEMP/lock_$i" 2>/dev/null; then SLOT=$i; break; fi
        done
        if [ "$SLOT" -gt 0 ]; then
            ( process_worker "$ARQUIVO" "$SLOT"; rmdir "$DIR_TEMP/lock_$SLOT" ) &
            break
        else
            sleep 0.5
        fi
    done
done
wait; sleep 2