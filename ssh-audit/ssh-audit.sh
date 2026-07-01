#!/usr/bin/env bash
#
# ssh-audit.sh -    Toma un log y cuenta intentos fallidos por ssh, mostrando atacantes y
#                   usuarios más atacados.
# Uso:
#       ./ssh-audit.sh <registro.log> [directorio_destino]
# Ejemplo:
#       ./ssh-audit.sh sample-auth.log log-ssh-audit.log
#
# Autor: Nicolás Rojo - parte de linux-sysadmin-toolkit

set -euo pipefail

# log() — un único punto para escribir mensajes con timestamp.
log() {
    local level="$1"; shift
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    local msg="[${timestamp}] [${level}] $*"

    if [[ -n "${LOG_FILE:-}" ]]; then
        echo "$msg" >> "$LOG_FILE"
    else
        echo "$msg" >&2
    fi
}

# die() — loguea un error y corta la ejecución con código distinto de cero.
die() {
    log "ERROR" "$*"
    exit 1
}

if [[ $# -lt 1 ]];then
    die "Uso: $0 <registro.log> [directorio_destino]"
fi

readonly INPUT_FILE="$1"

[[ -r "$INPUT_FILE" ]] || die "No se puede leer '$1'."

contar_ips() { 
    awk '/Failed password/ { 
    repeated = 1
    for(i=1;i<=NF;i++){
        if($i=="message"&&$(i+1)=="repeated"){
            repeated=$(i+2)
        }
        if($i=="from"){
            ips[$(i+1)]+=repeated
        }
    }
    }
    END {
        for(ip in ips){
            print ips[ip], ip
        }
    }' "$1"
}

contar_usuarios() { 
    awk '/Failed password/ { 
    repeated = 1
    for(i=1;i<=NF;i++){
        if($i=="message"&&$(i+1)=="repeated"){
            repeated=$(i+2)
        }
        if ($i=="for") {
            if ($(i+1)=="invalid")
                user=$(i+3)
            else
                user=$(i+1)

            users[user]+=repeated
        }
    }
    }
    END {
        for(user in users){
            print users[user], user
        }
    }' "$1"
}

echo "=== SSH Brute Force Report ==="

total=$( contar_ips "$INPUT_FILE" | awk '{ total+=$1 } END { print total }')

echo "Total intentos fallidos: $total"
echo

echo "Top IPs atacantes: "
contar_ips "$INPUT_FILE" | sort -k1,1 -nr

echo

echo "Usuarios mas atacados: "
contar_usuarios "$INPUT_FILE" | sort -k1,1 -nr