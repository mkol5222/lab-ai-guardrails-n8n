#!/usr/bin/env bash
# Print a Helm values file (JSON) listing OpenRouter's current free text models
# (the same set as https://openrouter.ai/collections/free-models) plus the "openrouter/free" router.
# Public catalog endpoint, no API key needed.
set -euo pipefail
curl -fsS --max-time 20 https://openrouter.ai/api/v1/models | jq '
  [ .data[]
    | select((.id | endswith(":free")) or (.pricing.prompt == "0" and .pricing.completion == "0"))
    | select((.architecture.output_modalities // ["text"]) == ["text"])   # text-only output, so Lakera can inspect every response
    | .id ] + ["openrouter/free"]
  | unique | {models: .}'
