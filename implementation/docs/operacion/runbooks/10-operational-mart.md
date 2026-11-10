# Operational Mart

**Grupo:** `operational_mart`  
**Consola GCP:** BigQuery Data Transfer

## Validación manual

1. Abrir el servicio indicado en la consola del proyecto configurado.
2. Filtrar recursos por `PREFIX` y revisar la región configurada.
3. Confirmar: Scheduled query y última ejecución están en estado correcto.

## Validación por CLI — solo lectura

Ejecutar desde la raíz del repositorio. Estos comandos no crean, actualizan ni eliminan recursos:

```bash
source automatizacion/scripts/common.sh
bq --project_id="$PROJECT_ID" ls --transfer_config --transfer_location="$REGION" --format=prettyjson
bq --project_id="$PROJECT_ID" show "$PROJECT_ID:$GOLD_DATASET.operational_mart"
```

## Validación automática existente

Ejecutar únicamente los verificadores del grupo; no se relanzan scripts de aprovisionamiento:

```bash
bash automatizacion/scripts/62_verificar_operational_mart.sh
```

Un verificador debe finalizar con `SCRIPT nn: 1` o la evidencia equivalente. Si devuelve `0`, conservar su salida y resolver la dependencia antes de reintentar.

## Cierre operativo

Revisar periodicidad y costo de la scheduled query.
