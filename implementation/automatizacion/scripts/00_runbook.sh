#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
source "$ROOT/automatizacion/scripts/common.sh"
heading 'Runbook — ejecución controlada de scripts pendientes'
RUN_STATE="$ROOT/state/$DEMO_RUN_ID/runbook.json"
mkdir -p "$(dirname "$RUN_STATE")"
if [[ ! -f "$RUN_STATE" ]]; then printf '{"status":"STARTED","results":[]}\n' > "$RUN_STATE"; fi

python3 - "$ROOT/automatizacion/configuracion/runbook.json" "$ROOT/automatizacion/scripts" <<'PY'
import json, pathlib, sys
manifest=json.load(open(sys.argv[1], encoding='utf-8')); scripts=pathlib.Path(sys.argv[2])
for group in manifest['groups']:
    print(f"GRUPO {group['name']}")
    for stem in group['scripts']:
        path=scripts/f'{stem}.sh'
        if not path.is_file():
            print(f'SCRIPT {stem}: 0')
            print(f'Dependencia faltante: {path.name}.')
            raise SystemExit(1)
        print(f'SCRIPT {stem.split("_", 1)[0]}: disponible ({path.name})')
print('RUNBOOK: 1 — todos los scripts 00–83 están disponibles. No se inició ninguna operación en GCP.')
PY
