#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
heading 'Paso 06 — entorno Python aislado'
python3 -m venv "$ROOT/.venv"
"$ROOT/.venv/bin/python" -m pip install -r "$ROOT/soluciones/procesamiento-streaming/requirements.txt"
"$ROOT/.venv/bin/python" -m pip freeze > "$ROOT/state/dependencias_instaladas.txt"
"$ROOT/.venv/bin/python" -c 'import apache_beam,google.cloud.storage; print("Beam",apache_beam.__version__)'
echo 'Cloud Shell usa credenciales adjuntas. En WSL: gcloud auth application-default login si faltan ADC.'
