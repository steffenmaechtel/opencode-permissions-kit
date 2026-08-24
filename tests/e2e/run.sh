#!/bin/sh
# e2e/run.sh — End-to-end test in Docker container
# Builds an Ubuntu image, installs opencode + our kit, verifies the soft-only
# protection model (DDEV-WORKING): opencode runs as its own user against a
# rootless container backend, no hard ACL denies, ddev can read its files.
# Run from repo root: ./tests/e2e/run.sh
# Shares its build/cache/check scaffolding with run-docker-rootless.sh (lib.sh).
set -e

E2E_IMAGE="opencode-e2e"
E2E_CONTAINER="opencode-e2e-test"
. "$(dirname "$(readlink -f "$0")")/lib.sh"

echo ""
echo "${CYAN}=============================================${NC}"
echo "${CYAN}  opencode permissions kit — E2E Test${NC}"
echo "${CYAN}=============================================${NC}"
echo ""

echo "--- opencode binary cache (version-keyed) ---"
e2e_resolve_cache
e2e_fetch_old

e2e_prepare_project

e2e_start_container

# Detect the OUTER docker layout (rootful vs rootless). Only the podman-rootless
# section (12i) uses it: on a rootless host the e2e container runs in a nested
# user namespace and needs an in-range subuid seed; a rootful host (CI) takes
# the kit's true default path. See lib.sh e2e_detect_host_layout.
e2e_detect_host_layout

echo ""
echo "--- 1. Install opencode (from cache) ---"
E 'bash /opencode-cache/install.sh --binary /opencode-cache/opencode-'"$OC_VERSION"'/opencode' || {
    echo "  ${RED}FAIL${NC}  opencode installer failed (network issue?)"
    if E 'test -x /home/dev/.opencode/bin/opencode'; then
        echo "  ${GREEN}OK${NC}  opencode binary already present"
    else
        failures=1; passed=0
        echo ""
        echo "${RED}E2E aborted — cannot install opencode.${NC}"
        sudo rm -rf "$TMP_PROJECT"
        exit 1
    fi
}

echo ""
echo "--- 1b. status.sh before install (not-installed state) ---"
check "status.sh (not installed) reports hardening NOT active" \
    E 'cd /tmp && sh /home/dev/repo/files/status.sh 2>&1 | grep -q "NOT active"'

echo ""
echo "--- 2. Run install (from local repo checkout, podman-rootless backend) ---"
# Pre-create a default-user config so install.sh must back it up and
# install the deny-all config (--yes auto-answers the backup prompt).
# podman-rootless because the e2e container has no systemd (docker-rootless
# provisioning would abort — rootless is mandatory now).
E 'mkdir -p /home/dev/.config/opencode && printf "%s\n" "{\"model\":\"dummy\"}" > /home/dev/.config/opencode/opencode.jsonc'
# Agent-resource fixtures (issue #19): skills in the developer's ~/.agents
# and ~/.claude (the two dirs opencode auto-scans for
# <dir>/skills/**/SKILL.md) — the install must MOVE both into
# /home/opencode (--yes default) with the sharing-group baseline.
E 'mkdir -p /home/dev/.agents/skills/my-skill /home/dev/.claude/skills/claude-skill && printf "name: my-skill\n---\nbody\n" > /home/dev/.agents/skills/my-skill/SKILL.md && printf "name: claude-skill\n---\nbody\n" > /home/dev/.claude/skills/claude-skill/SKILL.md && printf "agent-notes\n" > /home/dev/.agents/notes.md && printf "oauth-credentials" > /home/dev/.claude/.credentials.json && chmod 700 /home/dev/.agents /home/dev/.claude && chmod 600 /home/dev/.agents/skills/my-skill/SKILL.md /home/dev/.claude/skills/claude-skill/SKILL.md'

echo ""
echo "--- 1c. ddev migration fixtures (fake ddev + dev registry, issue #15) ---"
# The fake ddev (tests/e2e/fake-ddev) answers the version gate, records
# every call + the .ddev owner at call time, exports dump files, and fails
# `start ddev-broken`. The dev registry lists two projects under the
# registered root /var/www/vhosts. Base64 transport (portable GNU+BSD form,
# no -w0): the E helper takes a single sh -c string (heredocs get
# unreadable), and the fixture never needs the exec bit on the host —
# only inside the container.
FAKE_DDEV_B64="$(base64 "$(dirname "$(readlink -f "$0")")/fake-ddev" | tr -d '\n')"
E "echo $FAKE_DDEV_B64 | base64 -d | sudo tee /usr/local/bin/ddev >/dev/null && sudo chmod 755 /usr/local/bin/ddev"
E 'mkdir -p /home/dev/.ddev /var/www/vhosts/ddev-mig/.ddev /var/www/vhosts/ddev-broken/.ddev'
E 'printf "%s\n" "project_info:" "  ddev-mig:" "    approot: /var/www/vhosts/ddev-mig" "  ddev-broken:" "    approot: /var/www/vhosts/ddev-broken" > /home/dev/.ddev/global_config.yaml'
E 'printf "type: typo3\n" > /var/www/vhosts/ddev-mig/.ddev/config.yaml && printf "type: typo3\n" > /var/www/vhosts/ddev-broken/.ddev/config.yaml'
E 'touch /var/www/vhosts/ddev-mig/.ddev/.webimageBuild'
# Group-baseline fixtures: a pre-install tree (dir + file, dev-owned 644)
# plus a real dev-owned git repo (.git 700, config 600) that must become
# group-accessible so the agent-git check below is meaningful.
E 'sudo git init -q /var/www/vhosts/perm-check && sudo sh -c "cd /var/www/vhosts/perm-check && git -c user.email=dev@example.com -c user.name=dev commit -q --allow-empty -m init" && sudo mkdir -p /var/www/vhosts/perm-check/sub && sudo chown -R dev:dev /var/www/vhosts/perm-check && printf "old\n" | sudo tee /var/www/vhosts/perm-check/existing-file.txt >/dev/null && sudo chmod 700 /var/www/vhosts/perm-check/.git && sudo chmod 600 /var/www/vhosts/perm-check/.git/config'
# The log is written by root (version gate) AND dev (export loop): dev owns
# it, world-writable so both may append.
E 'touch /tmp/fake-ddev.log && chmod 666 /tmp/fake-ddev.log'

E "bash -c 'set -o pipefail; sudo bash /home/dev/repo/files/install.sh --yes --container-backend podman-rootless --projects /var/www/vhosts --ddev-settings ddev 2>&1 | tee /tmp/install-out.log'"
echo "  Install complete."

echo ""
echo "--- 2c. ddev database migration (issue #15) ---"
check "2c: dump directory created under /var/backups" \
    E 'ls -d /var/backups/opencode-permissions-kit/ddev-migration-* >/dev/null 2>&1'
check "2c: dump exported for the healthy project" \
    E 'sudo sh -c "test -s /var/backups/opencode-permissions-kit/ddev-migration-*/ddev-mig.sql.gz"'
check "2c: manifest records OK for the healthy project" \
    E 'sudo sh -c "grep -q \"^OK|ddev-mig|\" /var/backups/opencode-permissions-kit/ddev-migration-*/manifest.conf"'
check "2c: manifest records FAIL for the unstartable project" \
    E 'sudo sh -c "grep -q \"^FAIL|ddev-broken|\" /var/backups/opencode-permissions-kit/ddev-migration-*/manifest.conf"'
check "2c: export ran while .ddev was still dev-owned (before the handover)" \
    E 'grep -q "^export-db ddev-mig .*|dev$" /tmp/fake-ddev.log'
check "2c: per-project stop recorded (one project at a time)" \
    E 'grep -q "^stop ddev-mig|" /tmp/fake-ddev.log'
check "2c: exactly one final poweroff" \
    E 'test "$(grep -c "^poweroff|" /tmp/fake-ddev.log)" = "1"'
check "2c: .ddev handed over to opencode AFTER the export" \
    E 'test "$(stat -c %U /var/www/vhosts/ddev-mig/.ddev)" = "opencode"'
check "2c: install warned about the failed project (list + consequence)" \
    E 'grep -q "ddev-broken" /tmp/install-out.log && grep -q "could NOT be exported" /tmp/install-out.log'
check "2c: --yes continued past the failed export (non-interactive)" \
    E 'test -x /usr/local/bin/opencode'
check_fail "2c: DDEV_EXPORTED stamp NOT set while exports failed" \
    E 'sudo grep -q "^DDEV_EXPORTED=" /etc/opencode-permissions-kit/install.conf'
check "2c: install summary shows the dumps + import hint" \
    E 'grep -q "ddev-migrate.sh import" /tmp/install-out.log'
check "2c: recursive group baseline — subdir carries setgid" \
    E 'test -g /var/www/vhosts/perm-check/sub'
check "2c: recursive group baseline — pre-existing file is group-writable" \
    E 'test "$(stat -c %A /var/www/vhosts/perm-check/existing-file.txt | cut -c6)" = "w"'
check "2c: recursive group baseline — group is opencode everywhere" \
    E 'test "$(stat -c %G /var/www/vhosts/perm-check/existing-file.txt)" = "opencode"'
check "2c: baseline runs with live per-pass progress (issue #14)" \
    E 'grep -q "group baseline on /var/www/vhosts" /tmp/install-out.log && grep -q "entries — done" /tmp/install-out.log'
check "2c: .git dir gets the group baseline (dev-owned, setgid + group-writable)" \
    E 'test "$(stat -c %U:%G:%a /var/www/vhosts/perm-check/.git)" = "dev:opencode:2770"'
check "2c: .git/config group-writable, stays dev-owned (issue #17)" \
    E 'test "$(stat -c %U:%G:%a /var/www/vhosts/perm-check/.git/config)" = "dev:opencode:660"'
check "2c: git safe.directory '*' set for the opencode user (issue #17)" \
    E 'sudo -u opencode -H git config --global --get-all safe.directory 2>/dev/null | grep -qFx "*"'
check "2c: agent git can read the dev-owned repository (no dubious ownership)" \
    E 'sudo -u opencode -H git -C /var/www/vhosts/perm-check log --oneline -1 >/dev/null 2>&1'
# Remove the fake binary: section 3 asserts no ddev shadow exists at
# /usr/local/bin/ddev (the soft-only kit ships no shim).
E 'sudo rm -f /usr/local/bin/ddev'

echo ""
echo "--- 3. Wrapper & binary ---"
check "Wrapper at /usr/local/bin/opencode" \
    E 'test -x /usr/local/bin/opencode'
check "Binary at /usr/local/lib/opencode-permissions-kit/bin/opencode" \
    E 'sudo test -x /usr/local/lib/opencode-permissions-kit/bin/opencode'
check "Binary owned root:opencode (not world-executable)" \
    E 'test "$(stat -c %U:%G:%a /usr/local/lib/opencode-permissions-kit/bin/opencode)" = "root:opencode:750"'
# NOTE: with the opencode usergroup as the sharing group, dev is a member and
# CAN execute the binary by absolute path (group bit r-x). That bypass is
# mitigated by the default-user deny-all config (section 6b) — documented
# behavior of the soft-only model, not a regression.
check "default user can execute the binary by absolute path (group member; deny-all config mitigates)" \
    E '/usr/local/lib/opencode-permissions-kit/bin/opencode --version'
check "opencode user can execute the binary" \
    E 'sudo -u opencode /usr/local/lib/opencode-permissions-kit/bin/opencode --version'
check "Wrapper is first in PATH" \
    E 'test "$(which opencode)" = "/usr/local/bin/opencode"'
check "Uninstall script deployed" \
    E 'test -x /usr/local/lib/opencode-permissions-kit/uninstall.sh'
check "config.sh deployed" \
    E 'test -x /usr/local/lib/opencode-permissions-kit/config.sh'
check "update.sh deployed" \
    E 'test -x /usr/local/lib/opencode-permissions-kit/update.sh'
check "status.sh deployed" \
    E 'test -x /usr/local/lib/opencode-permissions-kit/status.sh'
check "install.conf written" \
    E 'test -f /etc/opencode-permissions-kit/install.conf'
check "install.conf records CONTAINER_BACKEND=podman-rootless" \
    E 'grep -q "^CONTAINER_BACKEND=podman-rootless" /etc/opencode-permissions-kit/install.conf'
check "install.conf records OPENCODE_GROUP=opencode" \
    E 'grep -q "^OPENCODE_GROUP=opencode" /etc/opencode-permissions-kit/install.conf'
check_fail "no ddev shim in the library (soft-only kit)" \
    E 'test -e /usr/local/lib/opencode-permissions-kit/bin/ddev'
check_fail "no hooks directory in the library" \
    E 'test -d /usr/local/lib/opencode-permissions-kit/hooks'
check_fail "no protect-projects.sh in the library" \
    E 'test -e /usr/local/lib/opencode-permissions-kit/protect-projects.sh'
check_fail "no ddev shim shadowed at /usr/local/bin/ddev" \
    E 'test -e /usr/local/bin/ddev'
check_fail "no (opencode:docker) RunAs grant in sudoers" \
    E 'sudo grep -q "opencode:docker" /etc/sudoers.d/opencode-permissions-kit'
check "sudoers keeps the base (opencode) RunAs" \
    E 'sudo grep -q "(opencode) NOPASSWD" /etc/sudoers.d/opencode-permissions-kit'
check "sudoers has the socket-check.sh rule" \
    E 'sudo grep -q "socket-check.sh" /etc/sudoers.d/opencode-permissions-kit'
check "status.sh reports the dedicated-user mode" \
    E '/usr/local/lib/opencode-permissions-kit/status.sh 2>&1 | grep -q "dedicated user"'

echo ""
echo "--- 4. User & group ---"
check "User opencode exists" \
    E 'id opencode'
check "opencode primary group is the opencode usergroup" \
    E 'test "$(id -gn opencode)" = "opencode"'
check "developer dev is in the opencode group" \
    E 'id dev | grep -q opencode'
check "opencode ddev home provisioned" \
    E 'sudo test -d /home/opencode/.ddev'

echo ""
echo "--- 4b. ddev always runs as the opencode user (helper + function) ---"
# The developer's `ddev` is a shell function that execs the kit's sudoers
# helper, which re-sets the opencode environment and runs the REAL ddev —
# so the terminal and the agent share one ddev home / one rootless daemon.
check "4b: ddev-as-opencode helper deployed (mode 755)" \
    E 'sudo test -x /usr/local/lib/opencode-permissions-kit/bin/ddev-as-opencode'
check "4b: ddev() function file deployed" \
    E 'sudo test -f /usr/local/lib/opencode-permissions-kit/ddev-as-opencode.sh'
check "4b: ddev() function hooked into the developer .bashrc" \
    E 'grep -q "opencode-permissions-kit/ddev-as-opencode.sh" /home/dev/.bashrc'
check "4b: sudoers grants the ddev-as-opencode helper" \
    E 'sudo grep -q "bin/ddev-as-opencode" /etc/sudoers.d/opencode-permissions-kit'
check_fail "4b: helper refuses a NON-opencode caller (exit 1)" \
    E 'sudo -u dev /usr/local/lib/opencode-permissions-kit/bin/ddev-as-opencode --version >/dev/null 2>&1'
check "4b: helper prints 'must run as' for a non-opencode caller" \
    E 'sudo -u dev /usr/local/lib/opencode-permissions-kit/bin/ddev-as-opencode --version 2>&1 | grep -q "must run as"'
# The e2e container has no real ddev installed: as the opencode user the
# helper must exit 127 with a clean hint (never a traceback, never a shim).
check "4b: helper as opencode without ddev exits 127 with a hint" \
    E 'sudo -u opencode sh -c "/usr/local/lib/opencode-permissions-kit/bin/ddev-as-opencode --version >/dev/null 2>/tmp/ddo.out; rc=\$?; test \$rc -eq 127 && grep -q \"ddev is not installed\" /tmp/ddo.out"'
# Issue #18: vendor scripts (e.g. TYPO3 vendor/bin/runTests.sh) call ddev
# in a CHILD bash shell — behind a #!/bin/sh (dash) wrapper that execs the
# bash target. The hook must export the function AND set BASH_ENV (dash
# strips BASH_FUNC_* entries, only the BASH_ENV variable survives), so the
# target resolves ddev to the function (runs as opencode) instead of the
# real binary (would run as the developer). The hook file is sourced
# directly (Ubuntu's .bashrc returns early for non-interactive shells; the
# .bashrc wiring itself is asserted by the static check above).
E 'printf "#!/usr/bin/env sh\nexec /tmp/rt-target.sh \"\$@\"\n" > /tmp/rt-wrap.sh && printf "#!/usr/bin/env bash\ncommand -v ddev\n" > /tmp/rt-target.sh && chmod 755 /tmp/rt-wrap.sh /tmp/rt-target.sh'
check "4b: ddev() exported to child bash scripts (issue #18)" \
    E 'sudo -u dev -H bash -c "source /usr/local/lib/opencode-permissions-kit/ddev-as-opencode.sh; bash -c \"type -t ddev\"" 2>/dev/null | grep -q function'
check "4b: ddev() survives the vendor #!/bin/sh wrapper chain into the bash target (issue #18)" \
    E 'sudo -u dev -H bash -c "source /usr/local/lib/opencode-permissions-kit/ddev-as-opencode.sh; /tmp/rt-wrap.sh -s phpstan" 2>/dev/null | grep -qx ddev'
# Issue #20: `ddev launch` must run as the DEVELOPER — opening the browser
# needs WSL interop (explorer.exe / xdg-open -> wslview), which the opencode
# user deliberately has not. Fake id reports a non-opencode uid; the fake
# ddev proves launch runs it directly as the developer, while `start` still
# routes through the sudoers helper (as opencode — no ddev in the container,
# so the helper exits 127 with its hint).
E 'mkdir -p /tmp/opk-fakebin && printf "#!/bin/sh\ncase \"\$*\" in \"-u\") echo 4242;; \"-u opencode\") echo 9999;; *) echo 0;; esac\n" > /tmp/opk-fakebin/id && printf "#!/bin/sh\necho \"REAL_DDEV_RAN:\$*\"\n" > /tmp/opk-fakebin/ddev && chmod 755 /tmp/opk-fakebin/id /tmp/opk-fakebin/ddev'
check "4b: ddev start still routes through the sudoers helper as opencode" \
    E 'sudo -u dev -H env PATH=/tmp/opk-fakebin:/usr/bin:/bin sh -c ". /usr/local/lib/opencode-permissions-kit/ddev-as-opencode.sh; ddev start" 2>&1 | grep -q "ddev is not installed"'
# Issue #20 full chain: the browser-command arm computes the URL AS
# OPENCODE via the sudoers helper with DDEV_DEBUG=true (ddev's launch
# prints "FULLURL <url>" instead of opening a browser — inherited by
# INTERNAL `ddev launch` children of wrapper commands like mailpit or
# the phpmyadmin/adminer add-ons) and only the browser open runs as the
# developer. Fake ddev honors the FULLURL contract for the whole class
# and records the caller; no explorer.exe/xdg-open in the container, so
# the function prints the URL.
E 'printf "#!/bin/sh\ncase \"\$1\" in launch|mailpit|phpmyadmin|adminer) echo \"FULLURL https://fake-project.ddev.site as \$(id -un)\";; *) exit 0;; esac\n" | sudo tee /usr/local/bin/ddev >/dev/null && sudo chmod 755 /usr/local/bin/ddev'
check "4b: ddev launch computes the URL as opencode and hands it to the developer (issue #20)" \
    E 'sudo -u dev -H bash -c ". /usr/local/lib/opencode-permissions-kit/ddev-as-opencode.sh; ddev launch /typo3" | grep -qx "https://fake-project.ddev.site as opencode"'
check "4b: ddev mailpit routes through the browser arm (issue #20 follow-up)" \
    E 'sudo -u dev -H bash -c ". /usr/local/lib/opencode-permissions-kit/ddev-as-opencode.sh; ddev mailpit" | grep -qx "https://fake-project.ddev.site as opencode"'
check "4b: ddev phpmyadmin routes through the browser arm (issue #20 follow-up)" \
    E 'sudo -u dev -H bash -c ". /usr/local/lib/opencode-permissions-kit/ddev-as-opencode.sh; ddev phpmyadmin" | grep -qx "https://fake-project.ddev.site as opencode"'
check "4b: launch does not run ddev as the developer (no spurious internal start)" \
    E 'sudo -u dev -H bash -c ". /usr/local/lib/opencode-permissions-kit/ddev-as-opencode.sh; ddev launch" | grep -qv "as dev"'
check_fail "4b: FULLURL transport lines stay off the visible output (stdout AND stderr)" \
    E 'sudo -u dev -H bash -c ". /usr/local/lib/opencode-permissions-kit/ddev-as-opencode.sh; ddev launch" 2>&1 | grep -q "^FULLURL"'
check "4b: stdout carries exactly the clean URL line" \
    E 'sudo -u dev -H bash -c ". /usr/local/lib/opencode-permissions-kit/ddev-as-opencode.sh; ddev launch" 2>/dev/null | grep -qx "https://fake-project.ddev.site as opencode"'
E 'sudo rm -f /usr/local/bin/ddev'

echo ""
echo "--- 4c. .ddev handover to the opencode user (ddev-working) ---"
# A pre-existing dev-owned .ddev breaks `ddev start` as opencode with
# "chmod .ddev/.webimageBuild: operation not permitted". config.sh refresh
# (the group-baseline refresh) must hand .ddev AND the typo3 settings dirs
# over to opencode (ddev chmods them unconditionally, owner-only).
E 'mkdir -p /var/www/vhosts/test-project/.ddev /var/www/vhosts/test-project/config/system && touch /var/www/vhosts/test-project/.ddev/.webimageBuild && printf "type: typo3\n" > /var/www/vhosts/test-project/.ddev/config.yaml && echo "db_default" > /var/www/vhosts/test-project/config/system/settings.php'
check "4c: planted .ddev is dev-owned before the handover" \
    E 'test "$(stat -c %U /var/www/vhosts/test-project/.ddev)" = "dev"'
E 'sudo bash /usr/local/lib/opencode-permissions-kit/config.sh --yes refresh' && \
    echo "  ${GREEN}OK${NC}  config.sh refresh completed"
check "4c: .ddev handed over to opencode" \
    E 'test "$(stat -c %U /var/www/vhosts/test-project/.ddev)" = "opencode"'
check "4c: .ddev in the opencode usergroup" \
    E 'test "$(stat -c %G /var/www/vhosts/test-project/.ddev)" = "opencode"'
check "4c: .ddev contents group-writable (agent-created files)" \
    E 'test "$(stat -c %a /var/www/vhosts/test-project/.ddev/config.yaml)" = "664"'
check "4c: typo3 settings dir handed over to opencode" \
    E 'test "$(stat -c %U /var/www/vhosts/test-project/config/system)" = "opencode"'
check "4c: typo3 settings.php group-writable" \
    E 'test "$(stat -c %a /var/www/vhosts/test-project/config/system/settings.php)" = "664"'
# Project-root handover (TYPO3 bootstrap): no vendor marker => ddev's
# settings-path fallback targets the APP ROOT and its chmod needs
# ownership. Root inode (not contents) => opencode, mode 2755: Perm==0755
# makes ddev's util.Chmod a structural no-op.
check "4c: undetected typo3 project root owned by opencode (bootstrap)" \
    E 'test "$(stat -c %U /var/www/vhosts/test-project)" = "opencode"'
check "4c: undetected typo3 project root is 2755 (Perm==0755, ddev chmod no-op)" \
    E 'test "$(stat -c %a /var/www/vhosts/test-project)" = "2755"'
check "4c: project-root handover is inode-only (contents not chowned to opencode)" \
    E 'test "$(stat -c %U /var/www/vhosts/test-project/index.php)" != "opencode"'
# Detected project (vendor marker present): ddev targets config/system,
# never the root — it must stay dev-owned with g+w (2775).
E 'sudo mkdir -p /var/www/vhosts/detected-project/.ddev /var/www/vhosts/detected-project/vendor/typo3/cms-core/Classes/Information /var/www/vhosts/detected-project/config/system && sudo chown -R dev:dev /var/www/vhosts/detected-project && printf "type: typo3\n" | sudo tee /var/www/vhosts/detected-project/.ddev/config.yaml >/dev/null && sudo touch /var/www/vhosts/detected-project/vendor/typo3/cms-core/Classes/Information/Typo3Version.php'
E 'sudo bash /usr/local/lib/opencode-permissions-kit/config.sh --yes refresh'
check "4c: detected typo3 project root handed BACK to dev (2775)" \
    E 'test "$(stat -c %U /var/www/vhosts/detected-project)" = "dev" && test "$(stat -c %a /var/www/vhosts/detected-project)" = "2775"'
check "4c: detected typo3 settings dir still handed over to opencode" \
    E 'test "$(stat -c %U /var/www/vhosts/detected-project/config/system)" = "opencode"'

echo ""
echo "--- 4d. fresh clone: hook hint + config.sh handover (local-test issue) ---"
# Scenario from the productive WSL test: git clone a typo3 project AFTER
# the last handover scan -> `ddev start` fails with EPERM (ddev chmods the
# undetected project root; owner-only). The ddev() hook must print the
# ready-made fix BEFORE the run, and `config.sh handover <project>` (light,
# no group baseline) must repair ownership without a full refresh.
E 'sudo mkdir -p /var/www/vhosts/fresh-clone/.ddev && sudo chown -R dev:dev /var/www/vhosts/fresh-clone && printf "type: typo3\n" > /var/www/vhosts/fresh-clone/.ddev/config.yaml && chmod 2775 /var/www/vhosts/fresh-clone'
check "4d: fresh clone root is dev-owned before the handover" \
    E 'test "$(stat -c %U /var/www/vhosts/fresh-clone)" = "dev"'
check "4d: ddev() hook prints the bootstrap hint naming the handover command" \
    E 'sudo -u dev -H sh -c "cd /var/www/vhosts/fresh-clone && . /usr/local/lib/opencode-permissions-kit/ddev-as-opencode.sh; ddev start" 2>&1 | grep -q "config handover /var/www/vhosts/fresh-clone"'
E 'sudo bash /usr/local/lib/opencode-permissions-kit/config.sh --yes handover /var/www/vhosts/fresh-clone' && \
    echo "  ${GREEN}OK${NC}  config.sh handover completed"
check "4d: handover gives the bootstrap root to opencode (2755, chmod no-op)" \
    E 'test "$(stat -c %U /var/www/vhosts/fresh-clone)" = "opencode" && test "$(stat -c %a /var/www/vhosts/fresh-clone)" = "2755"'
check "4d: .ddev handed over too" \
    E 'test "$(stat -c %U /var/www/vhosts/fresh-clone/.ddev)" = "opencode"'
check_fail "4d: hook stays silent once the root is handed over" \
    E 'sudo -u dev -H sh -c "cd /var/www/vhosts/fresh-clone && . /usr/local/lib/opencode-permissions-kit/ddev-as-opencode.sh; ddev start" 2>&1 | grep -q "hint: fresh typo3 clone"'
# vendor pruning (issue #21 pattern): a .ddev shipped inside a vendor
# package is a test fixture, not a project — never handed over.
E 'sudo mkdir -p /var/www/vhosts/fresh-clone/vendor/some/pkg/.ddev && sudo chown -R dev:dev /var/www/vhosts/fresh-clone/vendor'
E 'sudo bash /usr/local/lib/opencode-permissions-kit/config.sh --yes handover /var/www/vhosts/fresh-clone'
check "4d: .ddev inside vendor/ is NOT handed over (issue #21 pattern)" \
    E 'test "$(stat -c %U /var/www/vhosts/fresh-clone/vendor/some/pkg/.ddev)" = "dev"'
# testdata pruning (issue #29): a checkout of ddev's own repository ships
# .ddev dirs under cmd/pkg testdata — fixtures, not projects.
E 'sudo mkdir -p /var/www/vhosts/fresh-clone/pkg/ddevapp/testdata/TestHooksMerge/proj/.ddev && sudo chown -R dev:dev /var/www/vhosts/fresh-clone/pkg'
E 'sudo bash /usr/local/lib/opencode-permissions-kit/config.sh --yes handover /var/www/vhosts/fresh-clone'
check "4d: .ddev inside testdata/ is NOT handed over (issue #29)" \
    E 'test "$(stat -c %U /var/www/vhosts/fresh-clone/pkg/ddevapp/testdata/TestHooksMerge/proj/.ddev)" = "dev"'

echo ""
echo "--- 4e. dev-owned mode (disable_settings_management, design plan) ---"
# Installed with --ddev-settings ddev (handover model) so far. Toggle the
# dev-owned mode on: the scan must write disable_settings_management:
# true into a project's .ddev/config.yaml and keep settings dirs + root
# developer-owned — ddev then never chmods outside .ddev/ (early return
# in its CreateSettingsFile), git checkout stays free even on a fresh
# typo3 clone.
E 'sudo bash /usr/local/lib/opencode-permissions-kit/config.sh --yes ddev-settings on'
check "4e: install.conf carries the mode stamp" \
    E 'grep -q "^DDEV_DEV_OWNED=true$" /etc/opencode-permissions-kit/install.conf'
E 'sudo mkdir -p /var/www/vhosts/devowned-proj/.ddev /var/www/vhosts/devowned-proj/config/system && sudo chown -R dev:dev /var/www/vhosts/devowned-proj && printf "type: typo3\n" > /var/www/vhosts/devowned-proj/.ddev/config.yaml && chmod 2775 /var/www/vhosts/devowned-proj'
check "4e: fresh clone root is dev-owned before the scan" \
    E 'test "$(stat -c %U /var/www/vhosts/devowned-proj)" = "dev"'
E 'sudo bash /usr/local/lib/opencode-permissions-kit/config.sh --yes handover /var/www/vhosts/devowned-proj' && \
    echo "  ${GREEN}OK${NC}  config.sh handover (dev-owned) completed"
check "4e: scan wrote disable_settings_management into .ddev/config.yaml" \
    E 'grep -qx "disable_settings_management: true" /var/www/vhosts/devowned-proj/.ddev/config.yaml'
check "4e: flag inserted below type: with blank separation (issue #28)" \
    E 'test -z "$(sed -n 2p /var/www/vhosts/devowned-proj/.ddev/config.yaml)" && test "$(sed -n 5p /var/www/vhosts/devowned-proj/.ddev/config.yaml)" = "disable_settings_management: true"'
check "4e: undetected typo3 root STAYS dev-owned (no bootstrap handover)" \
    E 'test "$(stat -c %U /var/www/vhosts/devowned-proj)" = "dev" && test "$(stat -c %a /var/www/vhosts/devowned-proj)" = "2775"'
check "4e: settings dir stays dev-owned" \
    E 'test "$(stat -c %U /var/www/vhosts/devowned-proj/config/system)" = "dev"'
check "4e: .ddev still handed over to opencode" \
    E 'test "$(stat -c %U /var/www/vhosts/devowned-proj/.ddev)" = "opencode"'
check "4e: developer can replace top-level files (git checkout simulation)" \
    E 'sudo -u dev touch /var/www/vhosts/devowned-proj/AGENTS.md && sudo -u dev rm /var/www/vhosts/devowned-proj/AGENTS.md'
# migration: a project that went through the handover model (opencode-owned
# root 2755) gets everything back once flagged
E 'sudo mkdir -p /var/www/vhosts/devowned-mig/.ddev && sudo chown -R dev:dev /var/www/vhosts/devowned-mig && printf "type: typo3\n" > /var/www/vhosts/devowned-mig/.ddev/config.yaml && sudo chown opencode:opencode /var/www/vhosts/devowned-mig && sudo chmod 2755 /var/www/vhosts/devowned-mig'
E 'sudo bash /usr/local/lib/opencode-permissions-kit/config.sh --yes handover /var/www/vhosts/devowned-mig'
check "4e: previously handed-over root migrates back to dev (2775)" \
    E 'test "$(stat -c %U /var/www/vhosts/devowned-mig)" = "dev" && test "$(stat -c %a /var/www/vhosts/devowned-mig)" = "2775"'
# hook hint on an unflagged fresh clone mentions the dev-owned effect
E 'sudo mkdir -p /var/www/vhosts/devowned-hint/.ddev && sudo chown -R dev:dev /var/www/vhosts/devowned-hint && printf "type: typo3\n" > /var/www/vhosts/devowned-hint/.ddev/config.yaml && chmod 2775 /var/www/vhosts/devowned-hint'
check "4e: hook hint mentions disable_settings_management (dev-owned note)" \
    E 'sudo -u dev -H sh -c "cd /var/www/vhosts/devowned-hint && . /usr/local/lib/opencode-permissions-kit/ddev-as-opencode.sh; ddev start" 2>&1 | grep -q "disable_settings_management:"'
# once flagged, the hook must stay silent (the EPERM can no longer occur)
E 'sudo bash /usr/local/lib/opencode-permissions-kit/config.sh --yes handover /var/www/vhosts/devowned-hint'
check "4e: hook hint silent once the project is flagged (dev-owned)" \
    E '! sudo -u dev -H sh -c "cd /var/www/vhosts/devowned-hint && . /usr/local/lib/opencode-permissions-kit/ddev-as-opencode.sh; ddev start" 2>&1 | grep -q "hint: fresh typo3 clone"'
# testdata pruning in dev-owned mode (issue #29): fixture .ddev configs
# (e.g. a checkout of ddev's own repository) must stay untouched — no
# flag write, no chown, no git-status pollution in the checkout.
E 'sudo mkdir -p /var/www/vhosts/devowned-skip/pkg/ddevapp/testdata/TestWriteConfig/proj/.ddev && sudo chown -R dev:dev /var/www/vhosts/devowned-skip && printf "name: p\ntype: php\n" > /var/www/vhosts/devowned-skip/pkg/ddevapp/testdata/TestWriteConfig/proj/.ddev/config.yaml'
E 'sudo bash /usr/local/lib/opencode-permissions-kit/config.sh --yes handover /var/www/vhosts/devowned-skip'
check "4e: scan skips .ddev inside testdata/ (issue #29, no flag write)" \
    E '! grep -q "^disable_settings_management:" /var/www/vhosts/devowned-skip/pkg/ddevapp/testdata/TestWriteConfig/proj/.ddev/config.yaml'
check "4e: scan skips .ddev inside testdata/ (issue #29, no chown)" \
    E 'test "$(stat -c %U /var/www/vhosts/devowned-skip/pkg/ddevapp/testdata/TestWriteConfig/proj/.ddev)" = "dev"'
# back to the handover model for the remaining sections
E 'sudo bash /usr/local/lib/opencode-permissions-kit/config.sh --yes ddev-settings off'

echo ""
echo "--- 5. Soft-only file access (the ddev-working goal) ---"
# No hard ACL denies: the opencode user (and ddev, and its containers) can
# READ every project file. Protection is opencode's own soft permission layer.
check ".env readable by opencode (soft-only model)" \
    E 'sudo -u opencode test -r /var/www/vhosts/test-project/.env'
check "settings.php readable (ddev boots)" \
    E 'sudo -u opencode test -r /var/www/vhosts/test-project/settings.php'
check "auth.json readable" \
    E 'sudo -u opencode test -r /var/www/vhosts/test-project/auth.json'
check "README.md readable" \
    E 'sudo -u opencode test -r /var/www/vhosts/test-project/README.md'
check "index.php readable" \
    E 'sudo -u opencode test -r /var/www/vhosts/test-project/index.php'
check_fail "no u:opencode ACL deny on .env" \
    E 'sudo getfacl -p /var/www/vhosts/test-project/.env 2>/dev/null | grep -q "user:opencode:---"'

echo ""
echo "--- 6. Config & agents ---"
check "Config deployed" \
    E 'sudo test -f /home/opencode/.config/opencode/opencode.jsonc'
check "Agents dir exists" \
    E 'sudo test -d /home/opencode/.agents/'
check "issue #19: ~/.agents moved WHOLE into the opencode home (--yes default)" \
    E 'test "$(cat /home/opencode/.agents/skills/my-skill/SKILL.md)" = "name: my-skill
---
body" && test -f /home/opencode/.agents/notes.md'
check "issue #19: ~/.claude/skills moved into the opencode home" \
    E 'test -f /home/opencode/.claude/skills/claude-skill/SKILL.md'
check "review 0.0.22: ~/.claude/.credentials.json STAYS with the developer (skills-only from .claude)" \
    E 'test -f /home/dev/.claude/.credentials.json && test ! -e /home/opencode/.claude/.credentials.json'
check "issue #19: whole .agents gone after the move, .claude parent stays (skills-only)" \
    E 'test ! -e /home/dev/.agents && test -d /home/dev/.claude && test ! -e /home/dev/.claude/skills'
check "issue #19: migrated dirs carry the sharing baseline (setgid + group)" \
    E 'test "$(stat -c %U:%G:%a /home/opencode/.agents)" = "opencode:opencode:2775" && test "$(stat -c %U:%G:%a /home/opencode/.claude)" = "opencode:opencode:2775"'
check "issue #19: migrated files are group-writable for the developer" \
    E 'test "$(stat -c %U:%G:%a /home/opencode/.agents/skills/my-skill/SKILL.md)" = "opencode:opencode:660" && test -w /home/opencode/.agents/skills/my-skill/SKILL.md'
check "default user can cd into opencode home" \
    E 'cd /home/opencode'
check "default user can read opencode.jsonc" \
    E 'test -r /home/opencode/.config/opencode/opencode.jsonc'
check "default user can write opencode.jsonc" \
    E 'test -w /home/opencode/.config/opencode/opencode.jsonc'

echo ""
echo "--- 6b. Default-user deny-all config (self-update bypass protection) ---"
check "default-user deny-all config deployed" \
    E 'test -f /home/dev/.config/opencode/opencode.jsonc'
check "pre-existing default-user config backed up" \
    E 'ls /home/dev/.config/opencode/ | grep -q "opencode.jsonc_BAK_"'
check "deny-all config owned by dev" \
    E 'test "$(stat -c %U /home/dev/.config/opencode/opencode.jsonc)" = "dev"'
check "deny-all config denies everything" \
    E 'grep -q '\''"\*"'\'' /home/dev/.config/opencode/opencode.jsonc'
check "deny-all config points to the agent config (discoverability hint)" \
    E 'grep -q "/home/opencode/.config/opencode/opencode.jsonc" /home/dev/.config/opencode/opencode.jsonc'

echo ""
echo "--- 6c. Wrapper bypass guard (self-install + absolute path) ---"
check "shell-warn.sh deployed to library" \
    E 'test -f /usr/local/lib/opencode-permissions-kit/shell-warn.sh'
check "shell-warn.sh sourced by umask profile" \
    E 'grep -q shell-warn.sh /etc/profile.d/opencode-permissions-kit-umask.sh'
check "interactive-shell warning hooked into .bashrc" \
    E 'grep -q "opencode-permissions-kit/shell-warn.sh" /home/dev/.bashrc'
# Simulate a self-reinstall: the official installer drops a real binary into
# ~/.opencode/bin. The guard must report it.
E 'sudo mkdir -p /home/dev/.opencode/bin && sudo cp /usr/local/lib/opencode-permissions-kit/bin/opencode /home/dev/.opencode/bin/opencode'
E 'sudo chmod 755 /home/dev/.opencode/bin/opencode && sudo chown dev:dev /home/dev/.opencode/bin/opencode'
check "shell-warn.sh warns about shadow binary" \
    E 'sh -c '\''HOME=/home/dev . /usr/local/lib/opencode-permissions-kit/shell-warn.sh'\'' 2>&1 | grep -q "wrapper bypass"'
check "wrapper start warns about shadow binary" \
    E 'cd /var/www/vhosts/test-project && echo "" | /usr/local/bin/opencode --help 2>&1 | grep -q "self-installed opencode detected"'
# Cleaning the shadow directory restores the quiet state.
E 'rm -rf /home/dev/.opencode'
check "shell-warn.sh quiet after cleanup" \
    E 'test -z "$(sh -c '\''HOME=/home/dev . /usr/local/lib/opencode-permissions-kit/shell-warn.sh'\'' 2>&1)"'

echo ""
echo "--- 8. Umask ---"
check "umask script deployed" \
    E 'test -f /etc/profile.d/opencode-permissions-kit-umask.sh'

echo ""
echo "--- 9. Group baseline (sharing group = opencode usergroup) ---"
check "project files in the opencode group" \
    E 'test "$(stat -c %G /var/www/vhosts/test-project)" = "opencode"'
check "default ACL g:opencode:rwx on the project root" \
    E 'sudo getfacl -p -d /var/www/vhosts/test-project | grep -q "group:opencode:rwx"'
check "setgid on the registered project root" \
    E 'test -g /var/www/vhosts'

echo ""
echo "--- 11. update.sh re-deploys kit + preservation contract ---"
# Snapshot files that update.sh must NOT touch (use sudo to be independent of perms)
E 'sudo sha256sum /home/opencode/.config/opencode/opencode.jsonc | cut -d" " -f1 > /tmp/sha-opencode-jsonc.before'
E 'sudo sha256sum /usr/local/lib/opencode-permissions-kit/bin/opencode | cut -d" " -f1 > /tmp/sha-binary.before'
E 'cat /etc/opencode-permissions-kit/projects.conf > /tmp/projects.conf.before'
# Create a copy of the repo files with a sentinel VERSION so we can observe the bump.
# We can't overwrite the bind-mounted VERSION reliably, so we copy update.sh + a
# sentinel VERSION into a temp dir and run it from there.
E 'rm -rf /tmp/update-test && mkdir -p /tmp/update-test/files && cp -r /home/dev/repo/files/* /tmp/update-test/files/ && echo "9.9.9-sentinel" > /tmp/update-test/VERSION'
E 'sudo bash /tmp/update-test/files/update.sh --yes' && \
    echo "  ${GREEN}OK${NC}  update.sh completed without prompts"
check "Wrapper still present after update" E 'test -x /usr/local/bin/opencode'
check "config.sh still present"            E 'test -x /usr/local/lib/opencode-permissions-kit/config.sh'
check "update.sh still present"            E 'test -x /usr/local/lib/opencode-permissions-kit/update.sh'
check "install.conf still present"         E 'test -f /etc/opencode-permissions-kit/install.conf'
check "projects.conf untouched"           E 'test -f /etc/opencode-permissions-kit/projects.conf'
check ".env still readable after update (soft-only)" \
    E 'sudo -u opencode test -r /var/www/vhosts/test-project/.env'
check "opencode.jsonc byte-identical (sha256 unchanged)" \
    E 'test "$(sudo sha256sum /home/opencode/.config/opencode/opencode.jsonc | cut -d" " -f1)" = "$(cat /tmp/sha-opencode-jsonc.before)"'
check "default-user deny-all config survives update" \
    E 'test -f /home/dev/.config/opencode/opencode.jsonc'
check "binary byte-identical (sha256 unchanged)" \
    E 'test "$(sudo sha256sum /usr/local/lib/opencode-permissions-kit/bin/opencode | cut -d" " -f1)" = "$(cat /tmp/sha-binary.before)"'
check "projects.conf content unchanged" \
    E 'test "$(cat /etc/opencode-permissions-kit/projects.conf)" = "$(cat /tmp/projects.conf.before)"'
check "install.conf VERSION bumped to sentinel" \
    E 'grep -q "VERSION=9.9.9-sentinel" /etc/opencode-permissions-kit/install.conf'
E 'rm -rf /tmp/update-test'

echo ""
echo "--- 11b. update.sh --only-binary (issue #24) ---"
# Binary-only mode: kit steps skipped (marker in LIBDIR survives, the
# install.conf version stays at section 11's sentinel), the binary is
# actually replaced by the given stub.
E 'rm -rf /tmp/update-test && mkdir -p /tmp/update-test/files && cp -r /home/dev/repo/files/* /tmp/update-test/files/ && echo "8.8.8-onlybinary" > /tmp/update-test/VERSION'
E 'sudo sh -c "echo marker > /usr/local/lib/opencode-permissions-kit/.only-binary-marker"'
E 'printf "#!/bin/sh\necho \"opencode version 9.9.9-onlybinary\"\n" > /tmp/stub-opencode && chmod +x /tmp/stub-opencode'
E 'sudo bash /tmp/update-test/files/update.sh --yes --only-binary --binary-path /tmp/stub-opencode' && \
    echo "  ${GREEN}OK${NC}  update.sh --only-binary completed"
check "11b: binary replaced by the stub (--only-binary)" \
    E 'test "$(/usr/local/lib/opencode-permissions-kit/bin/opencode --version 2>/dev/null | head -1)" = "opencode version 9.9.9-onlybinary"'
check "11b: kit re-deploy skipped (marker survived)" \
    E 'test "$(sudo cat /usr/local/lib/opencode-permissions-kit/.only-binary-marker)" = "marker"'
check "11b: install.conf version NOT re-stamped (still section 11's sentinel)" \
    E 'grep -q "VERSION=9.9.9-sentinel" /etc/opencode-permissions-kit/install.conf && ! grep -q "VERSION=8.8.8-onlybinary" /etc/opencode-permissions-kit/install.conf'
# top-level shorthand (issue #24): kit CLI maps upgrade-opencode onto
# update.sh --yes --only-binary, flags pass through
E 'printf "#!/bin/sh\necho \"opencode version 7.7.7-shorthand\"\n" > /tmp/stub-opencode2 && chmod +x /tmp/stub-opencode2'
E 'opencode-permissions-kit upgrade-opencode --binary-path /tmp/stub-opencode2' && \
    echo "  ${GREEN}OK${NC}  kit CLI upgrade-opencode completed"
check "11b: upgrade-opencode replaced the binary (shorthand works)" \
    E 'test "$(/usr/local/lib/opencode-permissions-kit/bin/opencode --version 2>/dev/null | head -1)" = "opencode version 7.7.7-shorthand"'
E 'sudo rm -f /usr/local/lib/opencode-permissions-kit/.only-binary-marker'
# restore the real binary for the remaining sections
E 'sudo cp /opencode-cache/opencode-'"$OC_VERSION"'/opencode /usr/local/lib/opencode-permissions-kit/bin/opencode && sudo chown root:opencode /usr/local/lib/opencode-permissions-kit/bin/opencode && sudo chmod 750 /usr/local/lib/opencode-permissions-kit/bin/opencode'
E 'rm -rf /tmp/update-test /tmp/stub-opencode /tmp/stub-opencode2'

echo ""
echo "--- 11b. update floor check (installs < 0.0.14 abort) ---"
# Updates are only supported from 0.0.14 onwards; an older VERSION stamp must
# abort with re-install instructions instead of running an undefined path.
E 'sudo cp /etc/opencode-permissions-kit/install.conf /tmp/install.conf.floor-bak'
E "sudo sed -i 's/^VERSION=.*/VERSION=0.0.13/' /etc/opencode-permissions-kit/install.conf"
E 'sudo bash /home/dev/repo/files/update.sh --yes >/tmp/floor-abort.log 2>&1' || true
check "floor: update aborts on VERSION=0.0.13" \
    E 'grep -q "Unsupported upgrade path" /tmp/floor-abort.log'
check "floor: abort names the re-install way out" \
    E 'grep -q "install.sh" /tmp/floor-abort.log'
check "floor: library not re-deployed by the aborted run" \
    E 'test -x /usr/local/lib/opencode-permissions-kit/config.sh'
E 'sudo mv /tmp/install.conf.floor-bak /etc/opencode-permissions-kit/install.conf'
E 'sudo bash /home/dev/repo/files/update.sh --yes >/dev/null 2>&1' && \
    echo "  ${GREEN}OK${NC}  update succeeds again with a supported version"

echo ""
echo "--- 11c. opencode binary upgrade (old -> new via update.sh --binary-path) ---"
# Downgrade the system binary to a pinned OLD version, then upgrade it back to
# the (cached) latest with update.sh --binary-path. This is the kit's upgrade
# entry point — `opencode upgrade` cannot work behind the wrapper.
E 'sudo cp /opencode-cache/opencode-'"$OLD_VERSION"'/opencode /usr/local/lib/opencode-permissions-kit/bin/opencode' && \
    echo "  ${GREEN}OK${NC}  system binary downgraded to $OLD_VERSION"
check "downgrade: system binary is $OLD_VERSION" \
    E 'test "$(sudo /usr/local/lib/opencode-permissions-kit/bin/opencode --version)" = "'"$OLD_VERSION"'"'
E 'sudo bash /home/dev/repo/files/update.sh --yes --binary-path /opencode-cache/opencode-'"$OC_VERSION"'/opencode' && \
    echo "  ${GREEN}OK${NC}  update.sh --binary-path completed"
check "upgrade: system binary is latest ($OC_VERSION)" \
    E 'test "$(sudo /usr/local/lib/opencode-permissions-kit/bin/opencode --version)" = "'"$OC_VERSION"'"'
check "upgrade: version actually changed" \
    E 'test "'"$OLD_VERSION"'" != "'"$OC_VERSION"'"'
check "wrapper still present after binary upgrade" E 'test -x /usr/local/bin/opencode'
check "binary still root:opencode after binary upgrade" \
    E 'test "$(stat -c %U:%G /usr/local/lib/opencode-permissions-kit/bin/opencode)" = "root:opencode"'
check "kit scripts still deployed after binary upgrade" E 'test -x /usr/local/lib/opencode-permissions-kit/update.sh'
check ".env still readable after binary upgrade (soft-only)" \
    E 'sudo -u opencode test -r /var/www/vhosts/test-project/.env'
check_fail "new binary writable by opencode user" \
    E 'sudo -u opencode sh -c "test -w /usr/local/lib/opencode-permissions-kit/bin/opencode"'

echo ""
echo "--- 12. config.sh adds a project non-interactively ---"
# extra-project carries a dev-owned .ddev to prove the projects-add handover
# (ddev always runs as the opencode user).
E 'sudo mkdir -p /var/www/vhosts/extra-project' && \
    E 'sudo touch /var/www/vhosts/extra-project/.env' && \
    E 'sudo mkdir -p /var/www/vhosts/extra-project/.ddev /var/www/vhosts/extra-project/config/system && sudo touch /var/www/vhosts/extra-project/.ddev/.webimageBuild && sudo sh -c "printf \"type: typo3\\n\" > /var/www/vhosts/extra-project/.ddev/config.yaml" && sudo sh -c "echo db > /var/www/vhosts/extra-project/config/system/settings.php"' && \
    E 'sudo chown -R dev:dev /var/www/vhosts/extra-project'
E 'sudo bash /usr/local/lib/opencode-permissions-kit/config.sh --yes projects add /var/www/vhosts/extra-project' && \
    echo "  ${GREEN}OK${NC}  config.sh add completed"
check "extra-project in projects.conf" \
    E 'grep -q /var/www/vhosts/extra-project /etc/opencode-permissions-kit/projects.conf'
check "extra-project group baseline applied (default ACL)" \
    E 'sudo getfacl -p -d /var/www/vhosts/extra-project | grep -q "group:opencode:rwx"'
check "extra-project .env readable (soft-only)" \
    E 'sudo -u opencode test -r /var/www/vhosts/extra-project/.env'
check "extra-project .ddev handed over to opencode" \
    E 'test "$(stat -c %U /var/www/vhosts/extra-project/.ddev)" = "opencode"'
check "extra-project .ddev group-writable" \
    E 'test "$(stat -c %a /var/www/vhosts/extra-project/.ddev/.webimageBuild)" = "664"'
check "extra-project typo3 settings dir handed over" \
    E 'test "$(stat -c %U /var/www/vhosts/extra-project/config/system)" = "opencode"'

echo ""
echo "--- 12b. config.sh projects remove ---"
E 'sudo bash /usr/local/lib/opencode-permissions-kit/config.sh --yes projects remove /var/www/vhosts/extra-project' && \
    echo "  ${GREEN}OK${NC}  config.sh remove completed"
check "extra-project removed from projects.conf" \
    E '! grep -q /var/www/vhosts/extra-project /etc/opencode-permissions-kit/projects.conf'

echo ""
echo "--- 12c. config.sh git-config toggle (soft-only) ---"
E 'sudo bash /usr/local/lib/opencode-permissions-kit/config.sh --yes git-config on' && \
    echo "  ${GREEN}OK${NC}  git-config on completed"
check "git-config ON: .git/config deny rule active" \
    E 'sudo grep -qE "^[[:space:]]*\"\.git/config\"" /home/opencode/.config/opencode/opencode.jsonc'
check "git-config ON: status reports ON" \
    E 'sudo bash /usr/local/lib/opencode-permissions-kit/config.sh git-config status 2>&1 | grep -q "ON"'
E 'sudo bash /usr/local/lib/opencode-permissions-kit/config.sh --yes git-config off' && \
    echo "  ${GREEN}OK${NC}  git-config off completed"
check "git-config OFF: no active .git/config rule" \
    E '! sudo grep -qE "^[[:space:]]*\"\.git/config\"" /home/opencode/.config/opencode/opencode.jsonc'
check "git-config OFF: status reports OFF" \
    E 'sudo bash /usr/local/lib/opencode-permissions-kit/config.sh git-config status 2>&1 | grep -q "OFF"'

echo ""
echo "--- 12c-2. install.sh re-run re-applies the git choice (re-install) ---"
# 12c left git-config OFF. A re-install without flags must NOT silently keep
# that stale agent config: the default (git blocked) is re-rendered from the
# template with the previous file backed up. Regression for the 2026-08-16
# live-test bug where the choice was ignored on re-install.
E 'sudo bash /home/dev/repo/files/install.sh --yes --container-backend podman-rootless --projects /var/www/vhosts --ddev-settings ddev' && \
    echo "  ${GREEN}OK${NC}  re-install completed"
check "re-install: default git-block re-applied to the existing agent config" \
    E 'sudo grep -qE "^[[:space:]]*\"\.git/config\"" /home/opencode/.config/opencode/opencode.jsonc'
# The backup dir is root:root 0700 (mktemp — it holds sudoers + gitconfigs),
# so the glob must be expanded by root's shell, not the dev shell running E.
check "re-install: previous agent config was backed up" \
    E "sudo sh -c 'ls /tmp/opencode-install-backup*/opencode.jsonc-existing >/dev/null 2>&1'"
check "re-install: config.sh status reports ON again" \
    E 'sudo bash /usr/local/lib/opencode-permissions-kit/config.sh git-config status 2>&1 | grep -q "ON"'

echo "--- 12c-3. install.sh argument validation (fail fast) ---"
check_fail "install.sh aborts on unknown flags" \
    E 'sudo bash /home/dev/repo/files/install.sh --bogus-flag >/dev/null 2>&1'
check "install.sh names the unknown flag in its error" \
    E 'sudo bash /home/dev/repo/files/install.sh --bogus-flag 2>&1 | grep -q "unknown option: --bogus-flag"'
check_fail "install.sh aborts on --container-backend without a value" \
    E 'sudo bash /home/dev/repo/files/install.sh --container-backend >/dev/null 2>&1'
check "kit still operational after rejected installs" \
    E 'test -x /usr/local/bin/opencode && id opencode'

echo ""
echo "--- 12d. config.sh interactive menu (displays) ---"
E 'sudo mkdir -p /var/www/vhosts/menu-project' && \
    E 'sudo touch /var/www/vhosts/menu-project/.env'
# The interactive menu uses read </dev/tty which blocks in a non-TTY
# environment. We capture whatever output appears within 3 seconds before
# timeout kills the process. At minimum the banner + current settings +
# projects list should print. The full menu options ([2], [3], [q]) may
# or may not appear depending on buffering and how far the script gets
# before the read blocks.
E 'timeout 3 sudo bash /usr/local/lib/opencode-permissions-kit/config.sh < /dev/null > /tmp/menu-out.txt 2>&1 || true'
E 'sudo chown dev /tmp/menu-out.txt'
check "menu: banner shown" \
    E 'grep -q "opencode permissions kit" /tmp/menu-out.txt'
check "menu: shows current settings" \
    E 'grep -q "Current settings" /tmp/menu-out.txt'
check "menu: project list shown" \
    E 'grep -q "Project roots" /tmp/menu-out.txt'
E 'sudo bash /usr/local/lib/opencode-permissions-kit/config.sh --yes projects remove /var/www/vhosts/menu-project'

echo ""
echo "--- 12e. wrapper directory validation ---"
E 'cd /var/www/vhosts/test-project && echo "" | /usr/local/bin/opencode --help 2>&1 | tee /tmp/wrapper-valid.txt' && \
    echo "  ${GREEN}OK${NC}  wrapper ran from valid CWD"
check "wrapper: SECURED banner from valid CWD" \
    E 'grep -q "SECURED BY opencode permissions kit" /tmp/wrapper-valid.txt'
# Invalid CWD: wrapper should refuse
E 'cd /tmp && /usr/local/bin/opencode 2>&1 | tee /tmp/wrapper-invalid.txt; test $? -ne 0' && \
    echo "  ${GREEN}OK${NC}  wrapper refused from invalid CWD"
check "wrapper: ERROR banner from invalid CWD" \
    E 'grep -q "ERROR: opencode cannot be started here" /tmp/wrapper-invalid.txt'
check_fail "wrapper does NOT stamp OPENCODE_LAUNCH_CWD (soft-only)" \
    E 'grep -q OPENCODE_LAUNCH_CWD /usr/local/lib/opencode-permissions-kit/wrapper'

echo ""
echo "--- 12e.2 wrapper serve mode (headless, third-party UIs like OpenChamber) ---"
# Third-party UIs spawn `opencode serve` with stdin ignored and parse stdout
# for the "opencode server listening" line — no banner, no prompts, and the
# project-dir refusal must not fire (OpenChamber often launches from $HOME).
# timeout(1) kills the server after it came up; exit 124 = it ran headless
# until then.
E 'cd /tmp && timeout 20 /usr/local/bin/opencode serve --hostname 127.0.0.1 --port 4199 > /tmp/wrapper-serve.out 2> /tmp/wrapper-serve.err; test $? -eq 124' && \
    echo "  ${GREEN}OK${NC}  wrapper serve ran headless from a non-project dir"
check "wrapper serve: opencode server listening line on stdout" \
    E 'grep -q "opencode server listening" /tmp/wrapper-serve.out'
check_fail "wrapper serve: no SECURED banner on stdout" \
    E 'grep -q "SECURED BY" /tmp/wrapper-serve.out'
check_fail "wrapper serve: no Press-Enter prompt on stdout" \
    E 'grep -q "Press Enter" /tmp/wrapper-serve.out'
E 'cd /var/www/vhosts/test-project && timeout 20 /usr/local/bin/opencode serve --hostname 127.0.0.1 --port 4198 > /tmp/wrapper-serve2.out 2>/dev/null; test $? -eq 124' && \
    echo "  ${GREEN}OK${NC}  wrapper serve ran headless from a project dir"
check "wrapper serve: listening line also from project dir" \
    E 'grep -q "opencode server listening" /tmp/wrapper-serve2.out'
check "wrapper serve: sudoers keep OPENCODE_SERVER_PASSWORD across sudo" \
    E 'sudo grep -q "OPENCODE_SERVER_PASSWORD" /etc/sudoers.d/opencode-permissions-kit'

echo "--- 12e.3 wrapper headless run (orchestrators: cezar, CI, eval harnesses — issue #42) ---"
# Orchestrators spawn `opencode run` from git worktrees / temp checkouts
# and parse stdout (`--format json`). The wrapper must neither refuse the
# non-project CWD nor print the banner on stdout. Without auth the binary
# errors quickly on stderr — the wrapper contract is about stdout staying
# machine-clean, which holds either way.
E 'cd /tmp && timeout 30 /usr/local/bin/opencode run --format json "say ok" > /tmp/wrapper-run.out 2> /tmp/wrapper-run.err; true'
check_fail "wrapper run from non-project dir: no project-dir refusal" \
    E 'grep -q "cannot be started here" /tmp/wrapper-run.out /tmp/wrapper-run.err'
check_fail "wrapper run: no SECURED banner on stdout" \
    E 'grep -q "SECURED BY" /tmp/wrapper-run.out'

echo ""
echo "--- 12f. uninstall.sh --dry-run (no-op) ---"
E 'bash /usr/local/lib/opencode-permissions-kit/uninstall.sh --yes --dry-run' && \
    echo "  ${GREEN}OK${NC}  uninstall --dry-run completed"
check "dry-run: wrapper still exists"   E 'test -e /usr/local/bin/opencode'
check "dry-run: library still exists"   E 'test -e /usr/local/lib/opencode-permissions-kit'
check "dry-run: /etc/opencode-permissions-kit intact"  E 'test -e /etc/opencode-permissions-kit'
check "dry-run: user still exists"      E 'id opencode'

echo ""
echo "--- 12g. Audit log ---"
check "log dir exists" \
    E 'sudo test -d /var/log/opencode-permissions-kit'
check "log file exists" \
    E 'sudo test -f /var/log/opencode-permissions-kit/opencode-permissions-kit.log'
check "log is root-owned mode 640" \
    E 'test "$(sudo stat -c %U:%a /var/log/opencode-permissions-kit/opencode-permissions-kit.log)" = "root:640"'
check "log dir is root-owned mode 750" \
    E 'test "$(sudo stat -c %U:%a /var/log/opencode-permissions-kit)" = "root:750"'
check "default user can read log file" \
    E 'test -r /var/log/opencode-permissions-kit/opencode-permissions-kit.log'
check "install events logged" \
    E 'sudo grep -q "install complete" /var/log/opencode-permissions-kit/opencode-permissions-kit.log'
check "update events logged" \
    E 'sudo grep -q "update complete" /var/log/opencode-permissions-kit/opencode-permissions-kit.log'
check "binary upgrade events logged" \
    E 'sudo grep -q "opencode binary upgraded" /var/log/opencode-permissions-kit/opencode-permissions-kit.log'
check_fail "opencode user cannot read log file" \
    E 'sudo -u opencode test -r /var/log/opencode-permissions-kit/opencode-permissions-kit.log'
check_fail "opencode user cannot enter log dir" \
    E 'sudo -u opencode test -x /var/log/opencode-permissions-kit'

echo ""
echo "--- 12i. Rootless container backend (podman) ---"
# Real-rootless environment test (docs/design/rootless-backend.md). In the
# soft-only model the §9.1 proof flips: containers run as the opencode host
# UID and CAN read the project files (the ddev-working goal) — but the uid_map
# still proves they are NOT real root.
#
# Rootless podman needs nested user namespaces + uidmap. The e2e container runs
# --privileged, which usually suffices, but some runner kernels disallow it.
# If `podman info` fails as the opencode user, every check in this section is
# SKIPped (not failed) so CI stays green.

_rootless_ok=true

# Nested-userns adaptation (only when the OUTER docker is rootless). On such a
# host this container itself runs in a user namespace (uid_map `0 <uid> 1 /
# 1 <n> 65536`), so the kit's default subuid allocation (231072+) is OUTSIDE
# the container's uid map and podman-rootless provisioning's `newuidmap` write
# fails with EPERM. Seeding an in-range range first works because
# setup-container-backend.sh's allocate_range() KEEPS an existing entry. No-op
# on a rootful host, which keeps CI on the kit's true default path.
if [ "$E2E_HOST_LAYOUT" = "rootless" ]; then
    echo "  ${CYAN}Nested userns (rootless host docker) — seeding in-range subuid/subgid${NC}"
    E 'sudo sh -c '\''printf "opencode:4096:60000\n" > /etc/subuid; printf "opencode:4096:60000\n" > /etc/subgid'\'''
    check "12i: in-range subuid/subgid seeded for opencode (nested layout)" \
        E 'grep -q "^opencode:4096:60000$" /etc/subuid && grep -q "^opencode:4096:60000$" /etc/subgid'
fi

# 12i.1 re-apply podman-rootless via config.sh (idempotent re-provision of the
# install-time backend; exercises the config.sh switch path).
if ! E 'sudo bash /home/dev/repo/files/config.sh --yes container-backend podman-rootless >/tmp/config-backend.log 2>&1'; then
    echo "  ${YELLOW}SKIP${NC}  12i: backend provisioning failed ($(E 'tail -1 /tmp/config-backend.log' 2>/dev/null || echo unknown))"
    _rootless_ok=false
    skipped=$((skipped + 1))
fi

# 12i.2 verify install.conf + sudoers state.
if [ "$_rootless_ok" = true ]; then
    check "12i: install.conf records CONTAINER_BACKEND=podman-rootless" \
        E 'grep -q "^CONTAINER_BACKEND=podman-rootless" /etc/opencode-permissions-kit/install.conf'
    check "12i: sudoers has no (opencode:docker) grant" \
        E '! sudo grep -q "opencode:docker" /etc/sudoers.d/opencode-permissions-kit'
    check "12i: sudoers keeps the base (opencode) RunAs" \
        E 'sudo grep -q "(opencode) NOPASSWD" /etc/sudoers.d/opencode-permissions-kit'
fi

# 12i.3 verify podman + subuid/subgid were provisioned by the setup helper.
if [ "$_rootless_ok" = true ]; then
    check "12i: podman installed by setup helper" \
        E 'command -v podman && podman --version'
    check "12i: subuid range allocated for opencode" \
        E 'grep -q "^opencode:" /etc/subuid'
    check "12i: subgid range allocated for opencode" \
        E 'grep -q "^opencode:" /etc/subgid'
fi

# 12i.4 rootless podman usable as the opencode user (nested userns check).
if [ "$_rootless_ok" = true ]; then
    E 'sudo mkdir -p /run/user/$(id -u opencode) && sudo chown opencode:opencode /run/user/$(id -u opencode) && sudo chmod 700 /run/user/$(id -u opencode)'
    if E 'cd /tmp && sudo -u opencode sh -c "XDG_RUNTIME_DIR=/run/user/$(id -u opencode) podman info >/tmp/podman-info.out 2>&1"'; then
        check "12i: rootless podman works as the opencode user (nested userns)" \
            E 'cd /tmp && sudo -u opencode sh -c "XDG_RUNTIME_DIR=/run/user/$(id -u opencode) podman info >/dev/null 2>&1"'
    else
        echo "  ${YELLOW}SKIP${NC}  12i: nested user namespaces not available ($(E 'tail -1 /tmp/podman-info.out' 2>/dev/null || echo unknown))"
        _rootless_ok=false
        skipped=$((skipped + 1))
    fi
fi

# 12i.5 the flipped §9.1 proof — soft-only model: a rootless container CAN
# read the project files (ddev goal), running as the opencode host UID.
if [ "$_rootless_ok" = true ]; then
    # Runs `podman run --rm alpine cat /app/<file>` as the opencode user and
    # greps the container output for <pattern>. Used as the check command so
    # the PASS/FAIL lines are not swallowed by the output pipe.
    container_cat_check() {
        E "cd /tmp && sudo -u opencode sh -c 'XDG_RUNTIME_DIR=/run/user/\$(id -u opencode) podman run --rm -v /var/www/vhosts/test-project:/app alpine:latest cat /app/$2'" | grep -q "$1"
    }
    if E 'cd /tmp && sudo -u opencode sh -c "XDG_RUNTIME_DIR=/run/user/$(id -u opencode) podman pull alpine:latest >/tmp/podman-pull.out 2>&1"'; then
        check "12i: rootless container CAN read .env via bind mount (soft-only, ddev-working goal)" \
            container_cat_check secret123 .env
        check "12i: rootless container CAN read settings.php via bind mount (ddev boots)" \
            container_cat_check hunter2 settings.php
        check "12i: rootless container CAN read index.php via bind mount" \
            container_cat_check "normal source code" index.php
    else
        echo "  ${YELLOW}SKIP${NC}  12i: could not pull alpine (no network?) — $(sudo tail -1 /tmp/podman-pull.out 2>/dev/null || echo unknown)"
        skipped=$((skipped + 2))
    fi
fi

# 12i.6 status.sh reports the provisioned podman-rootless backend.
if [ "$_rootless_ok" = true ]; then
    check "12i: status.sh reports the podman-rootless backend" \
        E '/usr/local/lib/opencode-permissions-kit/status.sh 2>&1 | grep -Eq "backend +podman-rootless"'
    check "12i: status.sh reports the podman CLI as installed" \
        E '/usr/local/lib/opencode-permissions-kit/status.sh 2>&1 | grep -Eq "podman CLI +installed"'
fi

# 12i.7 wrapper auto-detect on the podman-CLI path.
if [ "$_rootless_ok" = true ]; then
    E 'sudo tee /var/www/vhosts/test-project/opencode.jsonc > /dev/null <<EOF
{
    "permission": {
        "bash": { "docker *": "allow" }
    }
}
EOF'
    E 'cd /var/www/vhosts/test-project && /usr/local/bin/opencode --help 2>&1 | tee /tmp/wrapper-podman.txt' && \
        echo "  ${GREEN}OK${NC}  wrapper podman auto-detection ran"
    check "12i: wrapper podman auto-detect: container tools advisory" \
        E 'grep -q "Container tools enabled by this project" /tmp/wrapper-podman.txt'
    check "12i: wrapper podman auto-detect: no [Y/n] question (removed 0.0.21)" \
        E '! grep -q "? \[Y/n\]" /tmp/wrapper-podman.txt'
    check "12i: wrapper podman auto-detect: accepted -> podman-rootless exec message" \
        E 'grep -q "opencode will run with the podman-rootless backend" /tmp/wrapper-podman.txt'
    check_fail "12i: wrapper podman path does NOT mention the docker group" \
        E 'grep -q "opencode will run with the docker group" /tmp/wrapper-podman.txt'
    check "12i: opencode user NOT in the docker group (rootless grants no group)" \
        E '! id -nG opencode | tr " " "\n" | grep -qx docker'
fi

# 12i.8 config.sh container-backend status subcommand.
if [ "$_rootless_ok" = true ]; then
    check "12i: config.sh container-backend status reports podman-rootless" \
        E 'sudo bash /home/dev/repo/files/config.sh container-backend status 2>&1 | grep -q "podman-rootless"'
fi

# 12i.9 teardown the rootless runtime so section 13's uninstall can remove
# the opencode user (userdel -r fails while storage is live).
if [ "$_rootless_ok" = true ]; then
    E 'cd /tmp && sudo -u opencode sh -c "XDG_RUNTIME_DIR=/run/user/$(id -u opencode) podman system reset --force >/dev/null 2>&1" || true'
    E 'sudo pkill -u opencode 2>/dev/null || true'
    E 'sudo rm -rf /run/user/$(id -u opencode) /home/opencode/.local 2>/dev/null || true'
fi

echo ""
echo "--- 12j. status.sh leak scan (report-only, PROOF-3 H2) ---"
# Scratch copies matching the deny patterns must be reported; a renamed copy
# must stay invisible; and the scan must never touch files outside the
# project roots (no ACL, no delete — report-only).
E 'mkdir -p /tmp/leak-e2e/sub /tmp/leak-e2e-clean && printf "SECRET=1\n" > /tmp/leak-e2e/.env && printf "key\n" > /tmp/leak-e2e/sub/backup.pem && printf "<?php\n" > /tmp/leak-e2e/settings.php && printf "renamed copy\n" > /tmp/leak-e2e/notes.txt'
check "12j: leak scan section is printed" \
    E '/usr/local/lib/opencode-permissions-kit/status.sh 2>&1 | grep -q "Leak scan"'
check "12j: deny-pattern copy in /tmp is reported" \
    E '/usr/local/lib/opencode-permissions-kit/status.sh 2>&1 | grep -q "leak-e2e/.env"'
check "12j: nested deny-pattern copy is reported" \
    E '/usr/local/lib/opencode-permissions-kit/status.sh 2>&1 | grep -q "leak-e2e/sub/backup.pem"'
check "12j: hit counter is shown" \
    E '/usr/local/lib/opencode-permissions-kit/status.sh 2>&1 | grep -Eq "[0-9]+ match\(es\)"'
check_fail "12j: renamed copy stays invisible (name tripwire, no DLP)" \
    E '/usr/local/lib/opencode-permissions-kit/status.sh 2>&1 | grep -q "leak-e2e/notes.txt"'
check_fail "12j: report-only — no ACL is applied outside the roots" \
    E 'getfacl -p /tmp/leak-e2e/.env 2>/dev/null | grep -q "user:opencode"'
check "12j: LEAK_SCAN_DIRS override narrows the scan (clean dir -> no matches)" \
    E 'LEAK_SCAN_DIRS=/tmp/leak-e2e-clean /usr/local/lib/opencode-permissions-kit/status.sh 2>&1 | grep -q "no matches"'
check_fail "12j: LEAK_SCAN_DIRS override — hits outside the override are not reported" \
    E 'LEAK_SCAN_DIRS=/tmp/leak-e2e-clean /usr/local/lib/opencode-permissions-kit/status.sh 2>&1 | grep -q "leak-e2e/.env"'
check "12j: root run logs the finding to the audit log" \
    E 'sudo /usr/local/lib/opencode-permissions-kit/status.sh >/dev/null 2>&1; sudo grep -q "leak scan" /var/log/opencode-permissions-kit/opencode-permissions-kit.log'
E 'rm -rf /tmp/leak-e2e /tmp/leak-e2e-clean'

echo ""
echo "--- 13. Uninstall & cleanup verification ---"
E 'bash /usr/local/lib/opencode-permissions-kit/uninstall.sh --yes' && \
    echo "  ${GREEN}OK${NC}  uninstall.sh completed"
check_fail "Wrapper removed"          E 'test -e /usr/local/bin/opencode'
check_fail "Library removed"          E 'test -e /usr/local/lib/opencode-permissions-kit'
check_fail "Sudoers removed"          E 'test -e /etc/sudoers.d/opencode-permissions-kit'
check_fail "/etc/opencode-permissions-kit removed"    E 'test -e /etc/opencode-permissions-kit'
check_fail "Umask removed"            E 'test -e /etc/profile.d/opencode-permissions-kit-umask.sh'
check_fail "opencode user removed"    E 'id opencode'
check_fail "opencode usergroup removed (died with the user)" E 'getent group opencode'
check_fail "developer no longer in the opencode group" E 'id dev | grep -q opencode'
check_fail "/run/opencode-permissions-kit removed"    E 'test -e /run/opencode-permissions-kit'
check_fail "router-port sysctl file removed"          E 'test -e /etc/sysctl.d/99-ddev-rootless.conf'
check_fail "Project ACLs cleaned"     E 'getfacl -p /var/www/vhosts/test-project/.env 2>/dev/null | grep -q "user:opencode"'
check_fail "Audit log removed"        E 'test -e /var/log/opencode-permissions-kit'

e2e_finish
