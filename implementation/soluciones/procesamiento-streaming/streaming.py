"""Streaming: Pub/Sub -> validar/normalizar -> tablas Silver BigQuery."""
import argparse
import logging
import apache_beam as beam
from apache_beam.metrics import Metrics
from apache_beam.options.pipeline_options import PipelineOptions
from contract import normalize

EVENT_PROFILES = {
    'order_created': ('channel-apps', ('order_id', 'product_id', 'quantity')),
    'cold_chain_reading': ('cold-room-sensors', ('asset_id', 'sensor_id', 'warehouse_id', 'metric_value', 'unit')),
    'inventory_level_changed': ('smart-shelves', ('snapshot_id', 'warehouse_id', 'sku_id', 'on_hand_qty', 'reserved_qty')),
    'store_sensor_reading': ('store-iot-sensors', ('asset_id', 'sensor_id', 'store_id', 'metric_value', 'unit')),
    'warehouse_sensor_reading': ('warehouse-sensors', ('asset_id', 'sensor_id', 'warehouse_id', 'metric_value', 'unit')),
    'delivery_status_changed': ('logistics-tracking', ('delivery_id', 'order_id', 'delivered_at')),
}


class ValidateEvent(beam.DoFn):
    def __init__(self):
        self.received = Metrics.counter('retailsmart', 'eventos_recibidos')
        self.valid = Metrics.counter('retailsmart', 'eventos_validos')

    def process(self, raw):
        self.received.inc()
        event = normalize(raw)
        profile = EVENT_PROFILES.get(event['event_type'])
        if profile:
            expected_producer, required = profile
            if event['producer_id'] != expected_producer:
                raise ValueError(f"producer_id inválido para {event['event_type']}")
            missing = [key for key in required if event['payload'].get(key) in (None, '')]
            if missing:
                raise ValueError(f"Campos faltantes en {event['event_type']}: {', '.join(missing)}")
        elif event['event_type'] not in {'order_created', 'cold_chain_reading', 'inventory_level_changed', 'store_sensor_reading', 'warehouse_sensor_reading', 'delivery_status_changed'}:
            raise ValueError(f"event_type sin ruta Silver: {event['event_type']}")
        self.valid.inc()
        logging.info('EVENTO_VALIDO event_id=%s', event['event_id'])
        yield event


def to_silver_route(event):
    payload = event['payload']
    event_type = event['event_type']
    if event_type == 'order_created':
        return 0, {
            'order_id': payload['order_id'], 'order_line_id': payload.get('order_line_id'),
            'customer_id': payload.get('customer_id'), 'store_id': payload.get('store_id'),
            'warehouse_id': payload.get('warehouse_id'), 'sku_id': payload.get('product_id') or payload.get('sku_id'),
            'quantity': int(payload['quantity']), 'occurred_at': event['occurred_at'],
            'quality_status': 'VALID'
        }
    if event_type == 'inventory_level_changed':
        return 1, {
            'snapshot_id': payload['snapshot_id'], 'warehouse_id': payload['warehouse_id'],
            'store_id': payload.get('store_id'), 'sku_id': payload['sku_id'],
            'on_hand_qty': int(payload['on_hand_qty']), 'reserved_qty': int(payload['reserved_qty']),
            'effective_at': payload.get('effective_at') or event['occurred_at'], 'quality_status': 'VALID'
        }
    if event_type == 'delivery_status_changed':
        return 2, {
            'delivery_id': payload['delivery_id'], 'order_id': payload['order_id'],
            'store_id': payload.get('store_id'), 'region_id': payload.get('region_id'),
            'promised_at': payload.get('promised_at'), 'delivered_at': payload['delivered_at'],
            'delivery_cost': payload.get('delivery_cost'), 'quality_status': 'VALID'
        }
    if event_type in {'cold_chain_reading', 'store_sensor_reading', 'warehouse_sensor_reading'}:
        return 3, {
            'asset_id': payload['asset_id'], 'sensor_id': payload['sensor_id'],
            'warehouse_id': payload.get('warehouse_id'), 'store_id': payload.get('store_id'),
            'metric_name': payload.get('metric_name') or event_type,
            'metric_value': float(payload['metric_value']), 'unit': payload['unit'],
            'occurred_at': event['occurred_at'], 'quality_status': 'VALID'
        }
    return None


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--input_subscription', required=True)
    parser.add_argument('--silver_table', required=True)
    parser.add_argument('--silver_inventory_table', default=None)
    parser.add_argument('--silver_delivery_table', default=None)
    parser.add_argument('--silver_telemetry_table', default=None)
    args, beam_args = parser.parse_known_args()
    base_table = args.silver_table.rsplit('.', 1)[0]
    args.silver_inventory_table = args.silver_inventory_table or f'{base_table}.inventario'
    args.silver_delivery_table = args.silver_delivery_table or f'{base_table}.entregas'
    args.silver_telemetry_table = args.silver_telemetry_table or f'{base_table}.telemetria_activos'
    pipeline = beam.Pipeline(options=PipelineOptions(beam_args))
    routed = (pipeline | 'LeerPubSub' >> beam.io.ReadFromPubSub(subscription=args.input_subscription)
                      | 'ValidarNormalizar' >> beam.ParDo(ValidateEvent())
                      | 'EnrutarPorContrato' >> beam.Map(to_silver_route)
                      | 'ExcluirEventoSinRuta' >> beam.Filter(bool))
    orders, inventory, deliveries, telemetry = routed | 'SepararDominios' >> beam.Partition(lambda row, n: row[0], 4)
    writer = dict(method=beam.io.gcp.bigquery.WriteToBigQuery.Method.STREAMING_INSERTS,
                  create_disposition=beam.io.gcp.bigquery.BigQueryDisposition.CREATE_NEVER,
                  write_disposition=beam.io.gcp.bigquery.BigQueryDisposition.WRITE_APPEND)
    (orders | 'PedidoSilverRow' >> beam.Map(lambda row: row[1])
            | 'SilverPedidosBigQuery' >> beam.io.WriteToBigQuery(table=args.silver_table,
                schema='order_id:STRING,order_line_id:STRING,customer_id:STRING,store_id:STRING,warehouse_id:STRING,sku_id:STRING,quantity:INTEGER,occurred_at:TIMESTAMP,quality_status:STRING', **writer))
    (inventory | 'InventarioSilverRow' >> beam.Map(lambda row: row[1])
               | 'SilverInventarioBigQuery' >> beam.io.WriteToBigQuery(table=args.silver_inventory_table,
                   schema='snapshot_id:STRING,warehouse_id:STRING,store_id:STRING,sku_id:STRING,on_hand_qty:INTEGER,reserved_qty:INTEGER,effective_at:TIMESTAMP,quality_status:STRING', **writer))
    (deliveries | 'EntregaSilverRow' >> beam.Map(lambda row: row[1])
                | 'SilverEntregasBigQuery' >> beam.io.WriteToBigQuery(table=args.silver_delivery_table,
                    schema='delivery_id:STRING,order_id:STRING,store_id:STRING,region_id:STRING,promised_at:TIMESTAMP,delivered_at:TIMESTAMP,delivery_cost:NUMERIC,quality_status:STRING', **writer))
    (telemetry | 'TelemetriaSilverRow' >> beam.Map(lambda row: row[1])
               | 'SilverTelemetriaBigQuery' >> beam.io.WriteToBigQuery(table=args.silver_telemetry_table,
                   schema='asset_id:STRING,sensor_id:STRING,warehouse_id:STRING,store_id:STRING,metric_name:STRING,metric_value:FLOAT,unit:STRING,occurred_at:TIMESTAMP,quality_status:STRING', **writer))
    result = pipeline.run()
    # Devuelve el control al terminal: la verificación y cancelación son pasos separados.
    print('JOB_ID=' + result.job_id(), flush=True)


if __name__ == '__main__':
    logging.basicConfig(level=logging.INFO)
    main()
