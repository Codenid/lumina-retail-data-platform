# Soluciones desplegables

Este directorio contiene exclusivamente las definiciones que los scripts
empaquetan o despliegan en Google Cloud. Los contratos, manifiestos y
utilidades de aprovisionamiento viven en [`../automatizacion/`](../automatizacion/).

| Capacidad | Tecnología y destino GCP | Artefacto | Scripts consumidores |
|---|---|---|---|
| API de Insights | Cloud Run | `api-insights/` | 63–67 |
| Procesamiento streaming | Apache Beam / Dataflow | `procesamiento-streaming/` | 07–13, 43–48 |
| Procesamiento batch demostrativo | Apache Spark / Dataproc | `procesamiento-batch/` | 23, 90 |
| Orquestación batch | Google Cloud Workflows | `orquestacion-batch/` | 20, 25–28, 50–53 |

No ejecutar directamente los artefactos de este directorio contra GCP. Usar
los scripts numerados: resuelven identidades, contratos, parámetros,
idempotencia, estado y validación posterior.
