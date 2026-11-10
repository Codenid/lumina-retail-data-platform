# Integración batch

**Grupo:** `integracion_batch`  
**Consola GCP:** Workflows, Storage Transfer y Dataproc

## Validación manual

1. Abrir el servicio indicado en la consola del proyecto configurado.
2. Filtrar recursos por `PREFIX` y revisar la región configurada.
3. Confirmar: Transferencia, ejecución Workflow y salida batch verificadas.

## Validación por CLI — solo lectura

Ejecutar desde la raíz del repositorio. Estos comandos no crean, actualizan ni eliminan recursos:

```bash
source automatizacion/scripts/common.sh
gcloud workflows list --project="$PROJECT_ID" --location="$REGION" --format='table(name,state,updateTime)'
gcloud transfer jobs list --project="$PROJECT_ID" --format='table(name,status,description)'
gcloud dataproc clusters list --project="$PROJECT_ID" --region="$REGION" --format='table(clusterName,status.state,status.stateStartTime)
```

## Validación automática existente

Ejecutar únicamente los verificadores del grupo; no se relanzan scripts de aprovisionamiento:

```bash
bash automatizacion/scripts/27_verificar_batch_orquestado.sh
bash automatizacion/scripts/28_generar_evidencia_batch.sh
```

Un verificador debe finalizar con `SCRIPT nn: 1` o la evidencia equivalente. Si devuelve `0`, conservar su salida y resolver la dependencia antes de reintentar.

## Cierre operativo

Dataproc debe respetar autoeliminación; usar 90 solo si se decide retirar cómputo.
