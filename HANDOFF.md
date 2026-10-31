# Handoff: Conditionals

Last updated: 2026-10-31, 11:50 WAT. Separate entry from GAMMA (`~/projects/imd`). GitHub and Vercel: **UgwujaGeorge** (not
haileymarshall). Push with `gh auth token --user UgwujaGeorge`; do not switch the active gh account.

## LATEST HANDOFF SESSION: 2026-10-31 (read this first)

### UPDATE 2026-10-31, 19:50 WAT: v2 IS LIVE WITH 4 MARKETS (launch 2786). This block overrides everything below.

- ConditionalsV2 `0xd8e4baf371abc9a36611543386f68e0df122fcf0`, ConditionalsZap `0x750a28557a6263681f0cb9612cc86cc6f3a7476d`. Site at conditionals.xyz runs on them from `main`.
- Job `3ecec030-b2ed-4059-8ebf-38a09626e73c`, launch `4edfea53-c4be-494b-a84d-e7b5776d6861`, no findings on the first judge pass. Delivered commit `1976c73`, no `src` change. Manifest at `launch/2786-manifest.json`.
- Markets 1 to 4 created from `launch/markets.json`, text read back from the chain and exact. The user set BTC to 75000 in markets 1 and 4. `b` 1.44 IMD, seed 1.996 IMD each. Market 1 closes Dec 9 00:00 UTC, the others Dec 31 00:00 UTC, all resolve from Jan 1 2027 12:00 UTC.
- Real bets from the wallet: ETH through the zap on market 1, USDG through the zap on market 2, one `sell`, one `exit` on each. Positions went to zero and prices back to 25%. The zap kept nothing.
- Wallet after the tests: 3.19 IMD, 0.00108 ETH. It is owed 0.0035 IMD in fees, claimable from the contract.
- Tests: 154 pass offline. The fork suite needs a recent `FORK_BLOCK` on the public RPC: 12 of 13 pass, `test_fork_launchArgumentsAndDependencies` fails only in that setup.
- IMD's pre-check returns `not_answerable` for any future-dated question. Past-dated versions of most of the wording had no blockers; the 75000 condition in market 4 was not tested on its own.
- Still open: which film to post, and recapturing it with the real markets (videos are no longer blocked by the bets).

**The user's decision: relaunch v2 through IMD with another 0.5 IMD when they get back.** Nothing is running and nothing has
been paid since the park. Start with step 1 below as soon as they say to continue. `PROGRESS.md` has the plain-language
history, and everything further down this file is older history: where it conflicts, this section wins.

### State

| What | Status |
|---|---|
| Live site | https://conditionals.xyz, still v1, from `main` at `825ee9f` |
| Work branch | `v2`, pushed, git tag `handoff-latest` |
| V1 contract | `0xc8cc656b71dd77ae1e29b0bc7890edd110e73255`, 1 market, holds only the 1 IMD oracle deposit, so no trader funds |
| V2 contracts | **Not deployed.** IMD launch 2765 parked; the fix is ready and unaudited |
| Wallet | `0x63BCf2d1483c7628d7D53704ff9c8199Dc28d907`: 15.5 IMD, 0.0015 ETH, Intake allowance 0. Key in `~/.conditionals/deployer.env` |
| Budget | 0.5 IMD launch + 4 markets x (1 IMD oracle + ~2 IMD seed) = 12.5 IMD, leaving 3 IMD |

**Do not merge `v2` into `main` before v2 is deployed.** `DEPLOYED` and `DEPLOYED_ZAP` in `frontend/src/lib/config.ts` are unset on
`v2`, so the live site would fall back to demo mode.

### What happened to launch 2765

Paid 06:45 WAT, delivered 10:52, parked 10:54: about 4 hours. Job `81264d12-a201-4065-b9ff-c8df33483dfe`, launch
`f5047328-73e5-40b2-8e96-1610c79e7549`, delivered commit `a03596c` (merged into `v2`), manifest archived at
`launch/2765-manifest.json`. Payment tx `0x0ed9be336c67e29c184f4a1adae5cadb7b331af07bf1ddc04053e09357adf98e`. The 0.5 IMD is lost.

| Severity | Finding | Status |
|---|---|---|
| Critical | `buy()` cast `int256(shares)` wrapped, crediting free shares; about 0.001 IMD could drain a market. My bug, my tests missed it | Fixed by the swarm |
| High | Void dilution: cooperating accounts wash trade, then a void pays them from the seed and honest stakers | Fixed by the swarm (per-outcome cost basis, value and cost blend) |
| Medium | A short void could refund above cost | Fixed by the swarm (capped at cost) |
| Medium | The capped refunds leave part of the pool stuck forever. **This parked it** | Fixed by me, `sweepVoid`, not yet audited |

What this taught us about IMD:
- The judge sent the work back 3 times, then the launch parked with a medium open. Assume 3 rounds of fixes per launch.
- **Findings are public while it runs:** `GET https://api.imd.fun/jobs/<job>/submissions`, judge entries have `.findings` and `.summary`.
- After the job completes, `GET /launches/<id>` shows `assembling`, then `parked` with `parkedReason`, or live.

### Contract state (branch `v2`)

- `src/ConditionalsV2.sol`, 24,269 bytes at optimizer_runs 1, **307 bytes spare**. `src/ConditionalsZap.sol`, 3,646 bytes. V1 is in `legacy/v1`, not built.
- `sweepVoid`: after a short void, from 365 days after the void, pays the creator whatever is left of the refund pool. Refunds unclaimed at
  the sweep lapse; late claims work until somebody sweeps. A void that was not short has no leftover and never lapses. `voidAfter` becomes the time of the void.
- Removed to fit: the `conditionals` view, the `pendingOracleConfig` getter, `totalCreatorFees`, and public getters for 7 constants. The site uses none of them.
- Fee: 2% per maker trade: half to the market's creator, 67/200 burned, 33/200 to the fee recipient. Claims are free.
- Tests: 129 pass at 1,024 fuzz runs. Fork tests need `ROBINHOOD_RPC_URL`, and the public RPC has no archive for the pinned `FORK_BLOCK`, so for a local run set
  `FORK_BLOCK` to a recent block and put it back. 10 of 11 then pass. `test_fork_launchArgumentsAndDependencies` fails only in that setup, because forge reports the
  L2 number as `block.number`. On the real chain a contract sees the Ethereum block number: checked 2026-10-31, 26,312,176 against Ethereum's head.
- `launch/launch.template.json` tells the swarm what launch 2765 settled and which designs are deliberate.

### Step 1: relaunch (costs 0.5 IMD)

```bash
cd ~/projects/conditionals && git checkout v2
W=0x63BCf2d1483c7628d7D53704ff9c8199Dc28d907
launch/pay.sh build $W $W   # pins HEAD, so commit first; launch.json is gitignored
launch/pay.sh approve       # lets the Intake pull 0.5 IMD
launch/pay.sh launch        # runs IMD's free check and pays only with no blockers
```

Then follow it:
- `curl -s https://api.imd.fun/intake/4663/<tx> | jq '.entries[0].admission.result.jobId'` gives the job.
- Put the new job id in `~/projects/conditionals-video/watch.sh` and run it in the background.
- When the job completes, read `.launch.id` from `/jobs/<job>`, put it in `watch-launch.sh` and run that.
- Read `/jobs/<job>/submissions` during the run, and tell the user about findings as they appear.

### Step 2: when it goes live

1. **Review every contract change the swarm made** with `git diff`, and rerun all tests. The critical bug shows my suite alone isn't enough.
2. Merge the delivered commit into `v2`. Move the root `launch.json` to `launch/<number>-manifest.json`, because a root one can block another launch.
3. `forge build`, then `cd frontend && pnpm abi`. Set `DEPLOYED` and `DEPLOYED_ZAP` in `frontend/src/lib/config.ts`.
4. Test real small bets from the wallet: one ETH through the zap and one USDG (buy a little USDG with ETH first), then sell one. Check `exit`.
5. Show the user the exact market wording, then create the 4 markets (`b` = 1.44 IMD, `maxBudget` = 1 IMD, seed ~2 IMD from `seedFor`). Recheck targets that day, and run IMD's pre-check on each question.
6. Merge `v2` into `main`, push with the George token (Vercel deploys), and check https://conditionals.xyz.

### The 4 markets (user approved; recheck targets on creation day)

| # | If… | Will… | Trading must close |
|---|---|---|---|
| 1 | The Fed raises rates at its Dec 9 2026 decision | BTC closes above $80,000 on Coinbase on Dec 31 | Before Dec 9 |
| 2 | The US carries out **new** strikes on Iran between market creation and Dec 31 | ICE Brent front-month settles above $115 on Dec 31 | Before Dec 31 |
| 3 | The Senate holds another Clarity Act vote by Dec 31 | ETH closes above $2,500 on Coinbase on Dec 31 | Before Dec 31 |
| 4 | BTC closes above $85,000 on Coinbase on Dec 31 | IMD trades above $5 on Dec 31 | Before Dec 31 |

- Resolve time: after Dec 31 UTC. Both statements are judged as of it. Informed traders can take the seed, so close trading before answers go public.
- Market 2 says "new" because reports already describe an Iran war. Brent's January contract settled at $113.43 on Oct 30, and the expiring December at $117.64.
- Market 1: one source put a December hike above 80%. The market still works.
- Text rules: printable ASCII, no double quotes or backslashes, condition and outcome up to 280 characters, rules up to 500 and containing a space.

### Addresses

IMD `0x5f7bb59365ce557c26dbcaa4ee9d39a4b95b7127`, USDG (genuine Global Dollar) `0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168`, Uniswap v4 PoolManager
`0x8366a39CC670B4001A1121B8F6A443A643e40951`, Intake `0xa43e6f75ee006411f79ac1c84120606c2330de82`, oracle signer `0x5598aa9146215bc13eb26f2c692ad1461fd32982`.
USDG routes USDG to ETH (fee 500, spacing 10), then ETH to IMD (fee 10000, spacing 100). The direct IMD/USDG pool is empty.

### Videos

In `C:\Users\Administrator\Videos\Conditionals\`, sources in `~/projects/conditionals-video`. **The user hasn't picked one. Don't post either before ETH and USDG bets work.**

| File | What | Rebuild |
|---|---|---|
| `conditionals-film.mp4` | "One line, two worlds": 60 s, 30 fps, calm, original music | `film.html`, `film.cjs`, `caps2/`, `compose.py` |
| `conditionals-film-2.mp4` | "Reality Splits": 55 s, 60 fps, three.js, 128 BPM track with drops | `film2.js`, `film2.cjs`, `render2.sh`, `parts/`, `compose2.py`, `tools/` |

- Both show sample markets with a note saying so. Recapture with the real 4 markets once live: `tools/parts.cjs` and `tools/e2e.cjs`, against a dev server on port 3987.
- `film2` needs `python3 -m http.server 8765 --bind 127.0.0.1 --directory ~/projects/conditionals-video`, internet for fonts, and about 40 minutes per pass. It skips frames that exist, so **delete the old frames folder named in `render2.sh` before re-rendering**.
- The song "Do I Clench My Fists" is banned: the user rejected it. Only the old sketch file still has it. Claude can't hear audio, so ask the user to judge it.

### What the user wants

- Site: viewed at about 1253x550 (Windows 150% scaling), so test there. No contract addresses on the site. The site shouldn't explain routing or how it uses IMD; the top menu section is titled "IMD", saying bets are made in IMD and can be placed with ETH or USDG.
- Commits: conventional format, no co-author, no mention of AI. The user wants plain, brief updates.
- Spending: confirm before each paid launch. The user wants things verified before paying.

### Still to decide with the user

1. Which film to use.
2. Whether the v2 bet box keeps "swapped into IMD in the same transaction". Claude kept it so people know what they hold; easy to remove.
3. Whether the creator getting a short void's leftover after a year is acceptable. It's the judge's suggested fix and is already in the contract.

---

# Older history

Kept for reference. Where it conflicts with the latest session above, the latest session wins.

## Session 2026-10-31: domain live, frontend adjustments

- **https://conditionals.xyz is live** (bought by the user, renews at $13/yr). `www` and `conditionals-bay.vercel.app`
  308-redirect to it. Step 1 of the list below and the domain purchase are done.
- Wallet funded: **16 IMD, ~0.0015 ETH** (read onchain 2026-10-31). Covers the 15.5 IMD high-end budget.
- Frontend adjustments shipped: hero and fork fit a short screen (user views at ~1253x550, Windows 150% scaling; test
  there), oracle chip under the title, fee card, hackathon link and contract links removed, "Built on IMD" replaced by
  a short "IMD" section. The user does not want the site to explain routing or how the app uses IMD. The user may send
  more adjustments.
- **New v2 requirement:** bet with ETH or stablecoins; the contract swaps to IMD in the same transaction, with a price
  limit, and pots, refunds and payouts stay in IMD (payouts in IMD is our assumption; the user has not objected). The
  site names ETH and USDG with a "Coming with v2" chip: **remove the chip in `Sections.tsx` only when it works**.
- Routes seen on DexScreener 2026-10-31: IMD/ETH ~$234k liquidity, IMD/USDG ~$25k, IMD ~$3.60. No usable USDC or USDT
  route found. Launch with ETH and USDG. Several tokens are named USDG: confirm the real address and allowlist only it.
- Still open: deploy route (IMD launch recommended) and the 5 market topics.

## Session 2026-10-29: domain, v2 liquidity, first markets

The user wants three things: (1) move the site to **conditionals.xyz**, (2) implement the v2 liquidity fixes from
`frontend/public/docs/conditionals-v2-liquidity.pdf`, (3) create **5 markets** on the frontend, seeded by the user.

### State found at the start

- v1 live at `0xc8cc656b71dd77ae1e29b0bc7890edd110e73255` (IMD launch 2278); `marketCount()` = 1.
- Launch wallet `0x63BCf2d1483c7628d7D53704ff9c8199Dc28d907`: **0 IMD, ~0.0000006 ETH**. It cannot pay gas, a
  launch or markets until the user funds it.
- Local `main` is 1 commit ahead of origin (`474d1ad`, the v2 PDF link on /docs), not pushed yet.

### Done this session

- Checked conditionals.xyz: available on Vercel, $1.99 first year, $13/yr renewal. User approved buying it there.
- `vercel domains buy` refuses to run for an agent (`purchase_requires_user`). **The user must buy it themselves**:
  `! vercel domains buy conditionals.xyz --global-config ~/.vercel-george --scope ugwujageorges-projects`
  (or the Vercel dashboard, Domains, as UgwujaGeorge).
- Uncommitted edits: `frontend/src/app/layout.tsx` adds `metadataBase` and `openGraph.url` =
  `https://conditionals.xyz`; `frontend/src/app/docs/page.tsx` "Try it at" link text now reads conditionals.xyz.

### Decisions agreed with the user (explained to them in plain language)

- **v2 = LMSR market maker, no vault for now** (PDF option "seed small"). Four outcomes per market (world A/B x
  YES/NO) in one pot; prices from the formula from the first trade; early exit by selling; one stake spans both worlds.
- **Seed is optional and small.** The seed is neutral (the creator does not pick a side); max loss per market = the
  seed. The user will seed 5 markets with **1-2 IMD each, 5-10 IMD total at risk**, and does not want to lose more.
  Without the vault, the 1% LP fee goes to the market's seeder. Markets without a seed fall back to v1 pool style
  (or must be blocked: decide in the build; simplest is a small minimum seed).
- This means **min b must drop well below the PDF's 10 IMD**: seed = b ln 4, so 1-2 IMD seed is b ~0.72-1.44 IMD.
  The user was told these markets are thin (a 1 IMD trade moves the odds a lot). Update the PDF parameters/docs.
- Oracle cost is separate and always spent: ~1 IMD per market (two questions x 0.5 IMD), ~5 IMD for 5 markets.

### Still open (ask the user)

1. **Deploy route for v2**: new IMD launch (0.5 IMD, swarm audit, parks and loses the 0.5 IMD on any medium/high
   finding) vs direct deploy from the wallet (no audit, not an IMD launch). Not answered yet.
2. **The 5 market topics** ("If [condition], will [outcome]?") or let Claude propose them.
3. **Funding**: wallet needs ETH for gas + ~5 IMD oracle + 5-10 IMD seeds (+0.5 IMD if IMD launch). `launch/buy-imd.sh`
   buys IMD with ETH.
4. What "adjustments to conditionals" means beyond the above (the user mentioned it; not specified yet).

### Next steps, in order

1. After the user buys the domain: `vercel domains add conditionals.xyz` (and `www.conditionals.xyz`) on project
   `conditionals` with the George config; commit the two edits (`chore(frontend): move the site to conditionals.xyz`),
   push `main` with the UgwujaGeorge token (Vercel redeploys), check https://conditionals.xyz. Update this file.
2. Build `ConditionalsV2.sol` per the PDF minus the vault: complete sets, LMSR (Solady expWad/lnWad, log-sum-exp,
   maker-favoured rounding), buy/sell with slippage bounds, `stakeConditional` router, cost-basis void, fees
   200 bps (LP to seeder / burn / builder), oracle flow copied from v1 unchanged. Low `MIN_B`. Tests for invariants
   I1-I8, fuzz, fork test against the live Intake. Keep v1's audit lessons (dust/fee cap, world B answer bug).
3. Frontend: switch to v2 ABI, show live prices per outcome, buy/sell, seed field on create, keep v1 markets readable.
4. Deploy by the chosen route (for an IMD launch: `POST /requests/check` first, then `launch/pay.sh`).
5. Create the 5 markets from the funded wallet with 1-2 IMD seed each; verify on the site.

## Where we stopped

- Contract done and tested: `src/Conditionals.sol`. 44 tests pass (unit, fuzz, 3 invariants); the fork test passes
  against the real Robinhood Chain Intake (`FORK_ROBINHOOD=1 forge test --mc Fork`).
- The question hash the contract computes was checked against the live API: `POST /requests/quote` returns the same
  `questionHash` (also with double, leading and trailing spaces, symbols and mixed-case addresses in the text).
- `POST /requests/import` accepts the repo; `POST /requests/check` on the launch body returns no blockers.
- Frontend done (`frontend/`): demo mode until an address is set. Passes `pnpm lint` and `pnpm build`.

- Launch wallet created: `0x63BCf2d1483c7628d7D53704ff9c8199Dc28d907` (owner and fee recipient). Key and phrase in
  `~/.conditionals/wallet.txt` and `deployer.env` (chmod 600, never committed).
- Rehearsed on an anvil fork of Robinhood Chain: `launch/buy-imd.sh` bought exactly 0.5 IMD for ~0.0010 ETH, then
  approve and the launch payment succeeded; total ~0.00101 ETH. The site was tested in live mode against a fork
  deployment with a scripted wallet: connect, approve, stake, create, ask the oracle, void and claim all work.

- **LIVE: IMD launch 2278.** Conditionals at `0xc8cc656b71dd77ae1e29b0bc7890edd110e73255` on Robinhood Chain (deploy
  tx `0x7baf02fbc322ef9c583b8d50008b0a19fcc0e405ec200e484130a36cdf60da40`). Job `e854ea48-ee65-40eb-b029-f441e6b3b1a2`.
  Owner and fee recipient: `0x63BCf2d1483c7628d7D53704ff9c8199Dc28d907`. Verified onchain: IMD, Intake, signer, 0.5 IMD
  price, panel 5, quorum 4, action `oracle.request@oracle-1`, fees 300/200/100 bps.
- Audit: the first audit found a high bug (world B always settled NO; the outcome was never asked); the swarm fixed it
  and four lows, then the panel found a medium (dust counter-stake forcing a 3% fee); fixed by capping the fee at the
  losing pool. Final judge: no findings. Delivered commit `f6d3551` merged; 106 tests pass. Manifest archived as
  `launch/2278-manifest.json` (a root `launch.json` would block another launch kind).
- Launch paid with 0.5 IMD (tx `0x7da2c11732bb2d3d59cfcced9bafc99ab096ac4c378c8094df01887f3ec276eb`); the wallet has
  ~0.00198 ETH left.
- Site: https://conditionals-bay.vercel.app, live mode against the deployed address (Vercel project
  `ugwujageorges-projects/conditionals`, root `frontend/`, GitHub connected so pushes to `main` redeploy). Vercel CLI for
  George: `vercel --global-config ~/.vercel-george --scope ugwujageorges-projects`. `conditionals.vercel.app` is someone
  else's site. Tested against a fork with the deployed bytecode: connect, create, stake.

**(Superseded: see the 2026-10-29 session at the top.)** Earlier next steps: X account, submission, custom domain, first market.
custom domain (conditionals.markets or conditionals.xyz were available), and a first real market.**

## Launch steps (one paid launch, 0.5 IMD)

1. Wallet key in `~/.conditionals/deployer.env` as `PRIVATE_KEY=0x...` (never committed). It needs 0.5 IMD and a little
   ETH on Robinhood Chain. The payer is the deployer IMD records (`paidBy`).
2. `launch/pay.sh build <owner> <feeRecipient>`: writes `launch/launch.json` pinned to HEAD.
3. `launch/pay.sh approve`, then `launch/pay.sh launch` (it runs the free check first and pays only on no blockers).
4. Follow `GET https://api.imd.fun/intake/4663/<txHash>`, then the job and `GET /launches/:id` for the address.
5. Merge the swarm's delivered commit, set `DEPLOYED` in `frontend/src/lib/config.ts` (or
   `NEXT_PUBLIC_CONDITIONALS_ADDRESS` on Vercel), run `pnpm abi` if the ABI changed, redeploy.
6. Submit at imdradar.site/hackathon with the project X handle, a description and the contract address.

## Lessons carried over from GAMMA

- Any open medium or high finding parks the launch and the 0.5 IMD is lost; a parked launch cannot be retried.
- Steps must be `audit-imported-code`, `adapt-contract-project`, `adversarial-review` with `shape: "chain"`.
- Always `POST /requests/check` before paying. IMD may register a payment hours late; it is fine onchain.
- Commits: conventional format, no co-author or AI mention.
