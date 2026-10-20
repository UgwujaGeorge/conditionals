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

**Next: the user funds the launch wallet and gives the owner and fee-recipient address, then launch.**

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
