# Diagramas ArchiMate para el informe

`arquitectura-archimate.svg` es la vista completa de referencia. Los flujos
incrementales deben exportarse desde ArchiMate y ubicarse en esta misma carpeta:

| Archivo esperado | Recorrido | Alcance visual |
|---|---|---|
| `flujo-01-fundacion-medallion.svg` | fundación | Cloud Storage, BigQuery y capas Landing/Bronze/Silver/Gold |
| `flujo-02-streaming-pedidos.svg` | streaming | Pub/Sub, ramas Bronze/Dataflow, Silver y Gold |
| `flujo-03-insights-auditoria.svg` | Insights | tópico, Dataflow, Insights y auditoría Gold |
| `flujo-04-batch-orquestacion.svg` | batch | Landing, transferencia, Workflow, medallón y Mart |
| `flujo-05-forecast-reposicion.svg` | forecast | features, baseline, artefacto, predicción y CU02 |
| `flujo-06-gold-api-reporting.svg` | consumo | productos Gold, vistas y Cloud Run |
| `flujo-07-controles-transversales.svg` | controles | gobierno, seguridad, auditoría y observabilidad |

Reglas de exportación: fondo claro, tipografía legible a ancho de página,
etiquetas fuera de las formas cuando no quepan, conectores sin cruces evitables
y paleta sobria. Cada gráfico debe destacar solo el recorrido de su sección;
la arquitectura completa no se debe duplicar.
