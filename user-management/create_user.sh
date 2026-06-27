#!/usr/bin/env bash
#
# create_user.sh — Alta de un usuario en el sistema para un entorno multi-usuario
#                  tipo cluster académico.
#
# Crea el usuario, lo asigna a un grupo (lo crea si no existe), ajusta los permisos
# del home para privacidad entre usuarios, y deja registro auditable de la acción.
#
# Uso:
#   sudo ./create_user.sh <usuario> <grupo> ["Nombre Completo"]
#
# Ejemplo:
#   sudo ./create_user.sh jperez investigadores "Juan Perez"
#
# Autor: Nicolás Rojo  —  parte de linux-sysadmin-toolkit

set -euo pipefail

readonly LOG_FILE="${USERADMIN_LOG_FILE:-/var/log/user_management.log}"


# log() registro auditable de cada alta
log() {
    local level="$1"; shift
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    local actor="${SUDO_USER:-${USER:-desconocido}}"
    echo "[${timestamp}] [${level}] [by:${actor}] $*" | tee -a "$LOG_FILE"
}

die() {
    log "ERROR" "$*"
    exit 1
}

# Requiere privilegios de root.
if [[ "$(id -u)" -ne 0 ]]; then
    die "Este script debe ejecutarse como root (usá: sudo $0 ...)"
fi

# Validación de argumentos.
if [[ $# -lt 2 ]]; then
    die "Uso: $0 <usuario> <grupo> [\"Nombre Completo\"]"
fi

readonly USERNAME="$1"
readonly GROUPNAME="$2"
readonly FULLNAME="${3:-}" 

# Validacion del nombre de usuario contra la convención POSIX típica de useradd:
if ! [[ "$USERNAME" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
    die "Nombre de usuario inválido: '$USERNAME' (use minúsculas, dígitos, '_' o '-')"
fi


# si el usuario ya existe no se recrea
if id "$USERNAME" &>/dev/null; then
    die "El usuario '$USERNAME' ya existe; no se realizan cambios"
fi


# Aseguro que el grupo exista
if ! getent group "$GROUPNAME" &>/dev/null; then
    log "INFO" "El grupo '$GROUPNAME' no existe; creándolo"
    groupadd "$GROUPNAME" || die "No se pudo crear el grupo '$GROUPNAME'"
fi

# -----------------------------------------------------------------------------
# Creación del usuario.
#   -m                  : crea el home (/home/<usuario>) copiando /etc/skel.
#   -g "$GROUPNAME"      : grupo primario = el grupo del proyecto.
#   -s /bin/bash         : shell interactiva estándar (los usuarios del cluster
#                          se conectan por SSH y necesitan una shell utilizable).
#   -c "$FULLNAME"       : nombre completo en GECOS, útil para identificar dueños.
# -----------------------------------------------------------------------------
log "INFO" "Creando usuario '$USERNAME' (grupo primario: '$GROUPNAME', nombre: '${FULLNAME:-N/D}')"

if [[ -n "$FULLNAME" ]]; then
    useradd -m -g "$GROUPNAME" -s /bin/bash -c "$FULLNAME" "$USERNAME" \
        || die "Falló useradd para '$USERNAME'"
else
    useradd -m -g "$GROUPNAME" -s /bin/bash "$USERNAME" \
        || die "Falló useradd para '$USERNAME'"
fi


HOME_DIR="$(getent passwd "$USERNAME" | cut -d: -f6)"
readonly HOME_DIR

# Permisos del home.
chown "$USERNAME:$GROUPNAME" "$HOME_DIR" || die "No se pudo asignar dueño a $HOME_DIR"
chmod 750 "$HOME_DIR" || die "No se pudieron ajustar permisos de $HOME_DIR"
log "INFO" "Permisos de '$HOME_DIR' fijados en 750 (dueño: $USERNAME, grupo: $GROUPNAME)"

# Forzar cambio de contraseña en el primer login.
chage -d 0 "$USERNAME" || log "WARN" "No se pudo forzar el cambio de contraseña inicial para '$USERNAME'"

log "INFO" "Usuario '$USERNAME' creado correctamente. Recordá asignar contraseña: 'passwd $USERNAME'"
exit 0

# =============================================================================
# NOTAS DE INTEGRACIÓN
# =============================================================================
# - Este script cubre el alta de CUENTAS LOCALES.
# - El campo de cuotas de disco (setquota) y el alta en el scheduler (ej:
#   'sacctmgr add user' en Slurm) serían los pasos siguientes en un flujo completo.
# - No se suele agendar en cron: el alta de usuarios es una acción puntual y
#   deliberada. Si se necesitara un alta masiva, se envolvería este script en un
#   bucle leyendo un CSV (usuario,grupo,nombre), p. ej.:
#
#       while IFS=, read -r u g n; do sudo ./create_user.sh "$u" "$g" "$n"; done < altas.csv
# =============================================================================
