# create_user.sh

Alta de usuarios para un entorno multi-usuario tipo cluster académico.

## Qué problema resuelve

Dar de alta cuentas a mano es repetitivo y propenso a errores: olvidarse el grupo,
dejar el home con permisos demasiado abiertos, o no registrar quién creó la cuenta.
En un cluster con muchos investigadores y estudiantes esos descuidos se traducen
en problemas de privacidad y de auditoría. Este script estandariza el alta:

- Crea el usuario con su **home** (`-m`, copiando `/etc/skel`) y shell `bash`.
- Lo asigna a un **grupo de proyecto/laboratorio**, creándolo si no existe.
- Fija permisos del home en **750**: privado frente a otros usuarios, pero
  accesible al grupo del proyecto para poder colaborar.
- Fuerza el **cambio de contraseña en el primer login** (`chage -d 0`), para que
  el admin nunca conozca la contraseña definitiva.
- **Loguea** la acción con quién la ejecutó (`SUDO_USER`) y cuándo, para auditoría.

Es **idempotente y seguro**: exige root, valida el nombre de usuario contra la
convención POSIX y se niega a recrear un usuario que ya existe.

## Uso

```bash
sudo ./create_user.sh <usuario> <grupo> ["Nombre Completo"]
```

- `usuario` — nombre de la cuenta (minúsculas, dígitos, `_` o `-`).
- `grupo`   — grupo primario / de proyecto (se crea si falta).
- `"Nombre Completo"` — opcional, va al campo GECOS.

Ejemplo:

```bash
sudo ./create_user.sh jperez investigadores "Juan Perez"
# luego asignar contraseña temporal:
sudo passwd jperez
```

El log por defecto va a `/var/log/user_management.log` (override con
`USERADMIN_LOG_FILE`).

> Probalo en una **VM o contenedor descartable**: modifica cuentas reales del
> sistema.

## Integración con cron / flujo mayor

El alta de usuarios es una acción **puntual y deliberada**, no se agenda en cron.
Notas de integración:

- En un cluster real las identidades suelen estar centralizadas en
  **LDAP/FreeIPA/Active Directory**; el alta se haría contra el directorio
  (`ipa user-add`, `ldapadd`) y este script sirve para cuentas locales o de
  servicio, o como referencia del flujo.
- Pasos siguientes habituales: **cuota de disco** (`setquota`) y alta en el
  scheduler **Slurm** (`sacctmgr add user`).
- Para **altas masivas**, envolver el script en un bucle leyendo un CSV:

  ```bash
  while IFS=, read -r u g n; do
      sudo ./create_user.sh "$u" "$g" "$n"
  done < altas.csv
  ```
