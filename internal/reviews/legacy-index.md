# legacy-index — pre-restructure review names → vorgang folders

> **Frozen 2026-10-14, generated once, never regenerated.** Maps the
> pre-restructure citation format (`0.0.49b C1`) and file names
> (`2026-10-12-v0.0.49-b.md`) onto the vorgang folders. The corpus
> covers snapshots 0.0.38–0.0.49; new vorgänge (with review-meta
> headers) never appear here — see [INDEX.md](INDEX.md).

## Stem → vorgang map

| Key | Stem | First snapshot | Snapshots | Resolution |
|---|---|---|---|---|
| pr-00109 | v0.0.38 | 2026-09-26 | a | yes |
| pr-00115 | v0.0.39 | 2026-09-27 | a–p | yes |
| pr-00125 | v0.0.40 | 2026-10-02 | a–c | yes |
| pr-00127 | v0.0.41 | 2026-10-02 | a–g | yes |
| pr-00133 | v0.0.42 | 2026-10-03 | a–i | yes |
| pr-00140 | v0.0.43 | 2026-10-04 | a–b | yes |
| pr-00142 | v0.0.44 | 2026-10-05 | a–g | yes |
| pr-00147 | v0.0.45 | 2026-10-06 | a–f | yes |
| pr-00151 | v0.0.46 | 2026-10-08 | a–c | yes |
| pr-00156 | v0.0.47 | 2026-10-10 | a–c | yes |
| pr-00160 | v0.0.48 | 2026-10-11 | a–e | yes |
| pr-00171 | v0.0.49 | 2026-10-12 | a–d | yes |

## Lookup rule

Take the stem from the old citation, find the key above, then:

- old stem + letter (`0.0.39a`) → `internal/reviews/<key>/review-a.md`
- old stem without letter (`0.0.38`) → `internal/reviews/<key>/review-a.md`
- old `*-resolution.md` (`0.0.39-resolution`) → `internal/reviews/<key>/resolution.md`

Examples:

- `0.0.49b C1` → `internal/reviews/pr-00171/review-b.md` (finding C1)
- `0.0.38 S1` → `internal/reviews/pr-00109/review-a.md` (finding S1)
- `2026-09-28-v0.0.39-resolution.md` → `internal/reviews/pr-00115/resolution.md`

`grep -r "0.0.49b" internal/reviews/` works too — stems and qualified
finding IDs appear inside the snapshots and resolutions.
