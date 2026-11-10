# Preflight de acceso

**Grupo:** `preflight`  
**Consola GCP:** IAM y Billing

## Validación manual

1. Abrir el servicio indicado en la consola del proyecto configurado.
2. Filtrar recursos por `PREFIX` y revisar la región configurada.
3. Confirmar: Proyecto activo, facturación y red configurada.

## Validación por CLI — solo lectura

Ejecutar desde la raíz del repositorio. Estos comandos no crean, actualizan ni eliminan recursos:

```bash
source automatizacion/scripts/common.sh
gcloud projects describe "$PROJECT_ID" --format='table(projectId,projectNumber,lifecycleState)'
gcloud asset search-all-resources --scope="projects/$PROJECT_ID" --query="$PREFIX" --format='table(assetType,displayName,location)
```

## Validación automática existente

Ejecutar únicamente los verificadores del grupo; no se relanzan scripts de aprovisionamiento:

```bash
bash automatizacion/scripts/00_verificar_acceso.sh
```

Un verificador debe finalizar con `SCRIPT nn: 1` o la evidencia equivalente. Si devuelve `0`, conservar su salida y resolver la dependencia antes de reintentar.

## Cierre operativo

No crea recursos.
