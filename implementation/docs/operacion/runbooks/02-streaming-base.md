# Streaming base

**Grupo:** `streaming_base`  
**Consola GCP:** Pub/Sub, Dataflow y BigQuery

## Validación manual

1. Abrir el servicio indicado en la consola del proyecto configurado.
2. Filtrar recursos por `PREFIX` y revisar la región configurada.
3. Confirmar: El mismo event_id existe en Bronze y Silver; Gold se materializa.

## Validación por CLI — solo lectura

Ejecutar desde la raíz del repositorio. Estos comandos no crean, actualizan ni eliminan recursos:

```bash
source automatizacion/scripts/common.sh
gcloud pubsub subscriptions describe "$RAW_BQ_SUB" --project="$PROJECT_ID" --format='yaml(topic,bigqueryConfig)'
bq --project_id="$PROJECT_ID" show "$PROJECT_ID:$BRONZE_DATASET.eventos_raw_pubsub"
bq --project_id="$PROJECT_ID" show "$PROJECT_ID:$SILVER_DATASET.pedidos"
bq --project_id="$PROJECT_ID" show "$PROJECT_ID:$GOLD_DATASET.cu03_kpis_operativos"
```

## Validación automática existente

Ejecutar únicamente los verificadores del grupo; no se relanzan scripts de aprovisionamiento:

```bash
bash automatizacion/scripts/09_verificar_silver_y_bronze.sh
bash automatizacion/scripts/12_ver_estado.sh
bash automatizacion/scripts/13_generar_evidencia.sh
```

Un verificador debe finalizar con `SCRIPT nn: 1` o la evidencia equivalente. Si devuelve `0`, conservar su salida y resolver la dependencia antes de reintentar.

## Cierre operativo

Cancelar el job Dataflow y confirmar CANCELLED.
