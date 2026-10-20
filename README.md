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
     the fee recipient**.
   - A world with stakes on only one side has no counterparty and is refunded with no fee.
6. **Void.** With no usable answer 30 days after `resolveTime`, anyone can call `voidMarket`: every stake is refunded.
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
  size, quorum, action id), activatable after a 3 day delay and applying to markets created afterwards, and (b) change the fee
  recipient. Each market keeps the configuration it was created with. There is no pause, no withdraw and no upgrade.
- **The oracle** is trusted as IMD documents it: the panel's honesty and the attester's key. The writer cannot forge
  an answer; a withheld one ends in a retry or a void. Answers are for moderate value and decisions that can wait.
- **Text** is printable ASCII without `"` or `\`, so the question needs no JSON escaping and the hash the contract
  computes equals the oracle's. `rules` must contain a space, because the oracle lowercases a definition that is
  exactly an address or a 32-byte hex string. Lengths: condition and outcome up to 280 bytes, rules up to 500.
- **Questions are public** and reach the oracle's agents as written. The oracle refuses ambiguous or unanswerable
  questions; such a market ends in a void.
- **Price changes.** Each market pays the Intake price it was created with. If the Intake raises its price, that
  market's asks revert and it is voided after 30 days.
- **Close before it is known.** Staking is open until `closeTime`, which the creator chooses (at or before
  `resolveTime`). A market whose condition or outcome becomes public before `closeTime` can be staked on with that
  knowledge, as in any prediction market; creators should close trading before either can be known. The frontend
  says so when a market is created.
- **Rounding.** Payouts round down; at most a few wei per market stay in the contract.

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
  owner configuration (including the action id and the creator's deposit cap) and a fuzzed conservation test.
- `test/OracleConformance.t.sol`: the protocol's conformance vector. The contract, deployed at the vector's address
  on the vector's chain, reproduces the protocol's EIP-712 digest, its callback selector is the canonical one, the
  protocol's own signature verifies against that digest, and a fresh answer from the vector's key is accepted as the
  Intake delivers it.
- `test/ConditionalsInvariant.t.sol`: random markets, stakes, asks, answers, failures, settlements, voids and claims;
  the contract stays solvent, conserves every IMD, and fees never exceed 3%.
- `test/ConditionalsFork.t.sol`: against Robinhood Chain, the real Intake accepts both asks and forwards 1 IMD.

## Frontend

`frontend/` is a Next.js site: browse markets as two diverging worlds, stake, create a market (with the oracle's
free pre-check), and follow resolution. Without a deployed address it runs a demo with sample markets.
