"""Streaming: Pub/Sub -> validar/normalizar -> tablas Silver BigQuery."""
import argparse
import logging
import apache_beam as beam
from apache_beam.metrics import Metrics
from apache_beam.options.pipeline_options import PipelineOptions
from contract import normalize


class ValidateEvent(beam.DoFn):
    def __init__(self):
        self.received = Metrics.counter('retailsmart', 'eventos_recibidos')
        self.valid = Metrics.counter('retailsmart', 'eventos_validos')

    def process(self, raw):
        self.received.inc()
        event = normalize(raw)
        self.valid.inc()
        logging.info('EVENTO_VALIDO event_id=%s', event['event_id'])
        yield event


def to_silver_row(event):
    payload = event['payload']
    if event['event_type'] != 'order_created':
        return None
    return {
        'order_id': payload['order_id'], 'order_line_id': payload.get('order_line_id'),
        'customer_id': payload.get('customer_id'), 'store_id': payload.get('store_id'),
        'warehouse_id': payload.get('warehouse_id'), 'sku_id': payload['product_id'],
        'quantity': int(payload['quantity']), 'occurred_at': event['occurred_at'],
        'quality_status': 'VALID'
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--input_subscription', required=True)
    parser.add_argument('--silver_table', required=True)
    args, beam_args = parser.parse_known_args()
    pipeline = beam.Pipeline(options=PipelineOptions(beam_args))
    (pipeline | 'LeerPubSub' >> beam.io.ReadFromPubSub(subscription=args.input_subscription)
              | 'ValidarNormalizar' >> beam.ParDo(ValidateEvent())
              | 'MapearPedidosSilver' >> beam.Map(to_silver_row)
              | 'FiltrarEventosNoPedido' >> beam.Filter(bool)
              | 'SilverPedidosBigQuery' >> beam.io.WriteToBigQuery(
                  table=args.silver_table,
                  schema='order_id:STRING,order_line_id:STRING,customer_id:STRING,store_id:STRING,warehouse_id:STRING,sku_id:STRING,quantity:INTEGER,occurred_at:TIMESTAMP,quality_status:STRING',
                  method=beam.io.gcp.bigquery.WriteToBigQuery.Method.STREAMING_INSERTS,
                  create_disposition=beam.io.gcp.bigquery.BigQueryDisposition.CREATE_NEVER,
                  write_disposition=beam.io.gcp.bigquery.BigQueryDisposition.WRITE_APPEND))
    result = pipeline.run()
    # Devuelve el control al terminal: la verificación y cancelación son pasos separados.
    print('JOB_ID=' + result.job_id(), flush=True)


if __name__ == '__main__':
    logging.basicConfig(level=logging.INFO)
    main()
