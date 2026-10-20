# Adaptation for the Robinhood Chain launch

Launch kind `evm_contracts`, chain 4663. One contract, `src/Conditionals.sol:Conditionals`, constructor
`(address owner, IERC20 imd, IIntake intake, address oracleSigner, address feeRecipient)`, all static values the
manifest step fills (`$owner` for the owner; the brief names the other four). The constructor makes no external call,
takes no ETH, and the contract has no proxy, DELEGATECALL, SELFDESTRUCT, pause, mint or admin power over stakes.
`bytecode_hash = "none"` was already set. Runtime 18,661 bytes, init code 20,718 bytes (`forge build --sizes`).

The launch rules required no change to the contract's constructor, ownership or configuration. Every change below
comes from an audit finding that reproduced against the code as it arrived, and each is covered by a test.

## Audit findings

### b48a22f9 (high) - world 1 was always settled to NO: fixed

Reproduced: the audit's proof (`.imd/reads/proofs/Proof_b48a22f91316.t.sol`) failed on the original code and
passes on this one (run from `test/scratch/`). `_settle` set `side = NO` whenever the condition was false,
`_settleable` was true on the condition alone and `_askable` refused to ask the outcome once the condition was false,
so every world-1 YES staker forfeited to NO whatever the outcome, with a 3% fee charged on a result the oracle never
gave. The README table, the frontend and `impact()` all present world-1 YES as "the outcome happens although the
condition does not", and the brief says "in the world that happened the winning side splits the pot", so the fix is
the audit's option (a): both questions are always asked and both answers are needed; the condition picks the world,
the outcome picks the winning side in either world.

- `src/Conditionals.sol`: `_askable` no longer skips the outcome; `_settleable` needs both answers; `_settle` takes
  the side from the outcome in both worlds. Header comment updated.
- `test/Conditionals.t.sol`: `test_conditionFalseSettlesWithoutOutcome`, which encoded the bug, is replaced by
  `test_conditionFalseWaitsForTheOutcome`, `test_conditionFalseOutcomeYes`, `test_conditionFalseOutcomeNo` and
  `test_world1YesWinsWhenOutcomeTrue` (the audit's reproduction). `test_failureThenRetryPaidByCaller` now answers the
  outcome too before settling.
- `README.md` step 5, `frontend/src/lib/market.ts` (`settleable`, `askable`, `askCost`),
  `frontend/src/hooks/useDemoMarkets.ts` (demo settlement) and `frontend/src/components/MarketDrawer.tsx` (the
  resolution steps) say and do the same. The frontend was not built here (no `node_modules`); the edits are the
  minimal mirror of the contract's rules.

### 3c993124 (low) - void while an answer is in flight: fixed

Reproduced: with an ask live, `voidMarket` succeeded one second after `voidAfter` and the answer that landed next
was ignored. `voidMarket` now refuses while an unanswered question has an ask younger than `RETRY_DELAY` (one day)
still live; after that the ask counts as lost, as it already did for retries. Since `requestResolution` is refused
after `voidAfter`, a void is delayed by at most one day. New view `voidable(marketId)`.

- `src/Conditionals.sol`: `_voidable`, `voidable`, `voidMarket`.
- `test/Conditionals.t.sol`: `test_cannotVoidWhileAnAskIsLive`, `test_voidAllowedOnceTheLiveAskIsStale`;
  `test_cannotVoidASettleableMarket` checks the view. `test/ConditionalsInvariant.t.sol`: the handler voids through
  `voidable`. `frontend/src/lib/market.ts`: `voidable`, used by `stage`.

### bf75158c (low) - the action id was a constant: fixed

Reproduced: `ORACLE_ACTION` was hard-coded, so a retired action version could not be rotated in and every market
would end in a void. `OracleConfig` gains `bytes32 action` (validated non-zero), snapshotted per market like the
rest of the configuration and passed to `requestWithFailure`. The constructor starts at `oracle.request@oracle-1`
(`ORACLE_ACTION` stays as that default). The owner rotates it on the same 3 day path; open markets keep theirs.

- `src/Conditionals.sol`: `OracleConfig.action`, constructor, `_ask`, `_validateConfig`.
- `test/Conditionals.t.sol`: `test_rotatedActionIsUsedByNewMarkets`, `test_oracleConfigBounds` (zero action),
  `test_createMarketTakesBudgetAndSnapshotsConfig`; `test/utils/Fixture.sol` `_config()`.

### d83d44e0 (low) - ECDSA-only signer check: fixed

Reproduced: `tryRecover` against an EOA refuses any ERC-1271 signer, so the protocol's signer registry could never
answer a market. Verification now uses OpenZeppelin `SignatureChecker.isValidSignatureNow`, which accepts an EOA's
signature or a contract's ERC-1271 answer, as the protocol's `OracleAttestationConsumer` does. The second half of
the suggestion, also accepting the current configuration's signer for older markets, was not taken: the brief
says the owner "cannot touch stakes, answers or open markets", and a signer rotation that applied to open markets
would let the owner settle them with a key of its choice after 3 days. Each market keeps its own signer; a
registry is the rotation path (`test_rotatedSignerCannotAnswerAnOlderMarket` pins this).

- `src/Conditionals.sol`: import and the signature check in `onOracleResult`; `attestationDigest` is public.
- `test/Conditionals.t.sol`: `test_acceptsAnErc1271SignerRegistry` (rotation inside a registry, refusal of an
  unlisted key, under the Intake's gas limit), `test_rejectsWrongSigner` (empty and garbage signatures),
  `test_rotatedSignerCannotAnswerAnOlderMarket`. `test/utils/Mocks.sol`: `MockSignerRegistry`.

### 30115fb4 (low) - createMarket pulled 2 x price with no cap: fixed

Reproduced: with a 10 IMD price activated in the same block, `createMarket` pulled 20 IMD from a creator who
approved the maximum. `createMarket` takes a sixth argument, `maxBudget`, and reverts `BudgetTooHigh(budget,
maxBudget)` when the active configuration charges more.

- `src/Conditionals.sol`: `createMarket`, error `BudgetTooHigh`.
- `test/Conditionals.t.sol`: `test_createRejectsBudgetAboveTheCreatorsCap`; every other call site passes the
  deposit it expects. `test/ConditionalsFork.t.sol`, `test/ConditionalsInvariant.t.sol` likewise.
  `frontend/src/hooks/useLiveMarkets.ts` passes the 1 IMD deposit it shows.

## Added for the oracle-consumer reference

- `test/OracleConformance.t.sol`: the protocol's conformance vector adapted to this contract. Deployed at the
  vector's address on chain 11155111, the contract reproduces the protocol's digest
  (`0x95fefa8b...325c`), its callback selector is `0x510379c7`, the protocol's own signature verifies against that
  digest the way the contract verifies it, and a fresh bool answer from the vector's key is accepted as the Intake
  delivers it (the vector's `bytes32[]` answer is refused by design, as the reference allows). This needed the public
  `attestationDigest` view above. The existing live-API question-hash vector is unchanged and still passes.
- `frontend/src/lib/abi.ts` regenerated with `node frontend/scripts/gen-abi.mjs` from the new build.

## Not changed

- Constructor, ownership (`Ownable2Step` with the owner as an argument), fee split, burn address, panel and quorum
  defaults, question document and request body (the live-API hash vector pins them), callback selectors.
- `launch/` scripts and `launch/launch.template.json` are the requester's own tooling; no `launch.json` is written
  here, as the manifest step owns it.
- `foundry.toml`, `remappings`, `lib/`, `.gitmodules` and lockfiles: untouched, as required.

## Checks run

`forge build` and `forge test` with `FOUNDRY_FUZZ_SEED=0x454e988217fa2b344b583d22689e3faa5b48f3f8dea6fa7a68e7caa6cf942db6`:
56 tests pass (49 unit and fuzz, 4 conformance, 3 invariants, 1 fork test that returns without an RPC). The fork
test (`FORK_ROBINHOOD=1`) was not run here; it needs the network.
