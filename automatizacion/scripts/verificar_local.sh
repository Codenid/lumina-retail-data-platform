#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
for script in "$ROOT"/automatizacion/scripts/*.sh; do bash -n "$script"; done
python3 -m compileall -q "$ROOT/automatizacion/utilidades" "$ROOT/soluciones" "$ROOT/tests"
python3 -m unittest discover -s "$ROOT/tests" -v
