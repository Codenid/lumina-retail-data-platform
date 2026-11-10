# Módulo de análisis de costos GCP

Matriz estática para capturar, revisar y guardar el costeo paramétrico del proyecto Lumina Retail Data Platform en una sola pantalla.

## Uso

Abrir [`index.html`](index.html) en un navegador. La primera vista muestra 20 servicios de referencia con capacidad inicial, proyección, unidad de cobro y costo mensual. Cada fila se puede expandir para revisar sus componentes —por ejemplo almacenamiento, operaciones, transferencia, cómputo o consultas— y editar cada importe. El encabezado totaliza el costo mensual y la proyección anual.

Los valores iniciales son supuestos de trabajo y deben reemplazarse con los resultados de Google Cloud Pricing Calculator. El JSON exportado queda listo como insumo para una futura sección del informe general.

## Orden de integración

1. Revisar el costo mensual y anual del encabezado.
2. Abrir cada servicio y validar sus componentes de cobro.
3. Reemplazar capacidad, proyección y costos con los resultados de la calculadora de GCP.
4. Guardar o exportar el escenario aprobado para anexarlo al informe.

Este módulo no consulta GCP en tiempo real; mantiene la separación entre la calculadora oficial y el análisis documentado del proyecto.
