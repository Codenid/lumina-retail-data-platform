#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
heading 'Paso 14 — fixtures batch CU01–CU04'
export ROOT
python3 "$ROOT/automatizacion/utilidades/generate_use_case_fixtures.py"
echo 'OK: fixtures batch presentes'
