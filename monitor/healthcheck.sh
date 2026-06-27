#!/usr/bin/env bash
#
# healthcheck.sh — Chequeo de salud de un nodo: uso de disco, RAM y carga de CPU.
#
# Si alguna métrica supera su umbral configurable, deja una alerta clara y con
# timestamp en un log y (opcionalmente) dispara una notificación. Pensado para
# correr cada pocos minutos desde cron en cada nodo de un cluster HPC, donde un
# disco lleno o un nodo swappeando puede tirar abajo los trabajos de varios usuarios.
#
# Uso:
#   ./healthcheck.sh
#
# Los umbrales se pueden ajustar abajo o vía variables de entorno, por ejemplo:
#   DISK_THRESHOLD=85 MEM_THRESHOLD=90 ./healthcheck.sh
#
# Autor: Nicolas Rojo  —  parte de linux-sysadmin-toolkit

set -euo pipefail

# -----------------------------------------------------------------------------
# Umbrales configurables.
# Se exponen como variables de entorno con ":-" para poder ajustarlos sin tocar
# el script (útil cuando el mismo script se distribuye a muchos nodos con perfiles
# distintos: un nodo "fat" de memoria tolera más uso que uno chico).
#
#   DISK_THRESHOLD : % de uso de la partición monitoreada a partir del cual alertamos.
#   MEM_THRESHOLD  : % de RAM usada (sin contar buffers/cache) a partir del cual alertamos.
#   LOAD_THRESHOLD : carga promedio de 1 minuto POR CORE a partir de la cual alertamos.
#                    Se normaliza por core porque "load 8" es normal en 16 cores y
#                    grave en 2: lo que importa es la carga relativa a los CPUs disponibles.
# -----------------------------------------------------------------------------
readonly DISK_THRESHOLD="${DISK_THRESHOLD:-90}"
readonly MEM_THRESHOLD="${MEM_THRESHOLD:-90}"
readonly LOAD_THRESHOLD="${LOAD_THRESHOLD:-2.0}"   # 2.0 = 200% de carga por core


readonly DISK_MOUNT="${DISK_MOUNT:-/}"

readonly LOG_FILE="${HEALTHCHECK_LOG_FILE:-/var/log/healthcheck.log}"
HOSTNAME_SHORT="$(hostname -s 2>/dev/null || hostname 2>/dev/null || cat /etc/hostname 2>/dev/null || echo 'nodo')"
readonly HOSTNAME_SHORT

log() {
    local level="$1"; shift
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    echo "[${timestamp}] [${level}] [${HOSTNAME_SHORT}] $*" | tee -a "$LOG_FILE"
}


# send_alert() — punto único de envío de alertas.
send_alert() {
    local subject="$1"
    local body="$2"

    log "ALERT" "${subject} :: ${body}"

    # correo clásico con mailx
    #   echo "${body}" | mailx -s "[HEALTHCHECK] ${HOSTNAME_SHORT}: ${subject}" el@correo.algo
    #
    #webhook a Slack o similares
    #   curl -fsS -X POST -H 'Content-Type: application/json' \
    #     --data "{\"text\":\"[HEALTHCHECK] ${HOSTNAME_SHORT}: ${subject}\n${body}\"}" \
    #     "$SLACK_WEBHOOK_URL"
    #
    # otra posible opcion podría ser integración con un sistema de monitoreo central
    :
}


# Chequeo de DISCO.
check_disk() {
    local usage
    usage="$(df -P "$DISK_MOUNT" | awk 'NR==2 {gsub(/%/,"",$5); print $5}')"

    # Validar que se obtuvo un número
    if ! [[ "$usage" =~ ^[0-9]+$ ]]; then
        log "WARN" "No se pudo leer el uso de disco de ${DISK_MOUNT}"
        return
    fi

    log "INFO" "Disco ${DISK_MOUNT}: ${usage}% usado (umbral ${DISK_THRESHOLD}%)"
    if (( usage >= DISK_THRESHOLD )); then
        send_alert "Disco alto en ${DISK_MOUNT}" "Uso ${usage}% supera el umbral ${DISK_THRESHOLD}%"
    fi
}


# Chequeo de MEMORIA.
check_memory() {
    local mem_total mem_available used_pct
    mem_total="$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)"
    mem_available="$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo)"

    if [[ -z "$mem_total" || -z "$mem_available" || "$mem_total" -eq 0 ]]; then
        log "WARN" "No se pudo leer la memoria desde /proc/meminfo"
        return
    fi

    used_pct=$(( (mem_total - mem_available) * 100 / mem_total ))

    log "INFO" "Memoria: ${used_pct}% usada (umbral ${MEM_THRESHOLD}%)"
    if (( used_pct >= MEM_THRESHOLD )); then
        send_alert "Memoria alta" "Uso ${used_pct}% supera el umbral ${MEM_THRESHOLD}%"
    fi
}


# Chequeo de CARGA de CPU.
check_load() {
    local load1 cores load_per_core
    load1="$(awk '{print $1}' /proc/loadavg)"
    cores="$(nproc)"
    load_per_core="$(awk -v l="$load1" -v c="$cores" 'BEGIN { printf "%.2f", l / c }')"

    log "INFO" "Carga: ${load1} en ${cores} cores => ${load_per_core} por core (umbral ${LOAD_THRESHOLD})"

    # awk devuelve 0 (éxito) si la condición se cumple
    if awk -v lpc="$load_per_core" -v thr="$LOAD_THRESHOLD" 'BEGIN { exit !(lpc >= thr) }'; then
        send_alert "Carga de CPU alta" "Carga por core ${load_per_core} supera el umbral ${LOAD_THRESHOLD}"
    fi
}

# main —> corremos los tres chequeos.
main() {
    log "INFO" "=== Inicio healthcheck ==="
    check_disk
    check_memory
    check_load
    log "INFO" "=== Fin healthcheck ==="
}

main "$@"


# EJEMPLO DE CRON JOB
#
# Para correr el chequeo cada 15 minutos, editar el crontab de root:
#
#   sudo crontab -e
#
# y agregar:
#
#   */15 * * * *  /opt/linux-sysadmin-toolkit/monitor/healthcheck.sh >> /var/log/healthcheck.log 2>&1
#
# Desglose de "*/15 * * * *":
#   */15 -> cada 15 minutos (minutos 0, 15, 30, 45)
#   *    -> todas las horas
#   *    -> todos los días del mes
#   *    -> todos los meses
#   *    -> todos los días de la semana
#
# Notas:
#   - 15 minutos es un buen compromiso: suficientemente frecuente para detectar
#     problemas antes de que escalen, sin generar ruido ni carga innecesaria.
#   - Para evitar tormentas de alertas (el mismo problema alertando cada 15 min),
#     en producción se le agregaría deduplicación/silenciado, idealmente delegando
#     esa lógica a Alertmanager o similar (ver send_alert, la tercer opcion que mencioné).
