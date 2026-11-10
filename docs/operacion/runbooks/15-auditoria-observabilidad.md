# Auditoría y observabilidad

**Grupo:** `auditoria_observabilidad`  
**Consola GCP:** Logging, BigQuery y Monitoring

## Validación manual

1. Abrir el servicio indicado en la consola del proyecto configurado.
2. Filtrar recursos por `PREFIX` y revisar la región configurada.
3. Confirmar: Sink, Audit Store, métrica, alerta y SLO existen; evento sintético llega al store.

## Validación por CLI — solo lectura

Ejecutar desde la raíz del repositorio. Estos comandos no crean, actualizan ni eliminan recursos:

```bash
source automatizacion/scripts/common.sh
gcloud logging sinks list --project="$PROJECT_ID" --format='table(name,destination)'
gcloud logging metrics list --project="$PROJECT_ID" --format='table(name,description)'
gcloud monitoring policies list --project="$PROJECT_ID" --format='table(displayName,enabled)'
bq --project_id="$PROJECT_ID" ls | grep -i audit || true
```

## Validación automática existente

Ejecutar únicamente los verificadores del grupo; no se relanzan scripts de aprovisionamiento:

```bash
bash automatizacion/scripts/83_verificar_observabilidad_evidencia.sh
```

Un verificador debe finalizar con `SCRIPT nn: 1` o la evidencia equivalente. Si devuelve `0`, conservar su salida y resolver la dependencia antes de reintentar.

## Cierre operativo

Revisar retención y presupuesto de logs.
