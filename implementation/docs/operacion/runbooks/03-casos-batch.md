# Casos de uso batch

**Grupo:** `batch_casos_uso`  
**Consola GCP:** BigQuery

## Validación manual

1. Abrir el servicio indicado en la consola del proyecto configurado.
2. Filtrar recursos por `PREFIX` y revisar la región configurada.
3. Confirmar: CU01 a CU04 y Operational Mart contienen el scenario_id de prueba.

## Validación por CLI — solo lectura

Ejecutar desde la raíz del repositorio. Estos comandos no crean, actualizan ni eliminan recursos:

```bash
source automatizacion/scripts/common.sh
for table in cu01_riesgo_quiebre_despacho cu02_plan_reposicion cu03_kpis_operativos cu04_alertas_mantenimiento operational_mart; do
  bq --project_id="$PROJECT_ID" show "$PROJECT_ID:$GOLD_DATASET.$table" | head -n 12
done
```

## Validación automática existente

Ejecutar únicamente los verificadores del grupo; no se relanzan scripts de aprovisionamiento:

```bash
bash automatizacion/scripts/19_verificar_casos_uso.sh
```

Un verificador debe finalizar con `SCRIPT nn: 1` o la evidencia equivalente. Si devuelve `0`, conservar su salida y resolver la dependencia antes de reintentar.

## Cierre operativo

No deja cómputo activo.
