# Control de ejecución reproducible

El orden canónico vive en [`automatizacion/configuracion/runbook.json`](../../automatizacion/configuracion/runbook.json).
`bash automatizacion/scripts/00_runbook.sh` valida que todos los archivos requeridos del
recorrido `00–83` estén presentes sin ejecutar operaciones en GCP.

## Convención de resultado

- `SCRIPT nn: 1`: el script verificó su criterio de aceptación.
- `SCRIPT nn: 0`: se detuvo; conserva el error original y no continúes hasta
  resolver la dependencia indicada.
- Los marcadores, IDs de ejecución y evidencias se guardan en
  `state/<DEMO_RUN_ID>/`. Ese directorio es local y no se comparte.

## Grupos y orden

| Orden | Grupo | Scripts | Cierre requerido |
|---:|---|---|---|
| 1 | Preflight | 00 | Cuenta, facturación y red existentes |
| 2 | Fundación | 01–06 | APIs, Storage, IAM, BigQuery, Pub/Sub y Python |
| 3 | Streaming base | 07–13 | 11 deja Dataflow cancelado |
| 4 | Casos batch | 14–19 | CU01–CU04 verificados |
| 5 | Integración batch | 20–28 | Transferencia, Workflow y Dataproc controlados |
| 6 | Fuentes batch | 29–35 | Bronze, Silver y Gold verificadas |
| 7 | Forecast | 36–42 | Modelo, scoring y planificación verificados |
| 8 | Insights streaming | 43–48 | 48 deja Dataflow cancelado |
| 9 | Workflow completo | 49–53 | Ejecución terminal y salida Gold verificadas |
| 10 | Batch productivo | 54–58 | Seis fuentes verificadas |
| 11 | Operational Mart | 59–62 | Integración y scheduled query verificadas |
| 12 | API | 63–67 | Cloud Run privado y rutas Gold verificadas |
| 13 | Reporting | 68–69 | Vistas Gold verificadas |
| 14 | Gobierno | 70–73 | Catálogo y linaje verificados |
| 15 | Seguridad | 74–78 | KMS, secreto CMEK y DLP verificados |
| 16 | Auditoría | 79–83 | Sink, métrica, alerta, SLO y evento verificados |

## Exclusiones deliberadas

- `90_eliminar_computo_opcional.sh` es destructivo y queda fuera de la secuencia.
  Úsalo solamente para eliminar Workflows o Dataproc que tú decidas retirar.
- Looker y la aplicación externa de consumo no pertenecen a este despliegue.
  Las vistas Gold que necesitan están en los scripts 68–69.

## Reejecución

Usa un `PREFIX` exclusivo por instalación y cambia `DEMO_RUN_ID` para una nueva
demostración. Los recursos compartidos se verifican antes de crear; los datos
de prueba y marcadores se aíslan por `DEMO_RUN_ID`.
