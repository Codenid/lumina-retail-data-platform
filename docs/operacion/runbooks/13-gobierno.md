# Gobierno y catálogo

**Grupo:** `gobierno`  
**Consola GCP:** Dataplex y Data Lineage

## Validación manual

1. Abrir el servicio indicado en la consola del proyecto configurado.
2. Filtrar recursos por `PREFIX` y revisar la región configurada.
3. Confirmar: Activos catalogados, metadatos y vínculos Gold→vista visibles.

## Validación por CLI — solo lectura

Ejecutar desde la raíz del repositorio. Estos comandos no crean, actualizan ni eliminan recursos:

```bash
source automatizacion/scripts/common.sh
gcloud services list --enabled --project="$PROJECT_ID" --filter='config.name:(datalineage.googleapis.com OR dataplex.googleapis.com)' --format='table(config.name,state)'
gcloud dataplex datascans list --project="$PROJECT_ID" --location="$REGION" --format='table(name,state)' 2>/dev/null || true
```

## Validación automática existente

Ejecutar únicamente los verificadores del grupo; no se relanzan scripts de aprovisionamiento:

```bash
bash automatizacion/scripts/73_verificar_linaje_y_evidencia.sh
```

Un verificador debe finalizar con `SCRIPT nn: 1` o la evidencia equivalente. Si devuelve `0`, conservar su salida y resolver la dependencia antes de reintentar.

## Cierre operativo

No elimina metadatos ni linaje existente.
