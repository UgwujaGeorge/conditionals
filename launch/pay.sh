#!/usr/bin/env bash
# Pays for the Conditionals IMD launch on Robinhood Chain through the Intake (0.5 IMD).
# Usage: launch/pay.sh build <owner> <feeRecipient>   writes launch/launch.json from the template at HEAD
#        launch/pay.sh approve                         lets the Intake pull 0.5 IMD, once
#        launch/pay.sh launch                          checks launch/launch.json (free) and pays only if it passes
# Signs with PRIVATE_KEY from ~/.conditionals/deployer.env.
set -euo pipefail
cd "$(dirname "$0")"

IMD_API=https://api.imd.fun
RPC=${RPC:-https://rpc.mainnet.chain.robinhood.com}
INTAKE=0xa43e6f75ee006411f79ac1c84120606c2330de82
IMD=0x5f7bb59365ce557c26dbcaa4ee9d39a4b95b7127
PRICE=500000000000000000

case "${1:-}" in
  build)
    owner=$(echo "${2:?owner address}" | tr 'A-F' 'a-f')
    fee=$(echo "${3:?fee recipient address}" | tr 'A-F' 'a-f')
    commit=$(git rev-parse HEAD)
    git diff --quiet HEAD || { echo "commit your changes first: the launch pins HEAD" >&2; exit 1; }
    sed -e "s/FEE_RECIPIENT/$fee/" -e "s/\"OWNER\"/\"$owner\"/" -e "s/COMMIT/$commit/" launch.template.json | jq . > launch.json
    echo "launch.json pinned to $commit"
    exit 0
    ;;
esac

# shellcheck disable=SC1090
source ~/.conditionals/deployer.env
SIGNER=(--private-key "$PRIVATE_KEY")

case "${1:-}" in
  approve)
    cast send $IMD 'approve(address,uint256)' $INTAKE $PRICE --rpc-url $RPC "${SIGNER[@]}"
    ;;
  launch)
    blockers=$(curl -s -X POST "$IMD_API/requests/check" -H 'Content-Type: application/json' \
      -d "{\"action\":\"launch.open\",\"input\":$(jq -c . launch.json)}" | jq -c '.blockers // .')
    if [[ "$blockers" != "[]" ]]; then
      echo "IMD check failed, nothing paid: $blockers" >&2
      exit 1
    fi
    cast send $INTAKE 'request(bytes32,bytes,(address,bytes4),address,uint256)' \
      "$(cast format-bytes32-string 'launch.open@launch-1')" "$(cast from-utf8 "$(jq -c . launch.json)")" \
      '(0x0000000000000000000000000000000000000000,0x00000000)' $IMD $PRICE \
      --rpc-url $RPC "${SIGNER[@]}"
    ;;
  *)
    echo "usage: launch/pay.sh build <owner> <feeRecipient> | approve | launch" >&2
    exit 1
    ;;
esac
