#!/bin/sh
set -eu

SYMPHONY_API="${SYMPHONY_API:-http://127.0.0.1:8082/v1alpha2}"
base_dir="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"

echo "Seeding Symphony target and echo-stack resources into $SYMPHONY_API"

curl -fsS -X POST -H "Content-Type: application/json" \
  --data @"$base_dir/symphony/ankaios/target/linaro-ankaios.json" \
  "$SYMPHONY_API/targets/registry/linaro-ankaios" >/dev/null

curl -fsS -X POST -H "Content-Type: application/json" \
  --data @"$base_dir/symphony/ankaios/echo-stack/solution-version.json" \
  "$SYMPHONY_API/solutionversions/ankaios-echo-stack-v-v1" >/dev/null

curl -fsS -X POST -H "Content-Type: application/json" \
  --data @"$base_dir/symphony/ankaios/echo-stack/instance.json" \
  "$SYMPHONY_API/instances/ankaios-echo-stack-instance" >/dev/null
