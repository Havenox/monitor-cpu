# Monitor de Temperatura

Script Bash para monitorar a temperatura da CPU, limitar processos que causam superaquecimento e enviar notificações via **webhook HTTP**.

---

# Por que criei este projeto

Criei este projeto porque eu precisava **monitorar e resolver problemas de temperatura** que estavam ocorrendo no meu **home server / homelab**, montado para estudos, desenvolvimento e projetos pessoais.  
Eu uso um **notebook antigo** como servidor caseiro rodando **Ubuntu Server**, e durante alguns testes de aplicações (como servidores de jogos, automações e containers), percebi que o processador aquecia demais — chegando próximo dos limites de segurança.

Como o sistema não tinha controle térmico automatizado (e ferramentas gráficas não são práticas em ambiente servidor), decidi desenvolver uma **solução leve, em shell script**, capaz de:
- Detectar aumento de temperatura via `lm-sensors`;
- Identificar automaticamente o processo que está forçando a CPU;
- Aplicar limitação de uso (`cpulimit`) até o sistema estabilizar;
- E ainda enviar notificações via **webhook**, integrando com automações externas (usando n8n para notificar via WhatsApp, Discord, Telegram, E-mail e etc).

---

### 🖥️ Especificações do servidor utilizado
**Hostname:** `havenoxserver`  
**Modelo:** Acer Aspire 3 A315-42-R6FZ  
**CPU:** AMD Ryzen 5 3500U  
**GPU:** Radeon 540X  
**Memória:** 6 GB DDR4  
**Armazenamento:** SSD Samsung EVO 840 120 GB  
**Sistema Operacional:** Ubuntu Server 24 LTS (headless)

---


# Instalando Dependências:

## lm-sensors

#### Instalar lm-sensors:
```
sudo apt install lm-sensors -y
```

#### Detectar os sensores:
```
sudo sensors-detect
```

#### Copnfirmando:
```
sensors
```
## cpulimit

#### Instalar:
```
sudo apt install cpulimit -y
```

# Dependencias Opcionais (Normlamente já presentes)

## curl

#### Instalar:
```
sudo apt install curl -y
```

## bc

#### Instalar:
```
sudo apt install bc -y
```




# Script Principal

### Crie o Arquivo
```
sudo nano /usr/local/bin/monitor_cpu.sh
```

#### Cole o conteúdo abaixo e ajuste o valor da variável WEBHOOK_URL com o endpoint do seu listener:


```
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
```

### Dê a permissão execução:
```
sudo hmod +x /usr/local/bin/monitor_cpu.sh
```

# Crie o Serviço Systemd

### Crie o Arquivo
```
sudo nano /etc/systemd/system/monitor_cpu.service
```

### Conteúdo do serviço:
```
[Unit]
Description=Monitoramento de Temperatura da CPU
After=network.target

[Service]
ExecStart=/usr/local/bin/monitor_cpu.sh
Restart=always
User=root

[Install]
WantedBy=multi-user.target
```

### Ative o serviço:

#### Recarreque o daemon:
```
sudo systemctl daemon-reload
```

#### Habilite:
```
sudo systemctl enable monitor_cpu
```

#### Inicie:
```
sudo systemctl start monitor_cpu
```

#### Verifique o status
```
systemctl status monitor_cpu
```
#### Para ver logs em tempo real:
```
sudo journalctl -u monitor_cpu -f
```


# Funcionamento

- Monitora temperatura a cada 5 segundos.
- Quando ultrapassa 90 °C (ou a temperatura setada em TEMP_LIMIT), limita o processo com maior uso de CPU.
- Quando a temperatura cai 5°C abaixo da temperatura limite , remove as limitações.
- Quando atinge 97 °C (ou a temeratura setada em TEMP_CRITICAL), envia alerta crítico via webhook.
- Envia notificações JSON com o body no formato:
```
...
"body": 
{
    "servidor": "nome-do-servidor",
    "nivel": "aviso",
    "temperatura": "79.6",
    "mensagem": "Temperatura alta: processo limitado",
    "pid": "1331415",
    "processo": "hping3",
    "cpu_uso": "94.0"
},
...
```


# Autor

Projeto criado por [Eduardo Nascimento (Havenox)](https://github.com/Havenox) para automação de segurança térmica em servidores Linux.
- [Instagram](https://www.instagram.com/eduardohavenox/)
- [Twitter](https://x.com/Havenox)
