# Alcance de la arquitectura

Este repositorio entrega una implementación reproducible de la plataforma
interna descrita en ArchiMate. El inventario de origen se conserva en
`mapeo-archimate-gcp.csv` y los productores en `productores.csv`.

## Componentes cubiertos por scripts

| Dominio | Implementación |
|---|---|
| Ingesta | Pub/Sub y Dataflow para streaming; Storage Transfer, BigQuery y Dataproc para batch de demostración. |
| Medallion | Landing en Cloud Storage; Bronze, Silver y Gold en datasets BigQuery. |
| Casos de uso | Riesgo de quiebre, reposición, KPIs operativos y alertas de mantenimiento. |
| Orquestación | Google Cloud Workflows y scheduled query para Operational Mart. |
| Forecast | Features, artefacto de modelo, scoring y planificación diaria de demostración. |
| API | Cloud Run privado que consulta productos Gold. |
| Gobierno | Metadatos, catálogo y linaje de activos BigQuery. |
| Seguridad | IAM mínimo, KMS, Secret Manager con CMEK y plantilla DLP. |
| Observabilidad | Audit Store, sink de Logging, métrica, alerta y SLO del servicio API. |

## Límites deliberados

- Los productores y datos son sintéticos. Conectar productores externos reales,
  definir SLA y calendarizar llegadas recurrentes es una actividad posterior.
- Dataflow es temporal para cada demostración; los scripts de cierre cancelan
  los jobs creados. No se deja un streaming job permanentemente activo.
- Dataproc es un clúster de demostración de un solo nodo, con autoeliminación.
  Revisa costo, cuota y red antes de los pasos 20–28.
- Las vistas Gold están listas para consumo, pero Looker y una aplicación
  externa de reporting están fuera de este repositorio.
- El script 90 puede eliminar cómputo opcional, por eso no se ejecuta como parte
  de la secuencia reproducible.

## Reglas de seguridad y reejecución

- Todos los recursos se derivan de `PROJECT_ID`, `REGION` y `PREFIX`.
- Los datos de cada ensayo se separan por `DEMO_RUN_ID` dentro de `state/` y en
  las tablas de demostración.
- Los scripts verifican recursos existentes; ante una divergencia o denegación
  de IAM, fallan con el error original en lugar de recrear o ampliar permisos.
- La cuenta que ejecuta el repositorio debe estar autorizada por el proyecto y
  por las políticas de la organización. Ese requisito no se resuelve mediante
  scripts ni mediante roles amplios.
