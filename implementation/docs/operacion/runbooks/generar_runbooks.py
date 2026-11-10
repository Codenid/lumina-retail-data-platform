#!/usr/bin/env python3
"""Genera runbooks de validación manual y automática por grupo funcional."""
import json
from pathlib import Path

RUNBOOKS = [
 ("00-preflight.md","Preflight de acceso","preflight","IAM y Billing","Proyecto activo, facturación y red configurada.","No crea recursos."),
 ("01-fundacion.md","Fundación de plataforma","fundacion","APIs, IAM, Cloud Storage, BigQuery y Pub/Sub","Buckets, datasets, worker y tópicos con el prefijo configurado.","No inicia cómputo."),
 ("02-streaming-base.md","Streaming base","streaming_base","Pub/Sub, Dataflow y BigQuery","El mismo event_id existe en Bronze y Silver; Gold se materializa.","Cancelar el job Dataflow y confirmar CANCELLED."),
 ("03-casos-batch.md","Casos de uso batch","batch_casos_uso","BigQuery","CU01 a CU04 y Operational Mart contienen el scenario_id de prueba.","No deja cómputo activo."),
 ("04-integracion-batch.md","Integración batch","integracion_batch","Workflows, Storage Transfer y Dataproc","Transferencia, ejecución Workflow y salida batch verificadas.","Dataproc debe respetar autoeliminación; usar 90 solo si se decide retirar cómputo."),
 ("05-fuentes-batch.md","Fuentes batch adicionales","nuevas_fuentes_batch","Cloud Storage y BigQuery","Tres dominios adicionales aparecen en Bronze y Silver.","No deja cómputo activo."),
 ("06-forecast.md","Forecast y planificación","forecast","BigQuery y Cloud Storage","Features, predicción, plan CU02 y artefacto de modelo existen.","Conservar el artefacto de modelo para trazabilidad."),
 ("07-insights-streaming.md","Insights streaming","streaming_insights","Pub/Sub, Dataflow y BigQuery","El event_id de Insights aparece en Gold y auditoría.","Cancelar el job Dataflow y confirmar CANCELLED."),
 ("08-workflow-batch.md","Workflow batch completo","workflow_batch_completo","Workflows y BigQuery","Workflow SUCCEEDED y Operational Mart contiene el run_id.","No deja cómputo activo."),
 ("09-batch-productivo.md","Batch de seis fuentes","batch_productivo","Cloud Storage y BigQuery","Las seis fuentes tienen filas en Bronze, Silver, Gold y Mart.","No deja cómputo activo."),
 ("10-operational-mart.md","Operational Mart","operational_mart","BigQuery Data Transfer","Scheduled query y última ejecución están en estado correcto.","Revisar periodicidad y costo de la scheduled query."),
 ("11-api-cloud-run.md","API Cloud Run","api_cloud_run","Cloud Run, IAM y BigQuery","Servicio privado READY y cuatro rutas autenticadas devuelven datos.","No habilitar acceso anónimo."),
 ("12-reporting-gold.md","Reporting Gold","reporting","BigQuery","Cuatro vistas Gold existen y devuelven datos.","Consumidor BI externo permanece fuera de alcance."),
 ("13-gobierno.md","Gobierno y catálogo","gobierno","[Knowledge Catalog](https://console.cloud.google.com/dataplex/studio?referrer=search&authuser=0&project=prj-codenid) y Data Lineage","Activos catalogados, metadatos y vínculos Gold→vista visibles.","No elimina metadatos ni linaje existente."),
 ("14-seguridad.md","Seguridad","seguridad","IAM, KMS, Secret Manager y DLP","Clave regional, secreto CMEK, IAM por recurso y plantilla DLP verificados.","No exponer valores de secretos ni resultados con PII."),
 ("15-auditoria-observabilidad.md","Auditoría y observabilidad","auditoria_observabilidad","Logging, BigQuery y Monitoring","Sink, Audit Store, métrica, alerta y SLO existen; evento sintético llega al store.","Revisar retención y presupuesto de logs."),
]

root = Path(__file__).resolve().parent
repo = root.parents[2]
groups = {group["name"]: group["scripts"] for group in json.loads((repo / "automatizacion/configuracion/runbook.json").read_text(encoding="utf-8"))["groups"]}

# Consultas de diagnóstico de solo lectura. No invocan el aprovisionamiento.
CLI_DEFAULT = '''source automatizacion/scripts/common.sh
gcloud projects describe "$PROJECT_ID" --format='table(projectId,projectNumber,lifecycleState)'
gcloud asset search-all-resources --scope="projects/$PROJECT_ID" --query="$PREFIX" --format='table(assetType,displayName,location)'''

CLI_CHECKS = {
    "fundacion": '''source automatizacion/scripts/common.sh
gcloud storage buckets list --project="$PROJECT_ID" --format='table(name,location,uniformBucketLevelAccess.enabled)' | grep "$PREFIX"
for ds in "$BRONZE_DATASET" "$SILVER_DATASET" "$GOLD_DATASET"; do bq --project_id="$PROJECT_ID" show "$PROJECT_ID:$ds" | head -n 12; done
gcloud pubsub topics list --project="$PROJECT_ID" --format='value(name)' | grep "$PREFIX"''',
    "streaming_base": '''source automatizacion/scripts/common.sh
gcloud pubsub subscriptions describe "$RAW_BQ_SUB" --project="$PROJECT_ID" --format='yaml(topic,bigqueryConfig)'
bq --project_id="$PROJECT_ID" show "$PROJECT_ID:$BRONZE_DATASET.eventos_raw_pubsub"
bq --project_id="$PROJECT_ID" show "$PROJECT_ID:$SILVER_DATASET.pedidos"
bq --project_id="$PROJECT_ID" show "$PROJECT_ID:$GOLD_DATASET.cu03_kpis_operativos"''',
    "batch_casos_uso": '''source automatizacion/scripts/common.sh
for table in cu01_riesgo_quiebre_despacho cu02_plan_reposicion cu03_kpis_operativos cu04_alertas_mantenimiento operational_mart; do
  bq --project_id="$PROJECT_ID" show "$PROJECT_ID:$GOLD_DATASET.$table" | head -n 12
done''',
    "integracion_batch": '''source automatizacion/scripts/common.sh
gcloud workflows list --project="$PROJECT_ID" --location="$REGION" --format='table(name,state,updateTime)'
gcloud transfer jobs list --project="$PROJECT_ID" --format='table(name,status,description)'
gcloud dataproc clusters list --project="$PROJECT_ID" --region="$REGION" --format='table(clusterName,status.state,status.stateStartTime)''',
    "nuevas_fuentes_batch": '''source automatizacion/scripts/common.sh
gcloud storage ls "gs://$LANDING/batch/" 2>/dev/null || true
for table in competidores eventos_locales redes_sociales; do bq --project_id="$PROJECT_ID" show "$PROJECT_ID:$SILVER_DATASET.$table"; done''',
    "forecast": '''source automatizacion/scripts/common.sh
gcloud storage ls "gs://$MODELS/forecast/" 2>/dev/null || true
bq --project_id="$PROJECT_ID" show "$PROJECT_ID:$GOLD_DATASET.forecast_predictions"
bq --project_id="$PROJECT_ID" show "$PROJECT_ID:$GOLD_DATASET.cu02_plan_reposicion"''',
    "streaming_insights": '''source automatizacion/scripts/common.sh
gcloud pubsub subscriptions describe "${PREFIX}-insights-dataflow" --project="$PROJECT_ID" --format='yaml(topic,ackDeadlineSeconds)'
bq --project_id="$PROJECT_ID" show "$PROJECT_ID:$GOLD_DATASET.insights_streaming"
bq --project_id="$PROJECT_ID" show "$PROJECT_ID:$GOLD_DATASET.procesamiento_auditoria"''',
    "workflow_batch_completo": '''source automatizacion/scripts/common.sh
gcloud workflows executions list "${PREFIX}-batch" --project="$PROJECT_ID" --location="$REGION" --limit=10 --format='table(name,state,startTime,endTime)'
bq --project_id="$PROJECT_ID" show "$PROJECT_ID:$GOLD_DATASET.operational_mart"''',
    "batch_productivo": '''source automatizacion/scripts/common.sh
gcloud storage ls "gs://$BRONZE/batch/" 2>/dev/null | tail -n 20
bq --project_id="$PROJECT_ID" show "$PROJECT_ID:$GOLD_DATASET.operational_mart"''',
    "operational_mart": '''source automatizacion/scripts/common.sh
bq --project_id="$PROJECT_ID" ls --transfer_config --transfer_location="$REGION" --format=prettyjson
bq --project_id="$PROJECT_ID" show "$PROJECT_ID:$GOLD_DATASET.operational_mart"''',
    "reporting": '''source automatizacion/scripts/common.sh
for view in vw_insights_streaming vw_riesgo_quiebre_despacho vw_plan_reposicion vw_kpis_operativos; do
  bq --project_id="$PROJECT_ID" show "$PROJECT_ID:$GOLD_DATASET.$view" | head -n 12
done''',
    "gobierno": '''source automatizacion/scripts/common.sh
gcloud services list --enabled --project="$PROJECT_ID" --filter='config.name:(datalineage.googleapis.com OR dataplex.googleapis.com)' --format='table(config.name,state)'
''',
    "seguridad": '''source automatizacion/scripts/common.sh
gcloud kms keyrings list --project="$PROJECT_ID" --location="$REGION"
gcloud secrets list --project="$PROJECT_ID" --format='table(name,createTime)'
gcloud dlp inspect-templates list --project="$PROJECT_ID" --location="$REGION" --format='table(name,displayName)''',
    "auditoria_observabilidad": '''source automatizacion/scripts/common.sh
gcloud logging sinks list --project="$PROJECT_ID" --format='table(name,destination)'
gcloud logging metrics list --project="$PROJECT_ID" --format='table(name,description)'
gcloud monitoring policies list --project="$PROJECT_ID" --format='table(displayName,enabled)'
bq --project_id="$PROJECT_ID" ls | grep -i audit || true''',
    "api_cloud_run": '''source automatizacion/scripts/common.sh
SERVICE="${PREFIX}-insights-api"
URL="$(gcloud run services describe "$SERVICE" --project="$PROJECT_ID" --region="$REGION" --format='value(status.url)')"
TOKEN="$(gcloud auth print-identity-token)"

gcloud run services describe "$SERVICE" --project="$PROJECT_ID" --region="$REGION" --format='yaml(status.url,status.conditions,spec.template.spec.serviceAccountName)'
for path in \\
  '/api/v1/insights?limit=5' \\
  '/api/v1/kpis?limit=5' \\
  '/api/v1/inventory-plans?limit=5' \\
  '/api/v1/maintenance-risks?limit=5'; do
  curl -i -H "Authorization: Bearer $TOKEN" "$URL$path"
done''',
}

def validation_scripts(group):
    """Solo verificadores; nunca scripts que crean o despliegan recursos."""
    terms = ("verificar", "evidencia", "ver_estado")
    return [stem for stem in groups[group] if any(term in stem for term in terms)]
for filename, title, group, console, expected, closure in RUNBOOKS:
    commands = "\n".join(f"bash automatizacion/scripts/{stem}.sh" for stem in validation_scripts(group)) or "# No hay verificador dedicado; usar la validación CLI anterior."
    cli = CLI_CHECKS.get(group, CLI_DEFAULT)
    (root / filename).write_text(f'''# {title}\n\n**Grupo:** `{group}`  \n**Consola GCP:** {console}\n\n## Validación manual\n\n1. Abrir el servicio indicado en la consola del proyecto configurado.\n2. Filtrar recursos por `PREFIX` y revisar la región configurada.\n3. Confirmar: {expected}\n\n## Validación por CLI — solo lectura\n\nEjecutar desde la raíz del repositorio. Estos comandos no crean, actualizan ni eliminan recursos:\n\n```bash\n{cli}\n```\n\n## Validación automática existente\n\nEjecutar únicamente los verificadores del grupo; no se relanzan scripts de aprovisionamiento:\n\n```bash\n{commands}\n```\n\nUn verificador debe finalizar con `SCRIPT nn: 1` o la evidencia equivalente. Si devuelve `0`, conservar su salida y resolver la dependencia antes de reintentar.\n\n## Cierre operativo\n\n{closure}\n''', encoding='utf-8')
    print(root / filename)
