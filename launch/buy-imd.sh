#!/usr/bin/env bash
# Buys exactly AMOUNT IMD (default 0.5) with ETH on the IMD/ETH Uniswap v4 pool on Robinhood Chain
# (ETH/IMD, 1% fee, tick spacing 100, no hook) through a Uniswap PoolSwapTest router. Unused ETH is refunded.
# Usage: launch/buy-imd.sh [amount-in-IMD] [max-eth]
# Signs with PRIVATE_KEY from ~/.conditionals/deployer.env. RPC can be overridden for a fork rehearsal.
set -euo pipefail

RPC=${RPC:-https://rpc.mainnet.chain.robinhood.com}
ROUTER=0x0a8c4623A15eE743357855a28F07d14d37DF268B
IMD=0x5f7bb59365ce557c26dbcaa4ee9d39a4b95b7127
MIN_SQRT_PRICE_PLUS_ONE=4295128740

# shellcheck disable=SC1090
source ~/.conditionals/deployer.env
amount=$(cast to-wei "${1:-0.5}")
max_eth=$(cast to-wei "${2:-0.0012}")

before=$(cast call $IMD 'balanceOf(address)(uint256)' "$ADDRESS" --rpc-url "$RPC" | awk '{print $1}')
# swap((currency0,currency1,fee,tickSpacing,hooks),(zeroForOne,amountSpecified,sqrtPriceLimitX96),(takeClaims,settleUsingBurn),hookData)
# A positive amountSpecified is exact output.
cast send $ROUTER \
  'swap((address,address,uint24,int24,address),(bool,int256,uint160),(bool,bool),bytes)' \
  "(0x0000000000000000000000000000000000000000,$IMD,10000,100,0x0000000000000000000000000000000000000000)" \
  "(true,$amount,$MIN_SQRT_PRICE_PLUS_ONE)" '(false,false)' 0x \
  --value "$max_eth" --rpc-url "$RPC" --private-key "$PRIVATE_KEY" >/dev/null
after=$(cast call $IMD 'balanceOf(address)(uint256)' "$ADDRESS" --rpc-url "$RPC" | awk '{print $1}')
echo "bought $(cast from-wei $((after - before))) IMD; balance $(cast from-wei "$after") IMD, $(cast balance "$ADDRESS" --rpc-url "$RPC" -e) ETH"
