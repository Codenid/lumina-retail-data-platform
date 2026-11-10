# Arquitectura y trazabilidad

| Archivo | Uso |
|---|---|
| `alcance.md` | capacidades implementadas, límites y decisiones de arquitectura |
| `mapeo-archimate-gcp.csv` | fuente principal: elemento ArchiMate, servicio GCP, implementación y estado |
| `componentes-scripts.csv` | trazabilidad desde un componente hasta los scripts que lo aprovisionan o verifican |
| `productores.csv` | fuentes externas previstas, modo de ingreso y destino |
| `contrato-evento-original.json` | evento base usado por la demostración streaming |

## Estados del mapeo

- `DEPLOYED_VERIFIED`: recurso y criterio de aceptación verificados.
- `DEPLOYED_VERIFIED_EPHEMERAL`: recurso probado y cerrado por diseño para controlar costo.
- `DEPLOYED_PARTIAL`: existe una parte útil; queda una integración específica por completar.
- `IMPLEMENTED_WITH_SUBSTITUTION`: la capacidad existe, pero usa una tecnología distinta de la declaración inicial.
- `VIEWS_READY_CONSUMER_OPTIONAL`: el producto de datos está listo; el consumidor externo queda fuera de alcance.
