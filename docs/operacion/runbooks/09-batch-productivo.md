# Batch de seis fuentes

**Grupo:** `batch_productivo`  
**Consola GCP:** Cloud Storage y BigQuery

## Validación manual

1. Abrir el servicio indicado en la consola del proyecto configurado.
2. Filtrar recursos por `PREFIX` y revisar la región configurada.
3. Confirmar: Las seis fuentes tienen filas en Bronze, Silver, Gold y Mart.

## Validación por CLI — solo lectura

Ejecutar desde la raíz del repositorio. Estos comandos no crean, actualizan ni eliminan recursos:

```bash
source automatizacion/scripts/common.sh
gcloud storage ls "gs://$BRONZE/batch/" 2>/dev/null | tail -n 20
bq --project_id="$PROJECT_ID" show "$PROJECT_ID:$GOLD_DATASET.operational_mart"
```

## Validación automática existente

Ejecutar únicamente los verificadores del grupo; no se relanzan scripts de aprovisionamiento:

```bash
bash automatizacion/scripts/58_verificar_batch_productivo.sh
```

Un verificador debe finalizar con `SCRIPT nn: 1` o la evidencia equivalente. Si devuelve `0`, conservar su salida y resolver la dependencia antes de reintentar.

## Cierre operativo

No deja cómputo activo.
