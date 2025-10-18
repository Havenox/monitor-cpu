#!/bin/bash
# Monitoramento dinâmico de temperatura com webhook e limitação automática

# Temperaturas de controle
TEMP_LIMIT=90       # Temperatura em que o script começa a agir
TEMP_CRITICAL=97    # Temperatura crítica (gera alerta crítico)
INTERVAL=5          # Intervalo de checagem em segundos
WEBHOOK_URL="ENDEREÇO_DO_LISTENER"
SERVER_NAME=$(hostname)
LIMIT_ACTIVE=0
LAST_PID=0

# Lê a temperatura da CPU
get_cpu_temp() {
    sensors | grep -i 'Tctl' | awk '{print $2}' | sed 's/+//g;s/°C//g' | head -n 1
}

# Identifica o processo com maior uso de CPU
get_top_process() {
    ps -eo pid,comm,%cpu --sort=-%cpu | awk 'NR==2 {print $1, $2, $3}'
}

# Envia dados via webhook
send_webhook() {
    local nivel=$1
    local temp=$2
    local msg=$3
    local pid=$4
    local pname=$5
    local pcpu=$6

    curl -s -X POST -H "Content-Type: application/json" \
         -d "{\"servidor\":\"$SERVER_NAME\",\"nivel\":\"$nivel\",\"temperatura\":\"$temp\",\"mensagem\":\"$msg\",\"pid\":\"$pid\",\"processo\":\"$pname\",\"cpu_uso\":\"$pcpu\"}" \
         "$WEBHOOK_URL" >/dev/null 2>&1
}

# Aplica limitação de CPU no processo identificado
apply_limit() {
    local pid=$1
    local pname=$2
    local temp=$3
    local pcpu=$4

    # evita recriar limite no mesmo processo
    if [[ $LIMIT_ACTIVE -eq 0 || $pid -ne $LAST_PID ]]; then
        pkill cpulimit 2>/dev/null
        cpulimit -p "$pid" -l 50 &
        LIMIT_ACTIVE=1
        LAST_PID=$pid
        echo "$(date) | Temperatura alta ($temp°C). Limitando $pname (PID=$pid, CPU=$pcpu%)"
        send_webhook "aviso" "$temp" "Temperatura alta: processo limitado" "$pid" "$pname" "$pcpu"
    fi
}

# Remove todas as limitações
remove_limit() {
    if [[ $LIMIT_ACTIVE -eq 1 ]]; then
        pkill cpulimit 2>/dev/null
        LIMIT_ACTIVE=0
        echo "$(date) | Temperatura normalizada. Limite removido."
        send_webhook "ok" "$1" "Temperatura normalizada: limite removido" "" "" ""
    fi
}

# Loop principal
while true; do
    TEMP=$(get_cpu_temp)
    if [[ -z "$TEMP" ]]; then
        echo "$(date) | Erro ao ler temperatura."
        sleep $INTERVAL
        continue
    fi

    if (( $(echo "$TEMP >= $TEMP_CRITICAL" | bc -l) )); then
        read PID PNAME PCPU <<<$(get_top_process)
        echo "$(date) | CRÍTICO: $TEMP°C! Processo: $PNAME ($PID, $PCPU%)"
        send_webhook "critico" "$TEMP" "Temperatura crítica detectada!" "$PID" "$PNAME" "$PCPU"

    elif (( $(echo "$TEMP >= $TEMP_LIMIT" | bc -l) )); then
        read PID PNAME PCPU <<<$(get_top_process)
        apply_limit "$PID" "$PNAME" "$TEMP" "$PCPU"

    elif (( $(echo "$TEMP < $TEMP_LIMIT - 5" | bc -l) )); then
        remove_limit "$TEMP"
    fi

    sleep $INTERVAL
done
