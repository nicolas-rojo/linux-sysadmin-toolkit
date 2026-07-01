# ssh-audit

Analiza un archivo de log de autenticación (`auth.log`) y genera un reporte
de intentos fallidos de conexión SSH: total de intentos, IPs más activas y
usuarios más atacados.

## Problema que resuelve

En un servidor Linux expuesto a internet, los intentos de acceso SSH por fuerza
bruta son constantes. Este script permite identificar rápidamente qué IPs están
atacando y qué usuarios están siendo probados, como primer paso para tomar
medidas (bloqueo con `iptables`, `fail2ban`, etc.).

## Uso

```bash
./ssh-audit.sh <archivo.log>
```

El reporte se imprime en stdout. Para guardarlo en un archivo:

```bash
./ssh-audit.sh /var/log/auth.log >> reporte-ssh.log
```

## Ejemplo de output
```text
=== SSH Brute Force Report ===

Total intentos fallidos: 30

Top IPs atacantes:
12 203.0.113.45
12 198.51.100.17
6 192.0.2.88

Usuarios más atacados:
12 root
3 admin
3 ubuntu
```


## Archivo de ejemplo

`sample-auth.log` contiene un log sintético con el formato exacto de Ubuntu 24
en WSL2, con tres IPs atacantes y distintos patrones de usuario. Útil para
probar el script sin necesidad de un servidor real bajo ataque.

## Notas técnicas

- Maneja correctamente las líneas de resumen que genera sshd
  (`message repeated N times`) sin contar doble ni perder intentos.
- Distingue entre `Failed password for root` (usuario válido) y
  `Failed password for invalid user X` (usuario inexistente).
- Compatible con el formato de timestamp ISO 8601 que usa Ubuntu 24+
  (`2026-06-29T21:57:25...`) y con el formato clásico de syslog.
- No modifica ni filtra el log original — solo lectura.