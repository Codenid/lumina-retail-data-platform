# API Cloud Run

**Grupo:** `api_cloud_run`  
**Consola GCP:** Cloud Run, IAM y BigQuery

## Validación manual

1. Abrir el servicio indicado en la consola del proyecto configurado.
2. Filtrar recursos por `PREFIX` y revisar la región configurada.
3. Confirmar: Servicio privado READY y cuatro rutas autenticadas devuelven datos.

## Validación por CLI — solo lectura

Ejecutar desde la raíz del repositorio. Estos comandos no crean, actualizan ni eliminan recursos:

```bash
source automatizacion/scripts/common.sh
SERVICE="${PREFIX}-insights-api"
URL="$(gcloud run services describe "$SERVICE" --project="$PROJECT_ID" --region="$REGION" --format='value(status.url)')"
TOKEN="$(gcloud auth print-identity-token)"

gcloud run services describe "$SERVICE" --project="$PROJECT_ID" --region="$REGION" --format='yaml(status.url,status.conditions,spec.template.spec.serviceAccountName)'
for path in \
  '/api/v1/insights?limit=5' \
  '/api/v1/kpis?limit=5' \
  '/api/v1/inventory-plans?limit=5' \
  '/api/v1/maintenance-risks?limit=5'; do
  curl -i -H "Authorization: Bearer $TOKEN" "$URL$path"
done
```

## Validación automática existente

Ejecutar únicamente los verificadores del grupo; no se relanzan scripts de aprovisionamiento:

```bash
bash automatizacion/scripts/66_verificar_api_retailsmart.sh
bash automatizacion/scripts/67_evidencia_api_retailsmart.sh
```

Un verificador debe finalizar con `SCRIPT nn: 1` o la evidencia equivalente. Si devuelve `0`, conservar su salida y resolver la dependencia antes de reintentar.

## Cierre operativo

No habilitar acceso anónimo.
