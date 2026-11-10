# Casos de uso y contrato de demostración

La demo mantiene un universo sintético coherente y reutiliza las mismas claves
entre streaming y batch. Cada ejecución debe producir datos válidos primero y
defectos configurables después.

| Caso | Pregunta | Gold observable |
|---|---|---|
| CU01 | ¿Qué SKU/ubicación está cerca de quebrarse y qué despacho conviene? | `cu01_riesgo_quiebre_despacho` |
| CU02 | ¿Qué debe reponerse por SKU, almacén y día? | `cu02_plan_reposicion` |
| CU03 | ¿Cómo evolucionan ventas, conversión, costos y entregas? | `cu03_kpis_operativos` |
| CU04 | ¿Qué activo presenta una anomalía y requiere mantenimiento? | `cu04_alertas_mantenimiento` |

## Capas BigQuery

- `luminalab_bronze.eventos_raw`: envelope original, `payload_json` y metadatos
  de ingesta.
- `luminalab_silver.pedidos`, `inventario`, `entregas`, `telemetria_activos` y
  `eventos_cliente`: datos normalizados con claves canónicas.
- `luminalab_gold.*`: productos consumibles por cada caso de uso.

Cloud Storage se conserva para Landing, staging/artefactos y modelos; no se
considera la capa Bronze/Silver lógica de la arquitectura actualizada.

## Claves canónicas

`simulation_id`, `scenario_id`, `event_id`/`batch_id`, `producer_id`,
`schema_version`, `occurred_at`, `emitted_at`, `trace_id`, `region_id`,
`business_unit_id`, `store_id`, `warehouse_id`, `product_id`/`sku_id`,
`customer_id`, `order_id`, `delivery_id`, `asset_id` y `sensor_id`.
