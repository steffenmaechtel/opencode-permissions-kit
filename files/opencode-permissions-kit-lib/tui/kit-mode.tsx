/** @jsxImportSource @opentui/solid */
// opencode permissions kit -- TUI mode display (docs/design/plan-ui-tui-opencode.md)
//
// Renders the kit's container-tools state in the app_bottom slot
// (append mode: own thin row, visible on home + session screens):
//
//   opencode-permissions-kit Mode: with ddev/docker
//   opencode-permissions-kit Mode: no ddev/docker
//
// The mode is derived live from the kit's install.conf on every render
// (backend toggles via `config.sh container-backend` show up without a
// restart) and colors follow the user's own theme (theme.info /
// theme.textMuted). Everything is defensive: a broken plugin must
// never take the TUI down.
//
// Deployed to /usr/local/lib/opencode-permissions-kit/tui/kit-mode.tsx,
// registered by /home/opencode/.config/opencode/tui.json (kit-managed).
// Validated as a bare plugin against opencode 1.18.15/1.18.21 — loads
// with zero npm installs (JSX runtime + type imports resolve against
// opencode's own bundle; @opentui/* are optional peers).
import fs from "node:fs"
import type { TuiPlugin, TuiPluginModule } from "@opencode-ai/plugin/tui"

const CONF = "/etc/opencode-permissions-kit/install.conf"

// OPK_TUI_CONF allows tests to point the parser at a fixture conf.
function kitMode(confPath: string) {
  try {
    const conf = fs.readFileSync(confPath, "utf8")
    const backend = /^CONTAINER_BACKEND=(.+)$/m.exec(conf)?.[1]?.trim() ?? ""
    if (backend === "docker-rootless" || backend === "podman-rootless") return "with ddev/docker"
    return "no ddev/docker"
  } catch {
    return "no ddev/docker"
  }
}

const tui: TuiPlugin = async (api) => {
  api.slots.register({
    order: 50,
    slots: {
      app_bottom() {
        try {
          const confPath = process.env.OPK_TUI_CONF ?? CONF
          const mode = kitMode(confPath)
          const theme = api.theme.current
          const color = mode === "with ddev/docker" ? theme.info : theme.textMuted
          return (
            <box paddingLeft={2} paddingRight={2} paddingBottom={1} flexShrink={0}>
              <text fg={color}>opencode-permissions-kit Mode: {mode}</text>
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
