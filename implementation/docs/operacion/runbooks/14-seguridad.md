# Seguridad

**Grupo:** `seguridad`  
**Consola GCP:** IAM, KMS, Secret Manager y DLP

## Validación manual

1. Abrir el servicio indicado en la consola del proyecto configurado.
2. Filtrar recursos por `PREFIX` y revisar la región configurada.
3. Confirmar: Clave regional, secreto CMEK, IAM por recurso y plantilla DLP verificados.

## Validación por CLI — solo lectura

Ejecutar desde la raíz del repositorio. Estos comandos no crean, actualizan ni eliminan recursos:

```bash
source automatizacion/scripts/common.sh
gcloud kms keyrings list --project="$PROJECT_ID" --location="$REGION"
gcloud secrets list --project="$PROJECT_ID" --format='table(name,createTime)'
gcloud dlp inspect-templates list --project="$PROJECT_ID" --location="$REGION" --format='table(name,displayName)
```

## Validación automática existente

Ejecutar únicamente los verificadores del grupo; no se relanzan scripts de aprovisionamiento:

```bash
bash automatizacion/scripts/78_verificar_seguridad_evidencia.sh
```

Un verificador debe finalizar con `SCRIPT nn: 1` o la evidencia equivalente. Si devuelve `0`, conservar su salida y resolver la dependencia antes de reintentar.

## Cierre operativo

No exponer valores de secretos ni resultados con PII.
