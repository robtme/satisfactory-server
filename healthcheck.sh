#!/bin/bash
set -o pipefail

# A specific MULTIHOME address isn't reachable via localhost; an invalid one falls back to :: in run.sh.
hosts=("127.0.0.1")
if [[ -n "$MULTIHOME" && "$MULTIHOME" != "::" ]]; then
    [[ "$MULTIHOME" == *:* ]] && hosts+=("[$MULTIHOME]") || hosts+=("$MULTIHOME")
fi

for host in "${hosts[@]}"; do
    curl -k -f -s -S --max-time 10 -X POST "https://${host}:${SERVERGAMEPORT}/api/v1" \
    -H "Content-Type: application/json" \
    -d '{"function":"HealthCheck","data":{"clientCustomData":""}}' \
    | jq -e '.data.health == "healthy"' && exit 0
done
exit 1
