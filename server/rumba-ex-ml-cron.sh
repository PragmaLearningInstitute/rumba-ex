#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
exec "${RUMBA_ML_PYTHON:-python3}" rumba_ml_pipeline.py "$@"
