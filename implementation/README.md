# Lumina Lab — implementación guiada en GCP

Repositorio para aprovisionar y documentar una plataforma de datos Lumina
Retail en Google Cloud: ingesta streaming y batch, capas Bronze/Silver/Gold,
productos analíticos, API privada, gobierno, seguridad y observabilidad.

## Punto de entrada

| Necesidad | Ubicación |
|---|---|
| Entender la arquitectura y su equivalencia en GCP | [docs/arquitectura/](docs/arquitectura/) |
| Consultar los casos de uso Gold | [docs/funcional/casos-uso.md](docs/funcional/casos-uso.md) |
| Ejecutar el aprovisionamiento en orden | [docs/operacion/ejecucion-scripts.md](docs/operacion/ejecucion-scripts.md) |
| Leer el informe técnico de implementación | [docs/informe-tecnico/informe/](docs/informe-tecnico/informe/) |
| Revisar las soluciones que se despliegan | [soluciones/](soluciones/) |
| Revisar automatización, contratos y scripts | [automatizacion/](automatizacion/) |

## Ejecución inicial

```bash
cp config.env.example config.env
# Completa PROJECT_ID, REGION, NETWORK, PREFIX y DEMO_RUN_ID.
bash automatizacion/scripts/00_runbook.sh
bash automatizacion/scripts/00_verificar_acceso.sh
```

Continúa con los grupos definidos en [`automatizacion/configuracion/runbook.json`](automatizacion/configuracion/runbook.json).
Los scripts son idempotentes: verifican recursos existentes y se detienen ante
divergencias o permisos insuficientes.

## Alcance

La plataforma implementa el recorrido interno desde ingesta hasta Gold y API.
Los productores externos, consumidores externos y Looker permanecen fuera de
alcance. Dataflow y Dataproc se ejecutan temporalmente para las demostraciones;
los scripts de cierre controlan su costo.

`state/`, `.venv/` y `config.env` son locales y no se versionan. `state/` se
crea automáticamente para guardar evidencias e identificadores de cada
`DEMO_RUN_ID`.
