# Insights streaming

**Grupo:** `streaming_insights`  
**Consola GCP:** Pub/Sub, Dataflow y BigQuery

## Validación manual

1. Abrir el servicio indicado en la consola del proyecto configurado.
2. Filtrar recursos por `PREFIX` y revisar la región configurada.
3. Confirmar: El event_id de Insights aparece en Gold y auditoría.

## Validación por CLI — solo lectura

Ejecutar desde la raíz del repositorio. Estos comandos no crean, actualizan ni eliminan recursos:

```bash
source automatizacion/scripts/common.sh
gcloud pubsub subscriptions describe "${PREFIX}-insights-dataflow" --project="$PROJECT_ID" --format='yaml(topic,ackDeadlineSeconds)'
bq --project_id="$PROJECT_ID" show "$PROJECT_ID:$GOLD_DATASET.insights_streaming"
bq --project_id="$PROJECT_ID" show "$PROJECT_ID:$GOLD_DATASET.procesamiento_auditoria"
```

## Validación automática existente

Ejecutar únicamente los verificadores del grupo; no se relanzan scripts de aprovisionamiento:

```bash
bash automatizacion/scripts/47_verificar_insights.sh
bash automatizacion/scripts/48_cancelar_insights_evidencia.sh
```

Un verificador debe finalizar con `SCRIPT nn: 1` o la evidencia equivalente. Si devuelve `0`, conservar su salida y resolver la dependencia antes de reintentar.

## Cierre operativo

Cancelar el job Dataflow y confirmar CANCELLED.
