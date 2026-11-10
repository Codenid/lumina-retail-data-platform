# Pendientes internos: catálogo y protección de datos

Este registro es interno para planificar la implementación. No forma parte del
informe destinado a la empresa.

## Knowledge Catalog, Sensitive Data Protection y linaje

Los scripts 70–73 ya habilitan Knowledge Catalog y Data Lineage, publican
metadatos descriptivos para activos BigQuery y verifican relaciones de linaje.
Los scripts 74–78 habilitan Sensitive Data Protection, configuran una plantilla
de inspección y verifican una solicitud de inspección de contenido. Todavía no
se inspeccionan tablas almacenadas en BigQuery ni se sincronizan sus hallazgos
con la clasificación del catálogo.

### Trabajo pendiente

- Crear scripts para ejecutar inspecciones de Sensitive Data Protection sobre
  tablas BigQuery seleccionadas y definir su frecuencia.
- Procesar y conservar resultados de inspección sin persistir valores o
  fragmentos sensibles.
- Crear scripts para convertir hallazgos revisados en metadatos de clasificación
  asociados a tablas y columnas en Knowledge Catalog.
- Verificar cómo se refleja esa clasificación a través del linaje hacia vistas y
  productos derivados, y definir el tratamiento requerido antes de su consumo.
