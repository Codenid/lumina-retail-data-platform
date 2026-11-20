# Lumina Retail · Aplicación de consumo

Aplicación web end-to-end para el consumo de información operacional. La
interfaz consulta los servicios publicados y presenta las vistas funcionales
de Lumina Retail.

## Vistas

- Resumen ejecutivo
- Riesgo de stock
- Forecast y reposición
- Operación pedidos/entregas
- Mantenimiento de activos
- Insights tiempo real
- Mercado y contexto
- Calidad y trazabilidad

## Ejecución local

Desde la raíz del repositorio:

```bash
python3 -m http.server 8080 --directory web/lumina-consumo
```

Abrir `http://localhost:8080`.

## Integración

La aplicación consume información mediante funciones `fetch` sobre las rutas:

```text
/api/v1/insights
/api/v1/kpis
/api/v1/inventory-plans
/api/v1/maintenance-risks
```

La aplicación no consulta BigQuery directamente. El `scenario_id` del selector
debe conservarse al conectar el API real.
