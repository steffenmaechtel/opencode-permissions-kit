/** @jsxImportSource @opentui/solid */
// opencode permissions kit -- TUI mode display (docs/design/plan-ui-tui-opencode.md)
//
// Renders the kit's container-tools state in the app_bottom slot
// (append mode: own thin row, visible on home + session screens):
//
//   opencode-permissions-kit (0.0.21) Mode: with ddev/docker
//   opencode-permissions-kit (0.0.21) Mode: no ddev/docker
//
// Bypass case (the TUI does NOT run as the kit's opencode user — e.g.
// the original binary started as the developer): a loud warning row
// instead, in the theme's error color (the default user additionally
// carries the red opencode-danger theme):
//
//   WARNING UNSECURE (bypass of opencode-permissions-kit detected)
//
// The mode is derived live from the kit's install.conf on every render
// (backend toggles via `config.sh container-backend` show up without a
// restart), the version comes from the same file's VERSION= stamp
// (install.conf is the canonical kit stamp, 644 root:root — readable by
// the opencode user; LIBDIR carries no VERSION file). Bypass detection
// compares the process user (os.userInfo — the real uid, immune to env
// spoofing) against install.conf's OPENCODE_USER. Colors follow the
// user's own theme (theme.info / theme.textMuted / theme.error).
// Everything is defensive: a broken plugin must never take the TUI
// down.
//
// Deployed to /usr/local/lib/opencode-permissions-kit/tui/kit-mode.tsx,
// registered by /home/opencode/.config/opencode/tui.json AND the
// default user's ~/.config/opencode/tui.json (kit-managed). Validated
// as a bare plugin against opencode 1.18.15/1.18.21 — loads with zero
// npm installs (JSX runtime + type imports resolve against opencode's
// own bundle; @opentui/* are optional peers).
import fs from "node:fs"
import os from "node:os"
import type { TuiPlugin, TuiPluginModule } from "@opencode-ai/plugin/tui"

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

const tui: TuiPlugin = async (api) => {
  api.slots.register({
    order: 50,
    slots: {
      app_bottom() {
        try {
          const confPath = process.env.OPK_TUI_CONF ?? CONF
          const { mode, version, bypass } = kitState(confPath)
          const theme = api.theme.current
          if (bypass) {
            return (
              <box paddingLeft={2} paddingRight={2} paddingBottom={1} flexShrink={0}>
                <text fg={theme.error}>{WARNING}</text>
              </box>
            )
          }
          const color = mode === "with ddev/docker" ? theme.info : theme.textMuted
          const prefix = version ? `opencode-permissions-kit (${version})` : "opencode-permissions-kit"
          return (
            <box paddingLeft={2} paddingRight={2} paddingBottom={1} flexShrink={0}>
              <text fg={color}>{prefix} Mode: {mode}</text>
            </box>
          )
        } catch {
          return undefined
        }
      },
    },
  })
}

const plugin: TuiPluginModule & { id: string } = {
  id: "opencode-permissions-kit-mode",
  tui,
}

export default plugin
