# Explorador end-to-end

Simulador visual autocontenido, disponible dentro del portal integral. Recorre
CU01–CU04 en batch y con una ruta streaming ilustrativa para cada caso.

Cada paso muestra la entrada recibida, la transformación y salida, el contrato,
las validaciones, la persistencia y los controles relacionados. La salida de
una etapa alimenta la entrada de la siguiente; las bifurcaciones Pub/Sub indican
de qué suscripción procede cada rama.

Las rutas streaming muestran el evento específico, su publicación en Pub/Sub,
la rama raw de BigQuery y la transformación Dataflow esperada. El pipeline
desplegado de pedidos admite `order_created`; las transformaciones streaming de
inventario y telemetría, así como la actualización Gold de los cuatro casos,
se etiquetan como simulación porque hoy esos productos se materializan por
batch. La ruta CU01 de Insights implementado se conserva por separado.

El catálogo permite consultar los 20 componentes del mapeo ArchiMate. Los datos
son ilustrativos y no se envían a GCP.
