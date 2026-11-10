# Operación

Guías para desplegar, validar y cerrar recursos de la demostración.

- `ejecucion-scripts.md`: orden de instalación, dependencias y cierres de recursos temporales.
- `runbooks/`: guías breves de validación manual, una por grupo funcional.

Los runbooks complementan la verificación automatizada: indican qué servicio
abrir, qué recurso observar y qué cierre operativo aplicar. Se generan desde
`runbooks/generar_runbooks.py` para mantener estructura uniforme.

## Inicio

Desde `implementation/`, prepara `config.env` y ejecuta:

```bash
bash automatizacion/scripts/00_verificar_acceso.sh
bash automatizacion/scripts/00_runbook.sh
```

Para una validación puntual, abre el runbook del grupo funcional y sigue su
orden; no uses valores distintos a los definidos en `config.env`.
