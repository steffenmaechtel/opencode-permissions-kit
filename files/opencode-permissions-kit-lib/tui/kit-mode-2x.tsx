/** @jsxImportSource @opentui/solid */
// opencode permissions kit -- TUI mode display, opencode 2.x CLI plugin
// (docs/design/opencode-2x.md; the v1 counterpart is kit-mode.tsx)
//
// Renders the kit's container-tools state inline in the built-in footer
// rows (home screen and session prompt):
//
//   opencode-permissions-kit (0.0.34) Mode: with ddev/docker
//   opencode-permissions-kit (0.0.34) Mode: no ddev/docker
//
// Bypass case (the TUI does NOT run as the kit's opencode user — e.g.
// the original binary started as the developer): a loud warning instead,
// in the theme's error color:
//
//   WARNING UNSECURE (bypass of opencode-permissions-kit detected)
//
// Same contract as the v1 plugin: the mode is derived live from the
// kit's install.conf on every render (backend toggles via `config.sh
// container-backend` show up without a restart), the version comes from
// the same file's VERSION= stamp (644 root:root, readable by everyone),
// and bypass detection compares the process user (os.userInfo — the
// real uid, immune to env spoofing) against install.conf's OPENCODE_USER.
// Colors follow the user's own theme tokens (text.subdued /
// text.feedback.info.default / text.feedback.error.default). Everything
// is defensive: a broken plugin must never take the TUI down.
//
// Deployed to /usr/local/lib/opencode-permissions-kit/tui/kit-mode-2x.tsx,
// registered as a plugins entry in ~/.config/opencode/cli.json (opencode
// user AND default user, additively — managed by py/tui-register.py,
// gated on OPENCODE_MAJOR=2). The v1 plugin API does not run on 2.x
// ("moving a file is not enough" — opencode 2 migration guide), hence
// this port; `import { Plugin } from "@opencode/plugin/tui"` resolves
// against opencode's own bundle at runtime, and absolute package paths
// are supported plugin sources, so this loads as a bare file with zero
// npm installs. Validated against opencode 2.0.6.
import fs from "node:fs"
import os from "node:os"
import { Plugin } from "@opencode/plugin/tui"

const CONF = "/etc/opencode-permissions-kit/install.conf"

const WARNING = "WARNING UNSECURE (bypass of opencode-permissions-kit detected)"

// OPK_TUI_CONF allows tests to point the parser at a fixture conf.
function kitState(confPath: string) {
  let backend = ""
  let version = ""
  let opencodeUser = ""
  try {
    const conf = fs.readFileSync(confPath, "utf8")
    backend = /^CONTAINER_BACKEND=(.+)$/m.exec(conf)?.[1]?.trim() ?? ""
    version = /^VERSION=(.+)$/m.exec(conf)?.[1]?.trim() ?? ""
    opencodeUser = /^OPENCODE_USER=(.+)$/m.exec(conf)?.[1]?.trim() ?? ""
  } catch {
    // unreadable/missing install.conf: no kit facts, treat as no-backend
  }
  let bypass = false
  try {
    if (opencodeUser) bypass = os.userInfo().username !== opencodeUser
  } catch {
    // userInfo failing: assume the normal (non-bypass) case
  }
  const mode = backend === "docker-rootless" || backend === "podman-rootless" ? "with ddev/docker" : "no ddev/docker"
  return { mode, version, bypass }
}

export default Plugin.define({
  id: "opencode-permissions-kit-mode",
  setup(context) {
    const render = () => {
      try {
        const confPath = process.env.OPK_TUI_CONF ?? CONF
        const { mode, version, bypass } = kitState(confPath)
        const theme = context.theme
        if (bypass) {
          return <text fg={theme.text.feedback.error.default}>{WARNING}</text>
        }
        const color = mode === "with ddev/docker" ? theme.text.feedback.info.default : theme.text.subdued
        const prefix = version ? `opencode-permissions-kit (${version})` : "opencode-permissions-kit"
        return (
          <text fg={color}>
            {prefix} Mode: {mode}
          </text>
        )
      } catch {
        return <text></text>
      }
    }
    // One row per screen (v1 parity): the home screen carries BOTH footers —
    // the prompt composer's status hint (which wraps narrow) and the home
    // footer — so the prompt slot renders only inside a session (its input
    // has a sessionID there) and the home slot covers the home screen.
    context.ui.slot({ append: "home.footer.status", render })
    context.ui.slot({
      append: "prompt.footer.status",
      render: (input) => (input?.sessionID ? render() : <text></text>),
    })
  },
})
