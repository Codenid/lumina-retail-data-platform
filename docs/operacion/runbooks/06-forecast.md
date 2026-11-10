# Forecast y planificación

**Grupo:** `forecast`  
**Consola GCP:** BigQuery y Cloud Storage

## Validación manual

1. Abrir el servicio indicado en la consola del proyecto configurado.
2. Filtrar recursos por `PREFIX` y revisar la región configurada.
3. Confirmar: Features, predicción, plan CU02 y artefacto de modelo existen.

## Validación por CLI — solo lectura

Ejecutar desde la raíz del repositorio. Estos comandos no crean, actualizan ni eliminan recursos:

```bash
source automatizacion/scripts/common.sh
gcloud storage ls "gs://$MODELS/forecast/" 2>/dev/null || true
bq --project_id="$PROJECT_ID" show "$PROJECT_ID:$GOLD_DATASET.forecast_predictions"
bq --project_id="$PROJECT_ID" show "$PROJECT_ID:$GOLD_DATASET.cu02_plan_reposicion"
```

## Validación automática existente

Ejecutar únicamente los verificadores del grupo; no se relanzan scripts de aprovisionamiento:

```bash
bash automatizacion/scripts/42_verificar_forecast_evidencia.sh
```

Un verificador debe finalizar con `SCRIPT nn: 1` o la evidencia equivalente. Si devuelve `0`, conservar su salida y resolver la dependencia antes de reintentar.

## Cierre operativo

Conservar el artefacto de modelo para trazabilidad.
