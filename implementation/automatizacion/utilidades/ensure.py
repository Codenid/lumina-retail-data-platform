"""Describe -> compara campos declarados -> crea SOLO ante NOT_FOUND explícito."""
import json
import subprocess
import sys


def check(actual, expected):
    for path, want in expected.items():
        value = actual
        for key in path.split('.'):
            value = value.get(key) if isinstance(value, dict) else None
        # API Storage y BigQuery pueden devolver ubicación en mayúsculas.
        if path.lower().endswith('location') and isinstance(value, str):
            value, want = value.lower(), want.lower()
        if value != want:
            raise ValueError(f'Configuración divergente {path}: actual={value!r}, esperada={want!r}. No se modifica.')


def main(args):
    expected = json.loads(args[0]); split = args.index(':::')
    describe, create = args[1:split], args[split+1:]
    result = subprocess.run(describe, capture_output=True, text=True)
    if result.returncode:
        error = result.stderr + result.stdout
        denied = any(s in error.lower() for s in ['permission_denied', 'permission denied', 'forbidden', '403', 'access denied'])
        missing = any(s in error for s in ['NOT_FOUND', 'NotFound', 'Not found:', 'not found:', '404', 'does not exist'])
        if denied or not missing:
            sys.stderr.write(error); return result.returncode
        subprocess.run(create, check=True)
        result = subprocess.run(describe, capture_output=True, text=True, check=True)
    check(json.loads(result.stdout), expected)
    print('Verificado:', ' '.join(describe[:5]))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
