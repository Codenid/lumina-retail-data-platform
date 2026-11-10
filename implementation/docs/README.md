# Documentación

| Carpeta | Contenido |
|---|---|
| [`arquitectura/`](arquitectura/) | alcance, contratos de referencia, mapeo ArchiMate→GCP, productores y relación componente→scripts |
| [`funcional/`](funcional/) | casos de uso y productos Gold |
| [`operacion/`](operacion/) | secuencia reproducible y runbooks manuales por capacidad |
| [`informe-tecnico/`](informe-tecnico/) | informe oficial en LaTeX/PDF; el Markdown se conserva como histórico |

Las definiciones desplegables no están en `docs/`: se agrupan por capacidad en
[`../soluciones/`](../soluciones/), con su tecnología, destino GCP y scripts
responsables.

Los contratos, manifiesto de ejecución y scripts no pertenecen a `docs/`; se
encuentran agrupados en [`../automatizacion/`](../automatizacion/).

El directorio `state/` no pertenece a la documentación ni al repositorio. Los scripts lo crean localmente para guardar marcadores, IDs y evidencias de cada `DEMO_RUN_ID`.
