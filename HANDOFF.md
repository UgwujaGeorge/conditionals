# Handoff: Conditionals

Last updated: 2026-10-20. Hackathon deadline: **21 Oct 2026** (imdradar.site/hackathon). Separate entry from GAMMA
(`~/projects/imd`). GitHub and Vercel: **UgwujaGeorge** (not haileymarshall).

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

**Next: the user sends ~0.0015 ETH to the launch wallet; then `launch/buy-imd.sh`, `launch/pay.sh build <wallet> <wallet>`,
`approve`, `launch`. Vercel deploy needs `vercel login --global-config ~/.vercel-george` (UgwujaGeorge).**

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
