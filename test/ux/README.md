# test/ux/ — UX playground (DEMO ONLY)

Experimental preview of the proposed output styles and flows from
[docs/design/UX-IMPROVEMENT.md](../docs/design/UX-IMPROVEMENT.md).
**Nothing here changes anything on your system** — every script only
prints simulated output (with short sleeps for realism).

## Run

```sh
sh test/ux/example-install-standard.sh    # proposed Standard install flow
sh test/ux/example-install-advanced.sh    # proposed Advanced flow (+ docker-classic warning variant)
sh test/ux/example-update.sh              # proposed update.sh output
sh test/ux/example-status.sh              # proposed status.sh output
sh test/ux/example-styles.sh              # style variants side by side
```

Questions accept Enter for the default; piped/EOF input falls back to the
defaults, so the scripts are safe to pipe into `less` etc.

`lib/ux.sh` is the candidate for the real shared helper
(`files/opencode-permissions-kit-lib/ui.sh`): POSIX sh, zero dependencies,
honors `NO_COLOR` / non-tty, `UI_ASCII=1` forces ASCII fallbacks.

## Feedback wanted

- Log style: labeled lines (A) vs symbols (B) vs bracketed steps (C)?
- Banner: slim line vs boxed?
- Inventory symbols (✔ + ⚠ ✖) OK on your terminal?
- Standard flow: 2 questions + plan + confirm — right amount?
- Anything too noisy / too quiet?
