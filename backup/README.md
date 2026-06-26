# backup.sh

Backup comprimido y versionado de un directorio, con política de retención.

## Qué problema resuelve

En un cluster los datos de proyectos y la configuración del sistema necesitan
respaldo periódico y automático. Un backup hecho a mano se olvida; uno mal hecho
(archivo truncado, disco que se llena con backups viejos) es peor que ninguno.
Este script automatiza el ciclo completo de forma segura:

- Comprime el directorio origen en un `.tar.gz`.
- Le agrega **timestamp** al nombre (`origen_YYYYMMDD_HHMMSS.tar.gz`) para no pisar
  backups previos y poder ordenarlos cronológicamente.
- Lo deposita en un directorio destino (puede ser otro disco o un montaje de red).
- Borra automáticamente los backups de ese mismo origen con más de **N días**
  (retención configurable) para que el destino no crezca indefinidamente.

Decisiones de robustez destacadas:

- **Escritura atómica**: comprime a un archivo `.part` y solo lo renombra al
  terminar bien, así nunca queda un `.tar.gz` corrupto que parezca válido.
- **Rutas relativas** en el tar, para poder restaurar en cualquier ubicación.
- **Falla ruidosa**: si la compresión falla, sale con código distinto de cero
  (cron puede detectarlo) y no toca la retención.

## Uso

```bash
./backup.sh <directorio_origen> <directorio_destino> [dias_retencion]
```

- `directorio_origen`  — qué respaldar (obligatorio).
- `directorio_destino` — dónde dejar el `.tar.gz` (se crea si no existe).
- `dias_retencion`     — días a conservar (opcional, por defecto **7**).

Ejemplo:

```bash
./backup.sh /home/proyectos /mnt/backups 7
```

El log por defecto va a `/var/log/backup.log`; se puede cambiar con la variable
`BACKUP_LOG_FILE`.

## Ejemplo de integración con cron

Backup diario a las **2:00 AM** (ventana de baja actividad del cluster):

```cron
0 2 * * *  /opt/linux-sysadmin-toolkit/backup/backup.sh /home/proyectos /mnt/backups 7 >> /var/log/backup.log 2>&1
```

Instalarlo en el crontab de root:

```bash
sudo crontab -e
```

El `>> ... 2>&1` captura cualquier salida inesperada además del log interno del
script. Restaurar un backup es un simple `tar -xzf <archivo>.tar.gz -C /destino`.
