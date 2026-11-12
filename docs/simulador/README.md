# Explorador end-to-end

Simulador visual autocontenido, disponible dentro del portal integral. Recorre
CU01–CU04, el flujo de pedido streaming y la demostración batch de Dataproc.

Cada paso muestra la entrada recibida, la transformación y salida, el contrato,
las validaciones, la persistencia y los controles relacionados. La salida de
una etapa alimenta la entrada de la siguiente; las bifurcaciones Pub/Sub indican
de qué suscripción procede cada rama.

El catálogo permite consultar los 20 componentes del mapeo ArchiMate. Los datos
son ilustrativos y no se envían a GCP.
