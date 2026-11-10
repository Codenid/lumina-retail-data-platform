#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
heading 'OPCIONAL — archivo batch mínimo en Landing y Bronze'
[[ -s "$ROOT/state/$DEMO_RUN_ID/evento.json" ]] || { echo 'Ejecuta 08 primero.'; exit 1; }
# Esta copia manual demuestra las capas; no se presenta como Storage Transfer Service.
gcloud storage cp "$ROOT/state/$DEMO_RUN_ID/evento.json" "gs://$LANDING/batch/$DEMO_RUN_ID/evento.json"
gcloud storage cp "gs://$LANDING/batch/$DEMO_RUN_ID/evento.json" "gs://$BRONZE/batch/$DEMO_RUN_ID/evento.json"
echo 'Ahora puedes ejecutar 23. Esta prueba NO implementa RS-013 ni la orquestación batch.'
