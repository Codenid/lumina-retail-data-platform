"""Contrato mínimo tomado del ejemplo del proyecto; sin reglas de negocio inventadas."""
import json
import re

REQUIRED = ('schema_version', 'simulation_id', 'scenario_id', 'producer_id',
            'event_type', 'event_id', 'occurred_at', 'emitted_at', 'trace_id')


def normalize(raw):
    event = json.loads(raw)
    if not isinstance(event, dict):
        raise ValueError('El evento debe ser un objeto JSON')
    for key in REQUIRED:
        if not isinstance(event.get(key), str) or not event[key].strip():
            raise ValueError(f'Campo requerido: {key}')
        event[key] = event[key].strip()
    if not isinstance(event.get('payload'), dict):
        raise ValueError('payload debe ser un objeto')
    if not re.fullmatch(r'[A-Za-z0-9_-]{1,120}', event['event_id']):
        raise ValueError('event_id no es seguro para una ruta')
    return event


def canonical(event):
    return json.dumps(event, sort_keys=True, ensure_ascii=False, separators=(',', ':')) + '\n'
