import json,sys
expected=json.load(open(sys.argv[1]))
if '--contains' in sys.argv:
    found=any(json.loads(line)==expected for line in open(sys.argv[2]) if line.strip())
    assert found, 'No se encontró el evento exacto en Bronze; espera la exportación y repite 09.'
else:
    assert json.load(open(sys.argv[2]))==expected, 'Contenido Silver diferente al evento publicado'
print('Contenido verificado:',expected['event_id'])
