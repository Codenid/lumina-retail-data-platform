# Plan de aplicación web de consumo

## Objetivo

Construir una aplicación web externa, orientada a una ejecución ejecutiva y
operativa, que consuma los resultados publicados por la plataforma RetailSmart.
La aplicación no procesa ni transforma datos de negocio: consulta el API de
consumo y presenta los cuatro casos de uso Gold con su fecha de actualización,
escenario y fuente.

La aplicación debe verse como una herramienta de operación real. Los datos son
controlados para la ejecución, pero se presentan como observaciones de negocio:
ventas, inventario, entregas, competencia, eventos locales, redes sociales y
telemetría.

## Arquitectura propuesta

```text
BigQuery Gold
    │
    ▼
RetailSmart API / Cloud Run
    │  GET + scenario_id
    ▼
Aplicación web externa
    ├── Resumen ejecutivo
    ├── Riesgo de quiebre y tendencia de inventario
    ├── Plan de reposición
    ├── KPIs operativos
    └── Riesgos de mantenimiento
```

La aplicación no debe conectarse directamente a BigQuery. El API es el límite de
seguridad y de contrato. En producción se recomienda mantener el API privado y
publicar la aplicación mediante un backend-for-frontend o una integración
segura; para la presentación se puede usar un endpoint de operación con credenciales
de solo lectura y un `scenario_id` explícito.

## Pantallas

### 1. Resumen ejecutivo

Pantalla inicial para explicar el valor de la arquitectura en menos de un
minuto.

- Estado de la operación: estable, atención o crítico.
- Stock disponible y productos con riesgo.
- Pedidos y unidades del periodo.
- Cumplimiento de entrega.
- Alertas de mantenimiento activas.
- Última actualización del escenario.
- Botón “Actualizar datos”.

Debe mostrar una frase ejecutiva generada a partir de los resultados, por
ejemplo: “SKU-001 en STORE-001 agotará su stock disponible en los próximos
días si se mantiene la demanda observada”.

### 2. Riesgo de quiebre

Es la vista principal para responder cuándo puede acabarse el stock.

- Selector de tienda, SKU y escenario.
- Tarjeta de stock disponible.
- Tabla de riesgo por SKU y tienda.
- Gráfico de línea con snapshots de inventario.
- Proyección visual de umbral de reposición.
- Acción recomendada: `REPOSICIONAR/DESPACHAR` o `MONITOREAR`.
- Fecha de observación y nivel de riesgo.

La primera versión puede calcular el texto de tendencia en el frontend a partir
de los snapshots recibidos; no debe inventar una predicción numérica si el API
no publica una predicción formal.

### 3. Plan de reposición

- Productos que requieren reposición.
- Cantidad demandada.
- Cantidad recomendada.
- Prioridad `HIGH` o `NORMAL`.
- Almacén asociado.
- Fecha del plan.
- Filtros por prioridad y almacén.

Esta vista debe responder qué comprar, cuánto y con qué urgencia.

### 4. KPIs operativos

- Pedidos.
- Unidades.
- Costo de entrega.
- SLA de entrega.
- Conversión, cuando esté disponible.
- Comparación contra el periodo o escenario anterior, si el API lo soporta.

Debe incluir una nota visible indicando el periodo y el `scenario_id` usado.

### 5. Riesgos de mantenimiento

- Activo.
- Sensor.
- Almacén.
- Tipo de anomalía.
- Severidad.
- Valor medido.
- Fecha de ocurrencia.

La vista debe separar anomalías `HIGH` de condiciones normales y permitir
ordenar por severidad y fecha.

## Contrato del frontend con el API

Endpoint base configurable por ambiente:

```text
VITE_API_BASE_URL=https://<api>/api/v1
VITE_SCENARIO_ID=<scenario_id>
```

Rutas:

| Vista | Ruta | Respuesta esperada |
|---|---|---|
| Resumen | `/insights?limit=25&scenario_id=...` | insights y riesgos de stock |
| KPIs | `/kpis?limit=25&scenario_id=...` | KPIs operativos |
| Reposición | `/inventory-plans?limit=25&scenario_id=...` | planes de reposición |
| Mantenimiento | `/maintenance-risks?limit=25&scenario_id=...` | alertas de activos |

Reglas del cliente:

1. No llamar a BigQuery desde el navegador.
2. No incluir credenciales en el bundle frontend.
3. Mostrar carga, vacío y error por cada tarjeta o módulo.
4. Conservar el `scenario_id` en la URL para que una captura sea reproducible.
5. Formatear fechas y números según `es-PE`.
6. No ocultar el origen: mostrar “Fuente: RetailSmart API → BigQuery Gold”.

## Diseño visual

La aplicación debe tener apariencia de centro de control retail, no de una
maqueta técnica:

- Fondo claro cálido, paneles blancos y contraste alto.
- Azul petróleo para navegación y confianza.
- Ámbar para atención y rojo controlado para riesgo crítico.
- Tipografía sans-serif legible.
- Gráficos simples, con valores visibles y leyendas claras.
- Diseño responsive para laptop y proyector.
- Estados accesibles que no dependan únicamente del color.

La navegación recomendada es una barra lateral con cinco destinos: Resumen,
Riesgo de stock, Reposición, KPIs y Mantenimiento.

## Modos de ejecución

### Modo conectado

Consume el API real mediante `VITE_API_BASE_URL` y `VITE_SCENARIO_ID`. Es el
modo que demuestra el valor de la infraestructura completa.

### Modo presentación

Usa respuestas JSON versionadas en `public/sample-data/` únicamente cuando el
API no esté disponible durante ensayos. Debe estar rotulado como “Datos de
ensayo” y tener un interruptor visible; nunca debe confundirse con el modo
conectado.

## Plan de implementación

### Fase 1 — Contrato y esqueleto

- Confirmar nombres de campos y `scenario_id` del API.
- Crear aplicación estática buildless o React/Vite, según necesidad de
  interactividad.
- Crear cliente HTTP tipado con cuatro funciones de consulta.
- Implementar manejo común de carga, error, vacío y reintento.

### Fase 2 — Experiencia de consumo

- Implementar layout y navegación.
- Implementar resumen ejecutivo.
- Implementar riesgo de quiebre con tendencia de inventario.
- Implementar reposición, KPIs y mantenimiento.
- Añadir filtros y actualización manual.

### Fase 3 — Integración y presentación

- Conectar el `scenario_id` generado por los scripts de carga.
- Validar que los cuatro módulos muestran filas reales del API.
- Añadir modo presentación con datos de respaldo claramente rotulado.
- Preparar una ruta de ejecución: resumen → quiebre → reposición → KPIs →
  mantenimiento.

### Fase 4 — Calidad y despliegue

- Pruebas de contrato del API.
- Pruebas responsive y accesibilidad básica.
- Validación de errores 400, 404, 500 y timeout.
- Verificación de CORS, autenticación y exposición del endpoint.
- Publicación como sitio estático separado de la infraestructura de datos.

## Criterios de aceptación

- Una persona puede entender el valor de la plataforma desde la pantalla
  inicial en menos de un minuto.
- Los cuatro casos de uso se pueden abrir desde la navegación.
- Cada vista muestra datos del mismo `scenario_id` y fecha de actualización.
- Riesgo de stock muestra una tendencia visible, no solo una tabla.
- La aplicación nunca consulta BigQuery directamente.
- Cuando el API falla, la interfaz explica el problema y ofrece reintento.
- El modo de respaldo no se presenta como dato conectado.
- La operación funciona en laptop y en una pantalla de presentación.

## Secuencia de ejecución

1. Abrir Resumen y mostrar que todos los indicadores provienen del mismo
   escenario.
2. Entrar a Riesgo de stock y señalar el descenso de `SKU-001` en `STORE-001`.
3. Abrir Reposición y mostrar la cantidad y prioridad recomendadas.
4. Abrir KPIs para conectar inventario con pedidos y entregas.
5. Abrir Mantenimiento para mostrar que el mismo modelo sirve para activos y
   sensores.
6. Cerrar mostrando que la aplicación es un consumidor desacoplado: el valor
   aparece después de que la arquitectura procesa y publica los datos.
