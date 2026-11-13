# Informes del proyecto

Repositorio central de los documentos ejecutivos en PDF.

| Documento | Contenido | Fuente editable |
|---|---|---|
| [Informe general](informe-general.pdf) | Contexto, propuesta, arquitectura y evaluación del proyecto. | [`docs/report/`](../report/) |
| [Informe de implementación](informe-tecnico-implementacion-gcp.pdf) | Implementación, contratos, validaciones y evidencia técnica. | [`implementation/docs/informe-tecnico/informe/`](../../implementation/docs/informe-tecnico/informe/) |

Los PDF se regeneran desde sus fuentes y se publican en esta carpeta:

- `make -C docs/report pdf`
- `make -C implementation/docs/informe-tecnico/informe pdf`
