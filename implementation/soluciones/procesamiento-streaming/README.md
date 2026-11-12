# Procesamiento streaming

Los pipelines Apache Beam de esta carpeta se ejecutan en Google Cloud
Dataflow. `streaming.py` lee el tópico de entrada y enruta eventos contratados
de pedidos, inventario, entregas y sensores a sus tablas Silver respectivas.
El despliegue de esas rutas usa el paso 07; verifica el job con el paso 08.
`insights_streaming.py` es el flujo separado de Insights Gold y auditoría,
controlado por los pasos 43–48.
