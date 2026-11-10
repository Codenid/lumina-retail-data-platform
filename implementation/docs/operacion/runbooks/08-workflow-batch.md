# Workflow batch completo

**Grupo:** `workflow_batch_completo`  
**Consola GCP:** Workflows y BigQuery

## Validación manual

1. Abrir el servicio indicado en la consola del proyecto configurado.
2. Filtrar recursos por `PREFIX` y revisar la región configurada.
3. Confirmar: Workflow SUCCEEDED y Operational Mart contiene el run_id.

## Validación por CLI — solo lectura

Ejecutar desde la raíz del repositorio. Estos comandos no crean, actualizan ni eliminan recursos:

```bash
source automatizacion/scripts/common.sh
gcloud workflows executions list "${PREFIX}-batch" --project="$PROJECT_ID" --location="$REGION" --limit=10 --format='table(name,state,startTime,endTime)'
bq --project_id="$PROJECT_ID" show "$PROJECT_ID:$GOLD_DATASET.operational_mart"
```

## Validación automática existente

Ejecutar únicamente los verificadores del grupo; no se relanzan scripts de aprovisionamiento:

```bash
bash automatizacion/scripts/52_verificar_workflow_batch_completo.sh
bash automatizacion/scripts/53_generar_evidencia_workflow_batch.sh
```

Un verificador debe finalizar con `SCRIPT nn: 1` o la evidencia equivalente. Si devuelve `0`, conservar su salida y resolver la dependencia antes de reintentar.

## Cierre operativo

No deja cómputo activo.
