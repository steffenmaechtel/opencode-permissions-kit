#!/bin/sh
# opencode permissions kit — migrate-denies.sh (COMPATIBILITY STUB)
#
# The real migration script was removed in 0.0.15 (docs/design/ddev-working.md
# — the hard-ACL era ended long before the 0.0.14 upgrade floor). This stub
# exists ONLY so update.sh versions within the supported upgrade floor
# (>= 0.0.14) can still complete their file fetch: their KIT_FILES lists
# include this path, and a 404 would abort the update before the freshly
# fetched update.sh takes over.
#
# Rules:
#   - NOT part of the current KIT_FILES — never deployed to the library.
#   - Executing it directly is a no-op with a pointer to the replacement.
#   - DELETE this file when the upgrade floor moves past 0.0.14.
#
# Replacement for the only still-needed function (group baseline refresh):
#   opencode-permissions-kit update --refresh   (inline in update.sh)
#   opencode-permissions-kit config refresh     (inline in config.sh)
echo "migrate-denies.sh was removed in kit 0.0.15 — the group baseline" >&2
echo "refresh now lives in update.sh --refresh / config.sh refresh." >&2
exit 0
