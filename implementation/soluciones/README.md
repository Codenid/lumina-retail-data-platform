# Soluciones desplegables

Este directorio contiene exclusivamente las definiciones que los scripts
empaquetan o despliegan en Google Cloud. Los contratos, manifiestos y
utilidades de aprovisionamiento viven en [`../automatizacion/`](../automatizacion/).

| Capacidad | Tecnología y destino GCP | Artefacto | Scripts consumidores |
|---|---|---|---|
| API de Insights | Cloud Run | `api-insights/` | 63–67 |
| Productora de datos | Cloud Run privado → Pub/Sub, Cloud Storage, BigQuery Bronze | `productor-datos/` | `productor-datos/deploy.sh` |
| Procesamiento streaming | Apache Beam / Dataflow | `procesamiento-streaming/` | 07–13, 43–48 |
| Procesamiento batch demostrativo | Apache Spark / Dataproc | `procesamiento-batch/` | 23, 90 |
| Orquestación batch | Google Cloud Workflows | `orquestacion-batch/` | 20, 25–28, 50–53 |

## Uso

No ejecutes directamente estos artefactos contra GCP. Desde `implementation/`,
usa los scripts numerados o el runbook; ellos resuelven identidades, contratos,
parámetros, idempotencia, estado y validación posterior.

Cada subcarpeta contiene una ficha breve de su capacidad y los scripts que la
gestionan.
