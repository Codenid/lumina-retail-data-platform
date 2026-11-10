#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
[[ -f "$ROOT/config.env" ]] || { echo 'Copia config.env.example a config.env y edita PROJECT_ID.'; exit 1; }
set -a
source "$ROOT/config.env"
set +a
[[ "$PROJECT_ID" != CAMBIA_POR_TU_PROYECTO && "$PROJECT_ID" =~ ^[a-z][a-z0-9-]{4,28}[a-z0-9]$ ]] || { echo 'PROJECT_ID inválido'; exit 1; }
[[ "$PREFIX" =~ ^[a-z][a-z0-9-]{1,12}[a-z0-9]$ ]] || { echo 'PREFIX: 3–14 caracteres minúsculos.'; exit 1; }
[[ "$DEMO_RUN_ID" =~ ^[a-z0-9][a-z0-9-]{0,24}$ ]] || { echo 'DEMO_RUN_ID inválido'; exit 1; }
[[ "$REGION" =~ ^[a-z]+-[a-z]+[0-9]$ ]] || { echo 'REGION inválida'; exit 1; }
command -v gcloud >/dev/null
command -v python3 >/dev/null
export CLOUDSDK_CORE_PROJECT="$PROJECT_ID"
export LANDING="${PROJECT_ID}-${PREFIX}-landing"
export BRONZE="${PROJECT_ID}-${PREFIX}-bronze"
export SILVER="${PROJECT_ID}-${PREFIX}-silver"
export ARTIFACTS="${PROJECT_ID}-${PREFIX}-artifacts"
export MODELS="${PROJECT_ID}-${PREFIX}-models"
export TOPIC="${PREFIX}-eventos-retail"
export INSIGHTS_TOPIC="${PREFIX}-insights-retail"
export AUDIT_TOPIC="${PREFIX}-auditoria"
export DF_SUB="${PREFIX}-dataflow"
export RAW_SUB="${PREFIX}-bronze"
export RAW_BQ_SUB="${PREFIX}-bronze-bq"
export WORKER="${PREFIX}-worker@${PROJECT_ID}.iam.gserviceaccount.com"
export BRONZE_DATASET="${PREFIX//-/_}_bronze"
export SILVER_DATASET="${PREFIX//-/_}_silver"
export GOLD_DATASET="${PREFIX//-/_}_gold"
export DATASET="$GOLD_DATASET"
export TABLE="eventos_${DEMO_RUN_ID//-/_}"
export JOB_NAME="${PREFIX}-silver-${DEMO_RUN_ID}"
mkdir -p "$ROOT/state/$DEMO_RUN_ID"
ensure() { python3 "$ROOT/automatizacion/utilidades/ensure.py" "$@"; }
heading() { echo; echo "== $* =="; }
contract_value() {
  python3 - "$1" "$2" <<'PY'
import json, os, sys
value=json.load(open(sys.argv[1], encoding='utf-8'))
for key in sys.argv[2].split('.'):
    value=value[key]
if not isinstance(value, str):
    raise SystemExit(f'El valor de contrato {sys.argv[2]!r} debe ser texto')
for key in ('PROJECT_ID', 'PREFIX', 'REGION'):
    value=value.replace('{{'+key+'}}', os.environ[key])
print(value)
PY
}
render_template() {
  python3 - "$1" "$2" <<'PY'
import os, pathlib, sys
source, target=map(pathlib.Path, sys.argv[1:])
text=source.read_text(encoding='utf-8')
for key in ('PROJECT_ID', 'PREFIX', 'REGION'):
    text=text.replace('{{'+key+'}}', os.environ[key])
target.write_text(text, encoding='utf-8')
PY
}
