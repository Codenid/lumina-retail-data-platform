#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
heading 'Paso 30 — crear y verificar contratos batch faltantes'
CONTRACT="$ROOT/automatizacion/configuracion/contratos/batch_sources.json"
[[ -s "$CONTRACT" ]] || { echo "Falta contrato: $CONTRACT"; exit 1; }
python3 -c 'import csv,json,sys; c=json.load(open(sys.argv[1])); p={r["producer"] for r in csv.DictReader(open(sys.argv[2],newline="")) if r["mode"]=="batch"}; e={"benchmark_competidores","eventos_locales","redes_sociales"}; d=c.get("domains",{}); assert set(d)==e, "Contratos faltantes o inesperados"; assert all(x.get("key") and x.get("fields") and x.get("bronze_table") and x.get("silver_table") for x in d.values()), "Contrato incompleto"; assert all(d[n]["producer"] in p for n in d), "Productor faltante"; print("Contratos y productores batch verificados")' "$CONTRACT" "$ROOT/docs/arquitectura/productores.csv"
printf 'Contratos batch verificados\n' > "$ROOT/state/$DEMO_RUN_ID/contracts_batch_ok.txt"
echo 'SCRIPT 30: 1 — contratos batch creados/verificados'
