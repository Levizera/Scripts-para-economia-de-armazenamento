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
C_PURPLE='\033[1;35m'
CLR_EOL=$(tput el)

# --- FUNÇÕES ---
format_size() {
    local B=${1:-0}
    if [ "$B" -ge 1073741824 ]; then awk "BEGIN {printf \"%.2f GB\", $B/1073741824}";
    elif [ "$B" -ge 1048576 ]; then awk "BEGIN {printf \"%.2f MB\", $B/1048576}";
    elif [ "$B" -ge 1024 ]; then awk "BEGIN {printf \"%.2f KB\", $B/1024}";
    else echo "${B} B"; fi
}

# --- SETUP DE NÚCLEOS ---
if [[ "$OSTYPE" == "linux-gnu"* ]] || [[ "$OSTYPE" == "msys" ]]; then
    TOTAL_CORES=$(nproc)
elif [[ "$OSTYPE" == "darwin"* ]]; then
    TOTAL_CORES=$(sysctl -n hw.ncpu)
else
    TOTAL_CORES=2
fi

# Usa N-1 núcleos para não travar o PC
if [ "$TOTAL_CORES" -gt 1 ]; then
    MAX_JOBS=$((TOTAL_CORES - 1))
else
    MAX_JOBS=1
fi

echo -e "${C_PURPLE}=== CONVERSOR MP4 PARA MP3 (DASHBOARD) ===${C_RESET}"
echo "CPUs: $TOTAL_CORES | Workers Ativos: $MAX_JOBS"
echo "Config: MP3 VBR (Qualidade Alta) | Ignorando Vídeo"
echo "Cole o caminho da pasta:"
tput cnorm; read -r INPUT_RAW; tput civis

PASTA_ORIGEM=$(echo "$INPUT_RAW" | tr -d "'\"" | sed 's:/*$::')

if [ ! -d "$PASTA_ORIGEM" ]; then echo "ERRO: Pasta não encontrada."; exit 1; fi

PASTA_DESTINO="${PASTA_ORIGEM}_MP3"
mkdir -p "$PASTA_DESTINO"

# Diretório Temporário
DIR_TEMP="temp_mp3_dash_$$"
mkdir -p "$DIR_TEMP"

# Inicializa Slots
for ((i=1; i<=MAX_JOBS; i++)); do
    echo "LIVRE" > "$DIR_TEMP/status_$i"
    echo "---" > "$DIR_TEMP/file_$i"
    echo "0" > "$DIR_TEMP/pct_$i"
    echo "--:-- / --:--" > "$DIR_TEMP/time_$i"
done

echo "0" > "$DIR_TEMP/completed"

# Mapeamento
echo "Mapeando arquivos..."
mapfile -t LISTA_ARQUIVOS < <(find "$PASTA_ORIGEM" -type f -iname "*.mp4" | sort)
TOTAL_ARQUIVOS=${#LISTA_ARQUIVOS[@]}

if [ "$TOTAL_ARQUIVOS" -eq 0 ]; then echo "Nenhum arquivo MP4 encontrado."; rm -rf "$DIR_TEMP"; exit 0; fi

redraw_interface() { clear; }
trap redraw_interface WINCH

# --- MONITOR (DASHBOARD) ---
monitor_dashboard() {
    while true; do
        tput cup 0 0
        
        DONE=$(cat "$DIR_TEMP/completed")
        if [ "$TOTAL_ARQUIVOS" -gt 0 ]; then PCT_GLOBAL=$(( (DONE * 100) / TOTAL_ARQUIVOS )); else PCT_GLOBAL=0; fi
        
        # Cabeçalho
        echo -e "${C_WHITE}CONVERSOR MP3${C_RESET} ${C_GRAY}|${C_RESET} ${PASTA_DESTINO/$HOME/~} ${CLR_EOL}"
        echo -e "Progresso: ${C_WHITE}$PCT_GLOBAL%${C_RESET} ($DONE/$TOTAL_ARQUIVOS) ${CLR_EOL}"
        echo -e "${C_GRAY}────────────────────────────────────────────────────────────────────────────────${C_RESET}${CLR_EOL}"
        
        # Tabela
        printf "${C_GRAY}%-5s %-10s %-8s %-17s %-s${C_RESET}${CLR_EOL}\n" "CORE" "STATUS" "PROG" "DURAÇÃO" "ARQUIVO"
        
        for ((i=1; i<=MAX_JOBS; i++)); do
            STATUS=$(cat "$DIR_TEMP/status_$i" 2>/dev/null)
            FILE=$(cat "$DIR_TEMP/file_$i" 2>/dev/null)
            PCT=$(cat "$DIR_TEMP/pct_$i" 2>/dev/null)
            TIME=$(cat "$DIR_TEMP/time_$i" 2>/dev/null)
            
            C_STAT=$C_WHITE
            if [[ "$STATUS" == "LIVRE" ]]; then C_STAT=$C_GRAY; 
            elif [[ "$STATUS" == "CONCLUIDO" ]]; then C_STAT=$C_GREEN;
            elif [[ "$STATUS" == "CONVERTENDO" ]]; then C_STAT=$C_PURPLE;
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
        sleep 0.5
    done
}

# --- WORKER ---
process_worker() {
    local ARQUIVO="$1"
    local SLOT="$2"
    local NOME=$(basename "$ARQUIVO")
    
    echo "CONVERTENDO" > "$DIR_TEMP/status_$SLOT"
    echo "$NOME" > "$DIR_TEMP/file_$SLOT"
    echo "0" > "$DIR_TEMP/pct_$SLOT"
    echo "Calculando..." > "$DIR_TEMP/time_$SLOT"

    # Preparação
    local RELATIVO="${ARQUIVO#$PASTA_ORIGEM/}"
    local DIRETORIO_BASE=$(dirname "$RELATIVO")
    local PASTA_FINAL="$PASTA_DESTINO/$DIRETORIO_BASE"
    mkdir -p "$PASTA_FINAL" 2>/dev/null
    
    local NOME_BASE="${NOME%.*}"
    local SAIDA="$PASTA_FINAL/$NOME_BASE.mp3"
    local SAIDA_TEMP="$PASTA_FINAL/$NOME_BASE.temp.mp3"
    
    # Se já existe
    if [ -f "$SAIDA" ]; then
        echo "IGNORADO" > "$DIR_TEMP/status_$SLOT"
        echo "100" > "$DIR_TEMP/pct_$SLOT"
        sleep 0.2
        read C < "$DIR_TEMP/completed"; echo $((C + 1)) > "$DIR_TEMP/completed"
        
        echo "LIVRE" > "$DIR_TEMP/status_$SLOT"
        return
    fi

    # Duração (para barra de progresso)
    local DUR_SEC=$(ffprobe -v quiet -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$ARQUIVO" | awk '{print int($1)}')
    [ -z "$DUR_SEC" ] && DUR_SEC=1
    
    local H=$((DUR_SEC/3600)); local M=$(((DUR_SEC%3600)/60)); local S=$((DUR_SEC%60))
    local STR_TOT=$(printf "%02d:%02d:%02d" $H $M $S)

    # --- COMANDO CONVERSÃO (SIMPLE & FAST) ---
    # -vn: Ignora vídeo (muito rápido)
    # -c:a libmp3lame -q:a 2: MP3 Alta Qualidade VBR
    
    nice -n 10 ffmpeg -y -i "$ARQUIVO" \
    -vn -map a -c:a libmp3lame -q:a 2 \
    -threads 1 \
    -nostdin -progress pipe:1 "$SAIDA_TEMP" 2>/dev/null | \
    while IFS= read -r line; do
        if [[ "$line" == "out_time_us="* ]]; then
            CUR_US=${line#*=}
            if [[ "$CUR_US" != "N/A" ]]; then
                CUR_SEC=$((CUR_US / 1000000))
                PCT=$(( (CUR_SEC * 100) / DUR_SEC ))
                
                # Filtro de atualização (evita piscar)
                if (( PCT % 2 == 0 )); then
                    cH=$((CUR_SEC/3600)); cM=$(((CUR_SEC%3600)/60)); cS=$((CUR_SEC%60))
                    STR_CUR=$(printf "%02d:%02d:%02d" $cH $cM $cS)
                    echo "$PCT" > "$DIR_TEMP/pct_$SLOT"
                    echo "$STR_CUR / $STR_TOT" > "$DIR_TEMP/time_$SLOT"
                fi
            fi
        fi
    done
    
    if [ -f "$SAIDA_TEMP" ]; then
        mv "$SAIDA_TEMP" "$SAIDA"
        echo "CONCLUIDO" > "$DIR_TEMP/status_$SLOT"
    else
        echo "ERRO" > "$DIR_TEMP/status_$SLOT"
    fi
    
    echo "100" > "$DIR_TEMP/pct_$SLOT"
    read C < "$DIR_TEMP/completed"; echo $((C + 1)) > "$DIR_TEMP/completed"
    
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
