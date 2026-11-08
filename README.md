# Conditionals

Conditional prediction markets in IMD, settled by the IdentityMD oracle, on Robinhood Chain.

A market asks **"if CONDITION, will OUTCOME?"** and opens two worlds:

| | YES | NO |
|---|---|---|
| **World 0**: the condition happens | pool | pool |
| **World 1**: the condition does not happen | pool | pool |

Traders stake IMD in any of the four pools. Comparing the two worlds shows what the market thinks the condition does
to the outcome: "if the Clarity Act passes, ETH above $5k is 62%; if it doesn't, 31%".

## Lifecycle

1. **Create.** Anyone calls `createMarket(condition, outcome, rules, closeTime, resolveTime, maxBudget)` and deposits
   the cost of two oracle questions (2 x 0.5 IMD). `maxBudget` caps the deposit: if an oracle configuration activated
   meanwhile charges more, the call reverts instead of pulling it. What is not spent comes back at settlement or void.
2. **Stake.** `stake(marketId, world, side, amount)` until `closeTime`. Minimum 0.001 IMD.
3. **Ask.** From `resolveTime` anyone calls `requestResolution(marketId)`. The contract pays the IdentityMD Intake
   (`oracle.request@oracle-1`, the action id the market was created with) for two questions, the condition and the
   outcome, each judged as of `resolveTime`, with a panel of 5 agents and a quorum of 4. It writes the market id and its own address into each question, pins the
   question to an Ethereum block a few blocks behind the head, and stores the question's hash.
4. **Answer.** The Intake calls `onOracleResult`. An answer counts only if it is a `bool`, signed by the oracle's
   attester for this contract (EIP-712 domain `IdentityMD Oracle`, version `2`; the attester may be an EOA or a
   contract answering ERC-1271, such as the protocol's signer registry), for the exact question hash this contract
   stored, with at least the market's panel and quorum, `agreed >= quorum`, and not expired. A refusal or a
   panel that disagrees calls `onFailure`, which clears the ask; anyone can ask again, paying the 0.5 IMD. An ask with
   no reply can be repeated after one day.
5. **Settle.** Once both questions are answered, anyone calls `settle` (or just `claim`). The condition's answer
   picks the world that happened; the outcome's answer picks the winning side in it, in either world.
   - The world that did not happen is refunded in full.
   - In the world that happened, the winning side splits the pot minus **3%**: **2% is burned** (sent to
     `0x000000000000000000000000000000000000dEaD`, because IMD reverts on transfers to the zero address) and **1% goes to
     the fee recipient**. The fee is **capped at what the losing side staked** (split 2:1 the same way), so a winner
     never nets less than they staked: a 0.001 IMD counter-stake cannot turn a one-sided world into a 3% loss.
   - A world with stakes on only one side has no counterparty and is refunded with no fee.
   - The burn, the fee and the creator's unspent budget are pushed in the same transaction. If IMD refuses one of
     those transfers (its owner can block an address), the amount is credited to `owed` and that party collects it
     with `withdrawOwed()`; the stakers' settlement, void and claims go through regardless.
6. **Void.** With no usable answer 30 days after `resolveTime`, anyone can call `voidMarket`: every position is
   refunded at what it cost. In ConditionalsV2 each account gets back what it paid, fees excluded, for the shares it
   still holds (`netIn`), pro rata if the market is short, and the creator is paid last. Gains and losses already
   realised by selling or redeeming shares are not refunded (see "Void refunds" below). In a short void the capped
   refunds can add up to less than the pool: from 365 days after the void anyone can call `sweepVoid`, which pays
   the creator what is left, and refunds still unclaimed then lapse. A void that was not short has nothing to sweep
   and its refunds never lapse.
   A void waits while an unanswered question has an ask less than a day old still live, so an answer on its way
   cannot be voided away; `voidable(marketId)` says whether it would succeed now.

## What it uses from IMD

- **IMD** is the only currency: stakes, payouts, the creation deposit and the oracle payments.
- **The oracle**: every market buys two `oracle.request` questions onchain through the Intake, paid by the contract
  itself. Answers are verified onchain, bound to the question the contract asked.
- **Burn**: 2% of every settled pot is removed from supply.
- **The swarm** builds, audits and deploys the contract (IMD launch, `evm_contracts`).

## Trust and limits

- **No admin over markets.** The owner can only (a) propose a new oracle configuration (Intake, signer, price, panel
  size, quorum, action id), activatable after a 3 day delay and within the 7 days after it (`CONFIG_WINDOW`; a
  proposal not activated by then lapses and must be proposed again), applying to markets created afterwards, and
  (b) change the fee recipient. Each market keeps the configuration it was created with. There is no pause, no withdraw and no upgrade.
- **The oracle** is trusted as IMD documents it: the panel's honesty and the attester's key. The writer cannot forge
  an answer; a withheld one ends in a retry or a void. Answers are for moderate value and decisions that can wait.
- **Text** is printable ASCII without `"` or `\`, so the question needs no JSON escaping and the hash the contract
  computes equals the oracle's. `rules` must contain a space, because the oracle lowercases a definition that is
  exactly an address or a 32-byte hex string. Lengths: condition and outcome up to 280 bytes, rules up to 500.
- **Questions are public** and reach the oracle's agents as written. The oracle refuses ambiguous or unanswerable
  questions; such a market ends in a void.
- **Price changes.** An ask reads the Intake's live price (`priceOf`) and pays it, up to `MAX_PRICE` (10 IMD), so a
  price cut is not overpaid from the creator's budget. In ConditionalsV2 a price rise no longer strands a market: the
  budget is drawn down to zero and the caller of `requestResolution` pays only the shortfall. A retry is paid the
  same way, from the budget while it lasts. A live price of zero, above 10 IMD, or unreadable falls back to the
  market's snapshot price.
- **Void refunds (ConditionalsV2).** The contract keeps, per account and outcome, what the shares still held cost: a
  buy adds its cost, a stake adds its collateral spread over the three outcomes it keeps by their prices, and a sell
  or an exit releases the sold shares' share of it. A void refunds that sum (`netIn`) in full when the market can
  cover it, and the creator takes what is left. When it is short, the shortfall is shared pro rata over the cost that
  a position's value at the final prices does not back: an account with cost c and value v (shares times final
  prices, clipped at c) is paid `(v * shortfall + c * (pool - V)) / (refundBase - V)`, where V is the value of every
  position. The market always holds at least V (`makerBalance >= C(q) >= sum p_i q_i`), so a position worth its
  cost, such as a stake's complete sets, is refunded in full, and cost paid at prices pumped on several outcomes at
  once, of which only one can pay, takes the loss. No account is ever refunded more than its cost, so a position
  worth more than it cost at the final prices is refunded at cost, never at a profit taken from other accounts;
  what this leaves unclaimed in a short void goes to the creator through `sweepVoid` a year after the void, when
  any refund not yet claimed lapses (`claim` then returns 0). What a sale fetched is the seller's, gain or loss: a loss one
  account realised against the maker is IMD another account took out, so it is not a claim on the seed or on other
  accounts' refunds. `claim` returns 0 for an account with nothing to claim.
- **Spread bound (ConditionalsV2).** No trade, sells included, may leave an outcome more than 20 b below the top
  outcome, so every outcome keeps a price. `exit` sells only what fits; any shares it cannot sell stay with the
  account (each is priced under about 2e-9 IMD) and a later `exit` or `sell` can sell them once the market moves.
- **Close before it is known.** Staking is open until `closeTime`, which the creator chooses (at or before
  `resolveTime`). A market whose condition or outcome becomes public before `closeTime` can be staked on with that
  knowledge, as in any prediction market; creators should close trading before either can be known. The frontend
  says so when a market is created.
- **Rounding.** Payouts round down; at most a few wei per market stay in the contract.
- **Answer freshness.** An attestation is refused when expired or when `issuedAt` is more than 5 minutes ahead of
  the chain's clock, as the protocol's own consumer refuses it.

## Contracts

| File | What |
|---|---|
| `src/Conditionals.sol` | Markets, stakes, oracle asks and answers, settlement, claims |
| `src/interfaces/IIntake.sol` | The Intake's `requestWithFailure` |
| `src/interfaces/IOracleAttestation.sol` | The oracle's signed answer |

Constructor: `(address owner, IERC20 imd, IIntake intake, address oracleSigner, address feeRecipient)`.
On Robinhood Chain: IMD `0x5f7bb59365ce557c26dbcaa4ee9d39a4b95b7127`, Intake
`0xa43e6f75ee006411f79ac1c84120606c2330de82`, oracle attester `0x5598aa9146215bc13eb26f2c692ad1461fd32982`.
The constructor makes no external calls.

### ConditionalsFacts (fact markets)

`src/ConditionalsFacts.sol` runs the encyclopedia's perpetual TRUE/FALSE markets, settled only by `challenge` and
the oracle's answer. It takes the same five constructor arguments as above. Things to know before trading:

- **Open rounds keep their oracle configuration.** A round uses the configuration (Intake, signer, action, price,
  panel) that was active when it opened, and the owner cannot change it afterwards. If the protocol rotates its
  signer or stops selling the action, a round opened before the rotation can no longer settle: its challenges stop
  being answered (or refused), trading resumes after each `ASK_TIMEOUT`, and its traders' only exit is selling back
  to the maker at the LMSR price. Nothing is lost outright, but a 1 IMD redemption is no longer reachable for that
  round. This is the brief's deliberate choice (the owner cannot touch open rounds).
- **Creator text is quoted.** The claim and the rules reach the oracle's panel in double quotes (which neither may
  contain), and the question tells the panel they are the creator's untrusted text to judge, not instructions.
- **Dust can always be sold.** A whole holding below 0.001 shares is sold back; when it is worth less than the
  maker's rounding margins (a few wei) it is taken back for nothing, so it never blocks `closeRound`.

## Tests

```sh
forge build
forge test                                  # unit, fuzz and invariant suites, no RPC
FORK_ROBINHOOD=1 forge test --mc Fork       # the real Robinhood Chain Intake takes the contract's asks
```

- `test/Conditionals.t.sol`: the question document byte for byte, the request body, a question hash checked against
  the live oracle API (`POST /requests/quote` returned the same hash), signature and binding checks (wrong signer,
  an ERC-1271 signer registry, another question, another window, another market, weak panel, expired, wrong type,
  malformed answer, tampered fields, replay, calls not from the Intake), callback gas under the Intake's 200,000
  limit, every settlement path in both worlds, one-sided worlds, failures and retries, voids and the void guard,
  owner configuration (including the action id, the creator's deposit cap and the proposal's activation window),
  the fee cap at the losing pool (unit and fuzz), deferred payments when IMD blocks the fee recipient or the
  creator, the live-price read, the `issuedAt` tolerance, and a fuzzed conservation test.
- `test/OracleConformance.t.sol`: the protocol's conformance vector. The contract, deployed at the vector's address
  on the vector's chain, reproduces the protocol's EIP-712 digest, its callback selector is the canonical one, the
  protocol's own signature verifies against that digest, and a fresh answer from the vector's key is accepted as the
  Intake delivers it.
- `test/ConditionalsInvariant.t.sol`: random markets, stakes, asks, answers, failures, settlements, voids and claims;
  the contract stays solvent, conserves every IMD, and fees never exceed 3%.
- `test/ConditionalsFork.t.sol`: against Robinhood Chain, the real Intake accepts both asks and forwards 1 IMD.
- `test/ConditionalsV2Lifecycle.t.sol`: two markets driven through trades, asks, answers, failures, settlement,
  void, claims, fee withdrawals and `sweepVoid`; the contract holds everything it owes, claims are exact, a sweep
  pays exactly a short void's leftover once and only after a year, and no refund is paid after it.
- `test/ConditionalsV2Launch.t.sol`: the `evm_contracts` launch rehearsed with no RPC: both contracts deployed by
  CREATE2 from a factory stand-in on an empty chain 4663 with the launch's constructor arguments, every value
  checked, the owner not the factory, both runtimes under 24,576 bytes with no forbidden opcode reachable.

## Frontend

`frontend/` is a Next.js site: browse markets as two diverging worlds, stake, create a market (with the oracle's
free pre-check), and follow resolution. Without a deployed address it runs a demo with sample markets.
