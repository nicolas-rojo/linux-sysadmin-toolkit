# healthcheck.sh

Chequeo de salud de un nodo: disco, memoria y carga de CPU, con alertas.

## Qué problema resuelve

En un cluster, un nodo con el disco lleno, swappeando o sobrecargado puede tirar
abajo los trabajos de varios usuarios sin previo aviso. Este script vigila las
tres métricas más comunes de saturación y avisa **antes** de que el problema
escale, dejando un registro claro y con timestamp.

Chequea:

- **Disco**: % de uso de la partición monitoreada (`/` por defecto).
- **Memoria**: % de RAM realmente usada, calculado con `MemAvailable` (no `free`),
  para no dar falsos positivos por la cache que Linux usa de forma sana.
- **Carga de CPU**: load average de 1 minuto **normalizado por core** (`load/nproc`),
  porque "load 8" es normal en 16 cores y grave en 2.

Si una métrica supera su umbral, escribe una línea `[ALERT]` en el log e invoca
`send_alert()`, el punto único donde se enchufa la notificación real.

## Uso

```bash
./healthcheck.sh
```

Umbrales y rutas se ajustan por variables de entorno (sin editar el script, para
poder distribuir el mismo archivo a muchos nodos):

| Variable | Default | Significado |
| -------- | ------- | ----------- |
| `DISK_THRESHOLD` | `90` | % de uso de disco que dispara alerta |
| `MEM_THRESHOLD`  | `90` | % de RAM usada que dispara alerta |
| `LOAD_THRESHOLD` | `2.0` | carga por core que dispara alerta |
| `DISK_MOUNT`     | `/` | partición a vigilar |
| `HEALTHCHECK_LOG_FILE` | `/var/log/healthcheck.log` | archivo de log |

Ejemplo (forzando una alerta de disco para probar, con log local):

```bash
DISK_THRESHOLD=10 HEALTHCHECK_LOG_FILE=./healthcheck.log ./healthcheck.sh
```

## Notificaciones reales

`send_alert()` hoy solo loguea, e incluye **comentados** tres caminos de
integración: correo con `mailx`, webhook a Slack/Mattermost con `curl`, y la
opción recomendada de empujar el estado a un sistema central
(Prometheus + Alertmanager, Nagios o Zabbix) que ya maneja deduplicación y
guardias. Se dejan comentados a propósito para no enviar alertas desde un entorno
de pruebas.

## Integración con cron

Chequeo cada **15 minutos** (buen balance entre detección temprana y ruido):

```cron
*/15 * * * *  /opt/linux-sysadmin-toolkit/monitor/healthcheck.sh >> /var/log/healthcheck.log 2>&1
```

Instalarlo en el crontab de root con `sudo crontab -e`. Para evitar tormentas de
alertas (el mismo problema cada 15 min), en producción se delega la deduplicación
a Alertmanager o similar.
