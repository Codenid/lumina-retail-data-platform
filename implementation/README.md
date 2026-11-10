# Implementación GCP

Implementación reproducible de Lumina Retail: ingesta, streaming, batch, Bronze/Silver/Gold, API, gobierno, seguridad y observabilidad.

## Inicio rápido

```bash
cp config.env.example config.env
# Completa PROJECT_ID, REGION, NETWORK, PREFIX y DEMO_RUN_ID
bash automatizacion/scripts/00_runbook.sh
bash automatizacion/scripts/00_verificar_acceso.sh
```

## Rutas útiles

- [Ejecución ordenada](docs/operacion/ejecucion-scripts.md)
- [Arquitectura y mapeo GCP](docs/arquitectura/README.md)
- [Automatización](automatizacion/README.md)
- [Soluciones](soluciones/README.md)
- [Pruebas](tests/)
- [Informe técnico](docs/informe-tecnico/informe/)

## Reglas

Los scripts son idempotentes y detienen la ejecución ante permisos o divergencias. `config.env`, `state/` y `.venv/` son locales y no deben versionarse. Dataflow y Dataproc pueden generar costos mientras están activos; revisa el estado antes y después de cada demostración.
