# Productora de datos Lumina

Mando privado para simular las aplicaciones que alimentan la plataforma. La
pantalla permite elegir productores, perfil de volumen y duración, iniciar la
carga, ver el progreso y detenerla.

## Productores disponibles

- **Streaming (6):** canales, cámaras frigoríficas, estantería inteligente,
  sensores IoT de tienda, sensores de almacén y tracking logístico. Emite
  contratos JSON por Pub/Sub; Dataflow enruta pedidos, inventario, entregas y
  telemetría a sus tablas Silver.
- **Batch (6):** pedidos, inventario, entregas, benchmark de competidores,
  eventos locales y redes sociales. Genera JSONL por productor en Landing,
  carga Bronze y activa Workflows; este cura los seis dominios y materializa
  CU01–CU03 y el mart operativo según los datos del lote.

Los payloads se rigen por
`automatizacion/configuracion/contratos/productor_datos.json`, el envelope
Streaming por `docs/arquitectura/contrato-evento-original.json`, Bronze por
`bigquery_schema.json` y los productores por
`docs/arquitectura/productores.csv`.

## Ejecución local

```bash
cd implementation/soluciones/productor-datos
make auth       # una sola vez por entorno
make start      # instala dependencias y levanta la app
```

Abre `http://127.0.0.1:8081`. Si el puerto está ocupado, ejecuta
`make run PORT=8082`. `make install` instala las dependencias por separado.

## Actualización y despliegue GCP

Despliega la aplicación después de crear los recursos y permisos. La ejecución
Batch requiere Workflows desplegado; la ejecución Streaming necesita un Dataflow
Silver activo. La falta de Dataflow ya no bloquea el despliegue ni las cargas Batch.

1. Para Batch, ejecuta los preflight y despliega el Workflow con los pasos 49–50.
2. Para Streaming, ejecuta los preflight de Dataflow y reinicia el consumidor con
   `automatizacion/scripts/07_iniciar_dataflow.sh`; verifica el job con el paso 08.
3. Despliega la aplicación privada:

```bash
bash implementation/soluciones/productor-datos/deploy.sh
gcloud run services proxy "${PREFIX}-productor-datos" --region="$REGION" --port=8080
```

Cloud Run se configura con una instancia y CPU disponible durante la
simulación, porque el controlador de carga vive en el proceso. El servicio
genera costo mientras permanezca desplegado; el volumen estimado no es un
estimador monetario.

El despliegue asigna al productor lectura y escritura de objetos en Landing.
BigQuery necesita leer esos objetos para cargar Bronze. Si solo se actualiza el
código, vuelve a ejecutar `deploy.sh` para aplicar también los permisos IAM.

## Perfiles y límites

Streaming: 1–10.000 eventos/s totales y 1–60 minutos. Batch: 1–100.000 filas
por productor/archivo, intervalos de 10 segundos a 60 minutos y duración de
1–60 minutos. El límite total por ejecución es 10 millones de registros. El
throughput efectivo depende de las cuotas Pub/Sub, la tasa de escritura, la
capacidad de Dataflow, BigQuery y la red del proyecto. El paso 07 define
Dataflow con escalado por throughput de 2 a 20 workers; el límite de cuota de
la región del proyecto sigue aplicando.

No se carga directamente en Gold. La ejecución avanza por los puntos de
entrada y consumidores de la arquitectura. El estado e historial se conservan
en memoria de la instancia y se pierden al reiniciarla. La app consumidora es
un producto separado pendiente.
