# Capturas reales de GCP

Esta carpeta contiene las capturas PNG disponibles de la revisión manual de GCP. Las capturas acreditan únicamente las pantallas y resultados visibles en esta entrega; no sustituyen los logs o validaciones automatizadas.
Cada captura PNG definitiva debe mostrar el proyecto correcto, el servicio, el recurso y la
señal que permite validar la capacidad. Ocultar secretos, tokens, correos
personales, IDs de sesión y payloads sensibles.

| ID | Carpeta y archivo | Evidencia que debe mostrar | Estado 07-11-2026 |
|---|---|---|---|
| EV-ARC-01 | `01-fundacion/01-inventario-servicios.png` | APIs o inventario base de la plataforma | CAPTURADO |
| EV-DAT-01 | `01-fundacion/02-storage-buckets.png` | buckets Landing, Bronze, Artifacts y Models | CAPTURADO |
| EV-DAT-02 | `01-fundacion/03-bigquery-medallion.png` | datasets y tablas Bronze, Silver y Gold | CAPTURADO |
| EV-STR-01 | `02-streaming/01-pubsub-topico-suscripciones.png` | tópico y suscripciones de las dos ramas | CAPTURADO |
| EV-STR-02 | `02-streaming/02-dataflow-job.png` | job, región, worker y estado terminal | CAPTURADO |
| EV-STR-03 | `02-streaming/03-bq-bronze-silver-evento.png` | misma correlación en Bronze y Silver | CAPTURADO |
| EV-STR-04 | `03-insights/01-bq-insights-auditoria.png` | mismo `event_id` en Insights y auditoría | CAPTURADO |
| EV-BAT-01 | `04-batch/01-landing-transfer.png` | archivo y transferencia terminada | CAPTURADO |
| EV-BAT-02 | `04-batch/02-workflow-execution.png` | revisión, identidad y ejecución exitosa | CAPTURADO |
| EV-BAT-03 | `04-batch/03-bq-batch-mart.png` | batch trazable de Bronze hasta Mart | CAPTURADO |
| EV-GOL-01 | `05-forecast/01-features-predicciones-plan.png` | features, predicción, plan y artefacto | CAPTURADO |
| EV-API-01 | `06-consumo/01-cloud-run-servicio.png` | Cloud Run privado y revisión READY | CAPTURADO |
| EV-API-02 | `06-consumo/02-api-rutas.png` | HTTP 200 de las cuatro rutas de negocio | CAPTURADO |
| EV-GOL-02 | `06-consumo/03-bigquery-vistas.png` | vistas Gold y consulta con filas | CAPTURADO |
| EV-SEC-01 | `07-controles/03-seguridad-kms.png` | KMS y seguridad sin exponer secretos | CAPTURADO |

La ubicación exacta de cada captura y su criterio de aceptación están en el
informe técnico, secciones 4 a 10.
