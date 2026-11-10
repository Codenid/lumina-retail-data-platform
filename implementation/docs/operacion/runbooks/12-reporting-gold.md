# Reporting Gold

**Grupo:** `reporting`  
**Consola GCP:** BigQuery

## Validación manual

1. Abrir el servicio indicado en la consola del proyecto configurado.
2. Filtrar recursos por `PREFIX` y revisar la región configurada.
3. Confirmar: Cuatro vistas Gold existen y devuelven datos.

## Validación por CLI — solo lectura

Ejecutar desde la raíz del repositorio. Estos comandos no crean, actualizan ni eliminan recursos:

```bash
source automatizacion/scripts/common.sh
for view in vw_insights_streaming vw_riesgo_quiebre_despacho vw_plan_reposicion vw_kpis_operativos; do
  bq --project_id="$PROJECT_ID" show "$PROJECT_ID:$GOLD_DATASET.$view" | head -n 12
done
```

## Validación automática existente

Ejecutar únicamente los verificadores del grupo; no se relanzan scripts de aprovisionamiento:

```bash
# No hay verificador dedicado; usar la validación CLI anterior.
```

Un verificador debe finalizar con `SCRIPT nn: 1` o la evidencia equivalente. Si devuelve `0`, conservar su salida y resolver la dependencia antes de reintentar.

## Cierre operativo

Consumidor BI externo permanece fuera de alcance.
