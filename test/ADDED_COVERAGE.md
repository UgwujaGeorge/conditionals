# Additional regression coverage

The application sources, deployment arguments, configuration and existing conformance vectors are unchanged.

- `ConditionalsV2Atomicity.t.sol` checks complete rollback when the second oracle request fails, the Intake
  returns a duplicate id, the caller cannot fund an oracle shortfall, a sponsored stake cannot collect payment,
  an exit misses its slippage bound, or a token refuses a sale/fee withdrawal. It also changes each of the 15
  attestation fields after signing and tests signatures for another consumer or chain. Rejected answers leave
  the legitimate pending answer deliverable under the Intake's 200,000 gas limit.
- `ConditionalsV2PortfolioInvariant.t.sol` runs 256 sequences of 80 calls across three markets with liquidity
  parameters 0.5, 20 and 100 IMD. Four accounts trade, including paying for another account. Fee recipients rotate
  (including to the creator), the burn recipient can reject transfers, and debts are withdrawn. The assertions
  reconcile exact custody, shares, cost bases and a fee ledger derived from actual cash flows. Unexpected revert
  reasons fail the invariant. After each sequence, all markets are voided, every claim is exercised, short-void
  leftovers are swept after the delay, and fees are withdrawn; the contract must then hold zero IMD.
- `utils/LmsrReference.sol` computes the LMSR cost using independent high precision Taylor series rather than
  Solady's approximations. Frozen Python Decimal vectors check neutral, saturated, translated, fractional and
  near-equal positions. The portfolio invariant and existing arithmetic fuzz tests check the full
  `makerBalance >= C(q) >= q[i]` guarantee. The reference is test-only and requires no FFI or Python at runtime.
- `ConditionalsZap.t.sol` additionally checks second-hop partial fills, USDG settlement failures, refused output
  transfers, both slippage limits and exact-input accounting with six-decimal USDG units (1,000 fuzz runs).
- `ConditionalsV2Fork.t.sol` uses Robinhood block **102702745**. It exercises the real Intake, IMD and both
  PoolManager routes. Failed live swaps must restore balances and finite allowances; a subsequent successful
  swap must match a clean execution from the same state, including its pool price effects.

Run the complete suite with the assignment's seed:

```sh
FOUNDRY_FUZZ_SEED=0x1603cce38c873662a78756267580099c44a77c9c5fe92d6a89347de0a67f480e forge test
```

Fork setup reads `vm.envOr("ROBINHOOD_RPC_URL", string(""))` and passes that value directly to
`vm.createSelectFork` at the pinned block. It skips only when the variable is empty. No endpoints, credentials,
new dependencies, production state changes, or source/configuration edits are needed by these additions.

## Fork RPC diagnostic

The reported local-check failure was an unsupported `eth_getAccountInfo` request, rather than a
failing Solidity assertion. All 13 fork tests passed again at block **102702745**, with zero skips,
including a run with Forge's storage cache disabled:

```sh
FOUNDRY_FUZZ_SEED=0x1603cce38c873662a78756267580099c44a77c9c5fe92d6a89347de0a67f480e \
  forge test --match-path test/ConditionalsV2Fork.t.sol --no-storage-caching -vv
```

Forge 1.8.3 (`cae51ad458f6abb64852b7709eb784352429825d`) uses `foundry-fork-db` from
`foundry-core` revision `327739f0d2b848725b462271276f27aecd8b8ff9`. Its account-fetch routine
probes the optional `eth_getAccountInfo` method and falls back to `eth_getBalance`,
`eth_getTransactionCount` and `eth_getCode` at the same pinned block when the probe fails.
See the [version-pinned backend implementation](https://github.com/foundry-rs/foundry-core/blob/327739f0d2b848725b462271276f27aecd8b8ff9/crates/fork-db/src/backend.rs#L355-L453).

Consequently, the provider's response that this method is unavailable does not establish that
archive state is unavailable. The successful fork run exercises real Intake payments, both live
PoolManager routes, burn accounting and rollback after rejected swaps. A checker that counts the
unsupported capability probe as an archive-state failure can reject these successful tests.
That classification belongs to the RPC/check infrastructure; changing application assertions,
skipping the fork, replacing live dependencies, or changing its block would not repair it.
The existing fork and offline test implementations are preserved.

Validation also completed with `forge build` and the full seeded
`forge test --no-storage-caching --summary` run: **161 passed, 0 failed, 0 skipped** across
11 suites. This includes the protocol conformance vectors and all three invariant suites;
the portfolio campaign executed 20,480 handler calls without a revert. Compiler artifacts
and local logs were directed to `test/scratch/`, which is excluded from submission.

## ConditionalsFacts additions

- `ConditionalsFactsInvariant.t.sol`: 256 runs of 64 random calls each, over three facts (b = 0.1, 10 and 100 IMD).
  The calls are buys, buyFor, partial and whole sells, challenges, correctly signed answers (delivered through the
  mock Intake under 200,000 gas), forged answers (wrong key or wrong question), failures, timeouts, closes, new
  rounds, redemptions, withdrawals, fee-recipient rotation and a burn address that refuses IMD. Invariants:
  - The IMD held always equals the sum of every round's makerBalance plus every `owed`.
  - In unsettled rounds, q[i] equals the shares held. A settled round's maker holds exactly the unredeemed winning
    shares.
  - In live rounds, makerBalance >= C(q) >= max q[i]. C(q) comes from an independent Taylor-series reference.
  - The spread stays <= 20b. Earlier rounds are always finished, and finished rounds never reopen.
  - A round settles only after a valid answer to its live ask.
  - The burn and oracle-spend totals reconcile with balances.
  - No unexpected reverts. `afterInvariant` settles everything, pays everyone and leaves only dust.
- `ConditionalsFactsFailurePaths.t.sol`:
  - The oracle-consumer conformance vector, run against ConditionalsFacts itself: the protocol's digest and
    signature, and the canonical callback and failure selectors.
  - Binding: another fact's or another ask's question is refused. Signatures for another consumer, another chain or
    domain version 1 are refused, and so are malformed signatures.
  - Quorum and answer-encoding edge cases.
  - The exact timeout boundary. Late answers and failures after a close or a re-challenge change nothing.
  - Duplicate Intake ids are refused atomically. Price fallbacks charge nothing on refusal.
  - Owner limits: no effect on open rounds, config validation bounds, activation-window edges, two-step ownership.
    Fees already owed stay with the old fee recipient after a change.
  - Lifecycle refusals.
  - Fuzzed edges: buy spend, exact fee split, round trips never profit, settlement always covers the winners.
  - ERC-1271 callback gas.
- Reported, not asserted (`.imd-findings.json`): whole-holding sales of the cheap side revert `PriceLimit` once the
  other side holds more than 20b shares beyond them.
