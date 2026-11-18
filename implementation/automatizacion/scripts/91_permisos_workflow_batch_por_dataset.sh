#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
heading 'Paso 91 — ACL del workflow batch por dataset'
WORKFLOW_SA="$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')-compute@developer.gserviceaccount.com"
python3 - "$PROJECT_ID" "$WORKFLOW_SA" "$BRONZE_DATASET" "$SILVER_DATASET" "$GOLD_DATASET" <<'PY'
import sys
from google.cloud import bigquery

project, service_account, bronze, silver, gold = sys.argv[1:]
client = bigquery.Client(project=project)
for dataset_id, role in ((bronze, "READER"), (silver, "WRITER"), (gold, "WRITER")):
    dataset = client.get_dataset(f"{project}.{dataset_id}")
    entries = [entry for entry in dataset.access_entries if getattr(entry, "user_by_email", None) != service_account]
    entries.append(bigquery.AccessEntry(role=role, entity_type="userByEmail", entity_id=service_account))
    dataset.access_entries = entries
    client.update_dataset(dataset, ["access"])
    print(f"ACL {role}: {project}.{dataset_id} <- {service_account}")
PY
echo 'SCRIPT 91: 1 — ACL por dataset configuradas'
