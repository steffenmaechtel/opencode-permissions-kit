# review.md — the maintainer's side of the review process

Your steering part only. The full process — loop mechanics, stop-rule
details, verification duty, reviewer agents — lives in
[agent/review-concept.md](../../agent/review-concept.md); file mechanics
(snapshots, resolutions, cases) in
[internal/reviews/README.md](../reviews/README.md).

- **Open the birth-PR before the review runs** (draft is fine) and tell
  the reviewer its number — that number is the case key
  (`internal/reviews/A/B/C/D/pr-ABCDE/`). PR-first keeps parallel features safe.
- **Trigger a full review** when a version bump is planned, ~500+
  changed lines or 10+ PRs have accumulated, or a high blast-radius
  area changed (`set -e`/pipefail semantics, traps, sudoers, wrapper).
- **Your go gates the wave review too:** the agent owes one after
  every fix wave, reports round completion (including owed-but-not-run
  reviews) and waits — fix waves and their wave reviews both start on
  your go, never self-advanced.
- **New session when?** Implement runs in one session; every review
  round runs in a NEW session, and that session also applies its fixes
  (report committed first, then the fixes — default since 2026-10-17,
  pr-00189; full rule in
  [agent/review-concept.md](../../agent/review-concept.md), "Session
  rotation"). Your part: start a fresh session per review round.
- **Pause point:** the committed snapshot is your visibility window.
  The fix wave starts on your go, not before.
- **Stop-rule call:** the loop closes when a round leaves
  review-relevant code untouched. When only LOW/INFO findings remain,
  closing the chain is your call — the agent proposes, you decide.
- **Release gate:** no release while a review chain is open.
- **External redundancy pass:** the second snapshot of a release review
  runs on a bias-reduced checkout — setup in
  [CONTRIBUTING.md](../../CONTRIBUTING.md#external-review-machines-bias-reduced-checkout),
  background and rejected alternatives in
  [internal/records/review-independence.md](../records/review-independence.md).
