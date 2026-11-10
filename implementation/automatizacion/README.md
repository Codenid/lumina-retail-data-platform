# Automatización de infraestructura

Scripts y contratos para crear, configurar y validar la plataforma en GCP. La
lógica desplegable vive en [`../soluciones/`](../soluciones/).

| Carpeta | Propósito |
|---|---|
| [`scripts/`](scripts/) | scripts numerados, idempotentes y su preflight común |
| [`configuracion/`](configuracion/) | manifiesto de ejecución y contratos de recursos/datos |
| [`utilidades/`](utilidades/) | validadores y generadores comunes |

## Uso rápido

Desde `implementation/`:

```bash
cp config.env.example config.env
# Completa PROJECT_ID, REGION, NETWORK, PREFIX y DEMO_RUN_ID
bash automatizacion/scripts/00_verificar_acceso.sh
bash automatizacion/scripts/00_runbook.sh
```

Los scripts son numerados e idempotentes. No edites `state/` ni ejecutes
recursos aislados sin respetar el runbook.
