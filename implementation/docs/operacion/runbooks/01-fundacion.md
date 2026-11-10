# Fundación de plataforma

**Grupo:** `fundacion`  
**Consola GCP:** APIs, IAM, Cloud Storage, BigQuery y Pub/Sub

## Validación manual

1. Abrir el servicio indicado en la consola del proyecto configurado.
2. Filtrar recursos por `PREFIX` y revisar la región configurada.
3. Confirmar: Buckets, datasets, worker y tópicos con el prefijo configurado.

## Validación por CLI — solo lectura

Ejecutar desde la raíz del repositorio. Estos comandos no crean, actualizan ni eliminan recursos:

```bash
source automatizacion/scripts/common.sh
gcloud storage buckets list --project="$PROJECT_ID" --format='table(name,location,uniformBucketLevelAccess.enabled)' | grep "$PREFIX"
for ds in "$BRONZE_DATASET" "$SILVER_DATASET" "$GOLD_DATASET"; do bq --project_id="$PROJECT_ID" show "$PROJECT_ID:$ds" | head -n 12; done
gcloud pubsub topics list --project="$PROJECT_ID" --format='value(name)' | grep "$PREFIX"
```

## Validación automática existente

Ejecutar únicamente los verificadores del grupo; no se relanzan scripts de aprovisionamiento:

```bash
# No hay verificador dedicado; usar la validación CLI anterior.
```

Un verificador debe finalizar con `SCRIPT nn: 1` o la evidencia equivalente. Si devuelve `0`, conservar su salida y resolver la dependencia antes de reintentar.

## Cierre operativo

No inicia cómputo.
