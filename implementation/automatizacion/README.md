# Automatización de infraestructura

Aquí se agrupan los artefactos que crean, configuran y validan la plataforma
en GCP. No contienen lógica de negocio desplegable; esa vive en
[`../soluciones/`](../soluciones/).

| Carpeta | Propósito |
|---|---|
| [`scripts/`](scripts/) | scripts numerados, idempotentes y su preflight común |
| [`configuracion/`](configuracion/) | manifiesto de ejecución y contratos de recursos/datos |
| [`utilidades/`](utilidades/) | validadores y generadores usados por los scripts |

El punto de entrada es `bash automatizacion/scripts/00_runbook.sh` después de
crear `config.env` desde `config.env.example`.
