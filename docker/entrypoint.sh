#!/usr/bin/env bash
set -euo pipefail
echo "Container ready."
echo "In ACI: az login --identity && az account show"
echo "Then:   cd /work/terraform && terraform init/plan/apply"
exec "$@"
