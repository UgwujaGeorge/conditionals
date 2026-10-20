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

## Revision: the independent review's findings

Each finding was reproduced on the accepted tree before anything changed. Answers are in `.imd-responses.json`.

### b57733eb (medium) - a 0.001 IMD counter-stake charged the 3% fee on the winners' principal: fixed

Reproduced: the proof `Proof_b57733eb72d5.t.sol` failed on the accepted tree with `970000970000000000000 <
1000000000000000000000`. `_settle` charged `BURN_BPS + BUILDER_BPS` on the whole pot whenever both pools were
non-empty, so a MIN_STAKE on the empty side of a one-sided world cost the winners 3% of their own stake and paid the
fee recipient 1% of it. The fee is now capped at the losing pool (`fee = min(3% of pot, losing pool)`, split 2:1
between the burn and the fee recipient as before), the first of the finding's options: the brief's 3% of the pot
stays wherever the losing side covers it, and a winner never nets less than they staked. The invariant
`invariant_feesBounded` (fees at most 3% of what was staked) still holds.

The proof itself cannot pass against any fix: its lines 104-106 assert the defective amounts (`paid ==
970000970000000000000`, the fee recipient paid 10.00001 IMD) and line 109 asserts `paid >= 1000 IMD`. On this tree it
fails at line 104 with `1000000000000000000000 != 970000970000000000000`, which is the fixed payout. The finding is
answered `disputed` for that reason, with the fix in place and the scenario covered by the suite.

- `src/Conditionals.sol`: `_settle`; header comment.
- `test/Conditionals.t.sol`: `test_feeIsCappedAtTheLosingPool` (the reviewer's scenario: the whale receives exactly
  1000 IMD, the fee is the 0.001 IMD dust), `test_feeIsThreePercentOfThePotWhenTheLosingPoolCoversIt` (above and
  exactly at the cap), `testFuzz_winnerNeverNetsLessThanStaked`.
- `frontend/src/lib/market.ts` (`worldFee`, `multiple`, `estimatePayout`), `frontend/src/hooks/useDemoMarkets.ts`
  (demo settlement) and `frontend/src/components/MarketDrawer.tsx` (fee copy) mirror the cap. `README.md` step 5.

### 3425133b (low) - third-party pushes inside the stakers' transaction: fixed

Reproduced with a mock IMD whose `_update` reverts for a blocked address (the live IMD answers `blocked(address)`):
with the fee recipient blocked, `settle` and every `claim` reverted and `voidMarket` reverted `NotVoidable`; with
the creator blocked and the budget unspent, `voidMarket` reverted. The burn, the fee and the budget return now go
through `_push`, which tries the transfer and, if IMD refuses it, credits `owed[to]` and emits `PaymentDeferred`
instead; the party collects it with `withdrawOwed()`. A staker's own claim is still a plain `safeTransfer`: IMD
refusing a staker reverts that staker's claim only.

- `src/Conditionals.sol`: `owed`, `withdrawOwed`, `_push`, `_settle`, `_returnBudget`, events `PaymentDeferred`
  and `OwedWithdrawn`.
- `test/utils/Mocks.sol`: `MockIMD.setBlocked`. `test/Conditionals.t.sol`:
  `test_blockedFeeRecipientDoesNotBlockSettlement`, `test_blockedCreatorDoesNotBlockVoid`,
  `test_blockedStakerOnlyBlocksTheirOwnClaim`. `README.md` step 5.

### d2cd6ea6 (low) - asks paid the snapshot price, never the live one: fixed for a lower price

Reproduced: with the Intake's price at 0.25 IMD the two asks still paid 1 IMD and the creator got nothing back.
`_askPrice` now reads `priceOf(action, imd)` on the Intake and pays the live price when it is below the market's
snapshot; the unspent budget comes back at settlement or void. The read is a `try`: an Intake without `priceOf` (a
mock, an older version) is charged the snapshot, so a buyer's mock need not implement it. `priceOf` is declared in a
separate `IIntakePrice` interface for the same reason (the proofs' mocks implement `IIntake`).

A live price above the snapshot still reverts at the Intake and the market voids at `voidAfter`, as the README
documented: the alternative, pulling the difference from the caller of `requestResolution`, would charge a
volunteer an amount the Intake's owner sets, the pattern finding 30115fb4 asked to remove from `createMarket`.
The caller never pays more than the snapshot (bounded by `MAX_PRICE`).

- `src/Conditionals.sol`: `_askPrice`, `_ask`. `src/interfaces/IIntake.sol`: `IIntakePrice`.
- `test/utils/Mocks.sol`: `MockIntake.price`, `setPrice`, `priceOf`, `setPriceOfReverts`.
  `test/Conditionals.t.sol`: `test_askPaysTheLivePriceWhenItIsLower`, `test_askPaysTheSnapshotWithoutALivePrice`,
  `test_askRevertsWhenTheLivePriceIsHigher`. `README.md` "Price changes".

### 931492ce (low) - no `issuedAt` check: fixed

Reproduced: an attestation with `issuedAt` a year ahead was accepted. `onOracleResult` now refuses
`a.issuedAt > block.timestamp + ISSUED_AT_TOLERANCE` (5 minutes, the protocol consumer's constant) alongside the
expiry check. The check stays inline rather than inheriting `OracleAttestationConsumer`, because the contract
verifies against each market's snapshotted signer, not one owner-settable signer.

- `src/Conditionals.sol`: `ISSUED_AT_TOLERANCE`, `onOracleResult`.
- `test/Conditionals.t.sol`: `test_rejectsIssuedAtInTheFuture` (a year ahead and tolerance + 1 refused, exactly the
  tolerance accepted). `README.md` "Answer freshness".

### 17efe772 (low) - a pending configuration never expires: fixed with an activation window

Reproduced: a proposal could be activated months after its delay, in the block a market was created. A proposal is
now activatable only between `CONFIG_DELAY` and `CONFIG_DELAY + CONFIG_WINDOW` (7 days, a value the brief leaves
open) after it was proposed; later it lapses (`ConfigExpired`) and must be proposed again, so every configuration a
creator can meet was announced at most 10 days earlier. The finding's other option, a configuration pin in
`createMarket`, was not taken: it changes the creator-facing ABI again for an exposure that is the creator's own 1
IMD budget, and the brief gives the owner the choice of oracle for future markets.

- `src/Conditionals.sol`: `CONFIG_WINDOW`, `ConfigExpired`, `activateOracleConfig`.
- `test/Conditionals.t.sol`: `test_pendingConfigExpires`. `README.md` "No admin over markets".

### 427f0607 (info) - `onFailure` NatSpec said RETRY_DELAY: fixed in the comment

Reproduced: `_askable` allows an immediate re-ask after a failure, as the README and
`test_failureThenRetryPaidByCaller` say; only the NatSpec said otherwise. The comment now matches the code; the
caller pays the retry, so nobody else loses by an immediate re-ask.

### f2b2f269, 1b5229b4, 167b3d1e (info) - not changed

- Rounding dust: reproduced (at most winners - 1 wei per market, documented in the README). Paying the remainder to
  the last claimant needs a count of unclaimed winners per market; not worth the storage for wei.
- `claim()` by a non-staker settles then reverts `NothingToClaim`: reproduced; gas only, and `settle()` is the
  function for settling without a payout. A `claim` that returns 0 for some callers and reverts for others would be
  a worse interface.
- `feeRecipient` read at settlement: reproduced; the brief gives the owner `setFeeRecipient`, the amount is fixed
  by the contract and stakes are untouched. With b57733eb fixed the recipient has no lever on one-sided worlds.

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
66 tests pass (60 unit and fuzz, 4 conformance, 1 invariant suite of 3 invariants, 1 fork test that returns without
an RPC). The fork test (`FORK_ROBINHOOD=1`) was not run here; it needs the network. Runtime size 19,654 bytes.
The held proof `Proof_b57733eb72d5.t.sol` fails on this tree at its own line 104 (see b57733eb above).
`frontend/src/lib/abi.ts` was regenerated with `node frontend/scripts/gen-abi.mjs`.
