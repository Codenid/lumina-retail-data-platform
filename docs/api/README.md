# Swagger UI de Lumina Retail Insights API

Para compartir un único archivo, abre [`swagger-ui.html`](swagger-ui.html) en un navegador. Es autónomo: el contrato OpenAPI está embebido dentro del HTML.

La versión modular está en [`index.html`](index.html) y usa [`openapi.yaml`](openapi.yaml) como fuente editable.

El contrato editable está en [`openapi.yaml`](openapi.yaml). Documenta las rutas que consume la web, los cuatro casos de uso, el resumen, los catálogos, parámetros y autenticación de Cloud Run.

Si el navegador bloquea la carga local del YAML por seguridad, sirve esta carpeta con cualquier servidor estático:

```bash
python3 -m http.server 8088 --directory docs/api
```

Luego abre `http://localhost:8088/`.
