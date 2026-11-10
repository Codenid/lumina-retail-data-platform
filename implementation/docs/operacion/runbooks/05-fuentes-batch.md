# Fuentes batch adicionales

**Grupo:** `nuevas_fuentes_batch`  
**Consola GCP:** Cloud Storage y BigQuery

## Validación manual

1. Abrir el servicio indicado en la consola del proyecto configurado.
2. Filtrar recursos por `PREFIX` y revisar la región configurada.
3. Confirmar: Tres dominios adicionales aparecen en Bronze y Silver.

## Validación por CLI — solo lectura

Ejecutar desde la raíz del repositorio. Estos comandos no crean, actualizan ni eliminan recursos:

```bash
source automatizacion/scripts/common.sh
gcloud storage ls "gs://$LANDING/batch/" 2>/dev/null || true
for table in competidores eventos_locales redes_sociales; do bq --project_id="$PROJECT_ID" show "$PROJECT_ID:$SILVER_DATASET.$table"; done
```

## Validación automática existente

Ejecutar únicamente los verificadores del grupo; no se relanzan scripts de aprovisionamiento:

```bash
bash automatizacion/scripts/35_verificar_batch_nuevos.sh
```

Un verificador debe finalizar con `SCRIPT nn: 1` o la evidencia equivalente. Si devuelve `0`, conservar su salida y resolver la dependencia antes de reintentar.

## Cierre operativo

No deja cómputo activo.
