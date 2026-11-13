# Documentación de implementación

Consulta esta carpeta para entender, operar y evidenciar la plataforma.

| Carpeta | Contenido |
|---|---|
| [`arquitectura/`](arquitectura/) | alcance, contratos de referencia, mapeo ArchiMate→GCP, productores y relación componente→scripts |
| [`funcional/`](funcional/) | casos de uso y productos Gold |
| [`operacion/`](operacion/) | secuencia reproducible y runbooks manuales por capacidad |
| [`informe-tecnico/`](informe-tecnico/) | fuentes LaTeX del informe técnico; el Markdown se conserva como histórico |

Las definiciones desplegables están fuera de `docs/`, agrupadas por capacidad en
[`../soluciones/`](../soluciones/), con su tecnología, destino GCP y scripts
responsables.

Los contratos, manifiesto de ejecución y scripts no pertenecen a `docs/`; se
encuentran agrupados en [`../automatizacion/`](../automatizacion/).

## Ruta recomendada

1. Revisa [`arquitectura/`](arquitectura/) para alcance y trazabilidad.
2. Ejecuta [`operacion/`](operacion/) para instalación y validación.
3. Consulta el [informe técnico PDF](../../docs/informes/informe-tecnico-implementacion-gcp.pdf) o sus [fuentes](informe-tecnico/informe/).

El directorio `state/` es local: los scripts lo crean para guardar marcadores,
IDs y evidencias de cada `DEMO_RUN_ID`.
