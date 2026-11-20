#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
heading 'Paso 88 — poblar dimensiones maestras'
[[ -s "$ROOT/state/$DEMO_RUN_ID/master_dimensions_created.txt" ]] || { echo 'SCRIPT 88: 0 — ejecuta SCRIPT 87'; exit 1; }
LOCATION="$(bq --project_id="$PROJECT_ID" show --format=json "$PROJECT_ID:$GOLD_DATASET" | python3 -c 'import json,sys; print(json.load(sys.stdin)["location"])')"
bq --project_id="$PROJECT_ID" --location="$LOCATION" query --use_legacy_sql=false --maximum_bytes_billed=104857600 "
DELETE FROM \`$PROJECT_ID.$GOLD_DATASET.dim_tiendas\` WHERE TRUE;
INSERT INTO \`$PROJECT_ID.$GOLD_DATASET.dim_tiendas\` SELECT FORMAT('STORE-%03d',n),FORMAT('Store %03d %s',n,zone),zone,city,FORMAT('REG-%02d',1+MOD(n-1,8)),'Supermercado','ACTIVE' FROM UNNEST(GENERATE_ARRAY(1,32)) n CROSS JOIN UNNEST([STRUCT('Lima Centro' AS zone,'Lima' AS city),STRUCT('San Miguel','Lima'),STRUCT('Surco','Lima'),STRUCT('Arequipa Norte','Arequipa'),STRUCT('Trujillo Centro','Trujillo'),STRUCT('Cusco Centro','Cusco'),STRUCT('Piura Norte','Piura'),STRUCT('Miraflores','Lima')]) z WITH OFFSET off WHERE MOD(n-1,8)=off;
DELETE FROM \`$PROJECT_ID.$GOLD_DATASET.dim_productos\` WHERE TRUE;
INSERT INTO \`$PROJECT_ID.$GOLD_DATASET.dim_productos\`
SELECT FORMAT('SKU-%05d',n),
  FORMAT('%s %s %05d',
    CASE MOD(n-1,12) WHEN 0 THEN 'Abarrotes' WHEN 1 THEN 'Bebidas' WHEN 2 THEN 'Lácteos' WHEN 3 THEN 'Limpieza' WHEN 4 THEN 'Cuidado personal' WHEN 5 THEN 'Congelados' WHEN 6 THEN 'Hogar' WHEN 7 THEN 'Tecnología' WHEN 8 THEN 'Snacks' WHEN 9 THEN 'Mascotas' WHEN 10 THEN 'Panadería' ELSE 'Frescos' END,
    CASE MOD(n,5) WHEN 0 THEN 'Andina' WHEN 1 THEN 'Valle' WHEN 2 THEN 'Nativa' WHEN 3 THEN 'Lumina' ELSE 'Pacífico' END,n),
  FORMAT('CAT-%02d',1+MOD(n-1,12)),
  CASE MOD(n-1,12) WHEN 0 THEN 'Abarrotes' WHEN 1 THEN 'Bebidas' WHEN 2 THEN 'Lácteos' WHEN 3 THEN 'Limpieza' WHEN 4 THEN 'Cuidado personal' WHEN 5 THEN 'Congelados' WHEN 6 THEN 'Hogar' WHEN 7 THEN 'Tecnología' WHEN 8 THEN 'Snacks' WHEN 9 THEN 'Mascotas' WHEN 10 THEN 'Panadería' ELSE 'Frescos' END,
  CASE MOD(n,5) WHEN 0 THEN 'Andina' WHEN 1 THEN 'Valle' WHEN 2 THEN 'Nativa' WHEN 3 THEN 'Lumina' ELSE 'Pacífico' END,'UNIDAD','ACTIVE'
FROM UNNEST(GENERATE_ARRAY(1,3200)) n;
DELETE FROM \`$PROJECT_ID.$GOLD_DATASET.dim_categorias\` WHERE TRUE;
INSERT INTO \`$PROJECT_ID.$GOLD_DATASET.dim_categorias\` SELECT FORMAT('CAT-%02d',n),name,IF(n<=6,'Consumo','Hogar y tecnología'),'ACTIVE' FROM UNNEST(GENERATE_ARRAY(1,12)) n CROSS JOIN UNNEST(['Abarrotes','Bebidas','Lácteos','Limpieza','Cuidado personal','Congelados','Hogar','Tecnología','Snacks','Mascotas','Panadería','Frescos']) name WITH OFFSET off WHERE n=off+1;
DELETE FROM \`$PROJECT_ID.$GOLD_DATASET.dim_almacenes\` WHERE TRUE;
INSERT INTO \`$PROJECT_ID.$GOLD_DATASET.dim_almacenes\` SELECT FORMAT('WH-%03d',n),FORMAT('Centro de distribución %03d',n),['Lima','Arequipa','Trujillo','Piura'][OFFSET(MOD(n-1,4))],FORMAT('REG-%02d',1+MOD(n-1,8)),'ACTIVE' FROM UNNEST(GENERATE_ARRAY(1,8)) n" >/dev/null
printf 'SCRIPT 88: 1 — tiendas=32 productos=3200 categorias=12 almacenes=8\n' > "$ROOT/state/$DEMO_RUN_ID/master_dimensions_loaded.txt"
echo 'SCRIPT 88: 1 — dimensiones pobladas'
