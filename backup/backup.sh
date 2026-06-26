#!/usr/bin/env bash
#
# backup.sh — Comprime un directorio, lo versiona con timestamp, lo deposita en
#             un destino y aplica una política de retención (borra backups viejos).
#
# Pensado para correr de forma desatendida desde cron en un nodo de un cluster
# HPC: por eso prioriza ser predecible, dejar rastro en un log y fallar de forma
# ruidosa pero controlada en lugar de dejar backups a medias.
#
# Uso:
#   ./backup.sh <directorio_origen> <directorio_destino> [dias_retencion]
#
# Ejemplo:
#   ./backup.sh /home/proyectos /mnt/backups 7
#
# Autor: Nicolás Rojo  —  parte de linux-sysadmin-toolkit

# -----------------------------------------------------------------------------
# Modo estricto de Bash.
#   -e          : aborta si cualquier comando devuelve error (no seguimos a ciegas).
#   -u          : un uso de variable no definida es un error (atrapa typos en nombres).
#   -o pipefail : si falla un comando dentro de un pipe (ej: tar | algo), el pipe falla.
# -----------------------------------------------------------------------------
set -euo pipefail

# Configuración por defecto.
readonly RETENTION_DAYS_DEFAULT=7
readonly LOG_FILE="${BACKUP_LOG_FILE:-/var/log/backup.log}"


# log() — un único punto para escribir mensajes con timestamp.
log() {
    local level="$1"; shift
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    echo "[${timestamp}] [${level}] $*" | tee -a "$LOG_FILE" >&2
}


# die() — loguea un error y corta la ejecución con código distinto de cero.
die() {
    log "ERROR" "$*"
    exit 1
}

# Validación de argumentos.
if [[ $# -lt 2 ]]; then
    die "Uso: $0 <directorio_origen> <directorio_destino> [dias_retencion]"
fi

readonly SOURCE_DIR="$1"
readonly DEST_DIR="$2"
readonly RETENTION_DAYS="${3:-$RETENTION_DAYS_DEFAULT}"

# El origen tiene que existir y ser un directorio
[[ -d "$SOURCE_DIR" ]] || die "El directorio origen no existe: $SOURCE_DIR"

# La retención tiene que ser un entero
[[ "$RETENTION_DAYS" =~ ^[0-9]+$ ]] || die "dias_retencion debe ser un entero, recibido: $RETENTION_DAYS"

# Creamos el destino si no existe
mkdir -p "$DEST_DIR" || die "No se pudo crear el directorio destino: $DEST_DIR"


# Construcción del nombre del archivo.
SOURCE_NAME="$(basename "$SOURCE_DIR")"
TIMESTAMP="$(date '+%Y%m%d_%H%M%S')"
readonly SOURCE_NAME TIMESTAMP
readonly ARCHIVE_NAME="${SOURCE_NAME}_${TIMESTAMP}.tar.gz"
readonly ARCHIVE_PATH="${DEST_DIR}/${ARCHIVE_NAME}"

log "INFO" "Iniciando backup de '${SOURCE_DIR}' -> '${ARCHIVE_PATH}'"


# Compresión.
# Escribimos primero a un archivo temporal (.part) y recién al terminar bien lo
# renombramos. Asi síi tar se corta a la mitad (disco lleno, OOM, etc.) no queremos
# dejar un .tar.gz truncado que parezca un backup válido. El rename es atómico.
readonly ARCHIVE_TMP="${ARCHIVE_PATH}.part"

if tar -czf "$ARCHIVE_TMP" -C "$(dirname "$SOURCE_DIR")" "$SOURCE_NAME"; then
    mv "$ARCHIVE_TMP" "$ARCHIVE_PATH"
    ARCHIVE_SIZE="$(du -h "$ARCHIVE_PATH" | cut -f1)"
    readonly ARCHIVE_SIZE
    log "INFO" "Backup creado correctamente (${ARCHIVE_SIZE}): ${ARCHIVE_PATH}"
else
    # Limpiamos el temporal para no dejar basura ocupando disco.
    rm -f "$ARCHIVE_TMP"
    die "Falló la compresión de ${SOURCE_DIR}"
fi


# Política de retención.
# Borramos backups de este mismo origen con más de RETENTION_DAYS días.
log "INFO" "Aplicando retención: borrando backups de '${SOURCE_NAME}' con más de ${RETENTION_DAYS} días"

deleted_count=0
while IFS= read -r old_backup; do
    log "INFO" "Eliminando backup vencido: ${old_backup}"
    deleted_count=$((deleted_count + 1))
done < <(find "$DEST_DIR" -maxdepth 1 -type f -name "${SOURCE_NAME}_*.tar.gz" -mtime "+${RETENTION_DAYS}" -print)

if find "$DEST_DIR" -maxdepth 1 -type f -name "${SOURCE_NAME}_*.tar.gz" -mtime "+${RETENTION_DAYS}" -delete; then
    log "INFO" "Retención completada. Backups eliminados: ${deleted_count}"
else
    log "WARN" "Hubo un problema aplicando la retención (el backup del día sí se completó)"
fi

log "INFO" "Proceso de backup finalizado OK"
exit 0


# EJEMPLO DE CRON JOB
# Editar el crontab del usuario root (o de un usuario de servicio dedicado):
#
#   sudo crontab -e
#
# Y agregar la siguiente línea para correr todos los días a las 2:00 AM:
#
#   0 2 * * *  /opt/linux-sysadmin-toolkit/backup/backup.sh /home/proyectos /mnt/backups 7 >> /var/log/backup.log 2>&1
