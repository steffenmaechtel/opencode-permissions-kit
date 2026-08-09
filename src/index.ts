/**
 * opencode permissions kit — Plugin
 *
 * Two modes:
 *   Install mode  — hardening not active, guides user through first-time install
 *   Hardened mode — protection active, provides status + diagnostics
 *
 * The npm package is used ONLY as an opencode plugin. The install/config/
 * update/uninstall shell scripts are bundled in `files/` and reached via the
 * plugin's own install path (import.meta.url) — no global npm install, no bin
 * symlinks.
 *
 * opencode v1 plugin API (v1.18.15+):
 *   - `config` hook registers the /permission-* slash commands so they are
 *     typeable + selectable in the TUI and reach the server command pipeline
 *   - `command.execute.before` replaces the (LLM-driven) command parts with a
 *     deterministic answer (the exact sudo command to run, status, etc.)
 *   - `event` hook observes session.created
 *   - `shell.env` exposes OPENCODE_HARDENED to spawned shells
 *
 * Install: opencode plugin install @steffenmaechtel/opencode-permissions-kit
 *     or: place plugin.ts in .opencode/plugins/
 */

import type { Config, Hooks, Plugin } from "@opencode-ai/plugin"
import { existsSync, readFileSync } from "node:fs"
import { fileURLToPath } from "node:url"
import { execSync } from "node:child_process"

// ── Script paths ────────────────────────────────────────────────────────────

function scriptPath(name: "install" | "uninstall" | "config" | "update"): string {
    if (name === "uninstall" && existsSync("/usr/local/lib/opencode/uninstall.sh")) {
        return "/usr/local/lib/opencode/uninstall.sh"
    }
    return fileURLToPath(new URL(`../files/${name}.sh`, import.meta.url))
}

// ── Version (single source: VERSION file) ────────────────────────────────────

function readVersion(): string {
    try {
        return readFileSync(new URL("../VERSION", import.meta.url), "utf-8").trim()
    } catch {
        return "0.0.0"
    }
}

const VERSION = readVersion()

// ── Types ────────────────────────────────────────────────────────────────────

type Mode = "install" | "hardened"

type CommandName =
    | "permission-status"
    | "permission-install"
    | "permission-config"
    | "permission-update"
    | "permission-uninstall"

const COMMAND_NAMES: CommandName[] = [
    "permission-status",
    "permission-install",
    "permission-config",
    "permission-update",
    "permission-uninstall",
]

interface ProtectionStats {
    mode: Mode
    userExists: boolean
    wrapperExists: boolean
    configFile: string | null
    projectsConf: string[]
    version: string | null
}

// ── Mode Detection ───────────────────────────────────────────────────────────

function detectMode(): Mode {
    const env = process.env.OPENCODE_HARDENED
    if (env === "1" || env === "true") return "hardened"

    try { execSync("id opencode", { stdio: "ignore" }) } catch { return "install" }

    if (!existsSync("/usr/local/bin/opencode")) return "install"

    return "hardened"
}

// ── Protection Stats ─────────────────────────────────────────────────────────

function getStats(): ProtectionStats {
    const mode = detectMode()

    let userExists = false
    try { execSync("id opencode", { stdio: "ignore" }); userExists = true } catch {}

    const wrapperExists = existsSync("/usr/local/bin/opencode")

    let configFile: string | null = null
    if (existsSync("/home/opencode/.config/opencode/opencode.jsonc")) {
        configFile = "/home/opencode/.config/opencode/opencode.jsonc"
    } else if (existsSync("/home/opencode/.config/opencode/opencode.json")) {
        configFile = "/home/opencode/.config/opencode/opencode.json"
    }

    const projectsConf: string[] = []
    try {
        if (existsSync("/etc/opencode/projects.conf")) {
            const content = readFileSync("/etc/opencode/projects.conf", "utf-8")
            projectsConf.push(...content.split("\n").map(s => s.trim()).filter(Boolean))
        }
    } catch {}

    let version: string | null = null
    try {
        if (existsSync("/usr/local/lib/opencode/.cache")) {
            const cache = readFileSync("/usr/local/lib/opencode/.cache", "utf-8")
            const m = cache.match(/config_mtime=(\d+)/)
            if (m) version = "active"
        }
    } catch {}

    return { mode, userExists, wrapperExists, configFile, projectsConf, version }
}

// ── Command definitions (registered via the config hook) ─────────────────────

function commandDefinitions(): NonNullable<Config["command"]> {
    return {
        "permission-install": {
            description: "Install the opencode permissions kit",
            template: [
                `The user wants to install the opencode permissions kit.`,
                `Tell them to run this command in a separate terminal (it needs sudo):`,
                ``,
                `    sudo bash ${scriptPath("install")}`,
                ``,
                `Optional flags: --yes  --projects /path/to/project.`,
                `After the install completes, the user must restart opencode.`,
            ].join("\n"),
        },
        "permission-config": {
            description: "Change permissions kit settings (projects, git-config, ACL refresh)",
            template: [
                `The user wants to change permissions kit settings.`,
                `Tell them to run this command in a separate terminal (it needs sudo):`,
                ``,
                `    sudo bash ${scriptPath("config")}`,
                ``,
                `Or non-interactively:`,
                `    sudo bash ${scriptPath("config")} projects add /var/www/vhosts/new-project`,
                `    sudo bash ${scriptPath("config")} projects remove /var/www/vhosts/old-project`,
                `    sudo bash ${scriptPath("config")} git-config on|off|status`,
                `    sudo bash ${scriptPath("config")} refresh`,
            ].join("\n"),
        },
        "permission-update": {
            description: "Re-deploy the permissions kit after a git pull",
            template: [
                `The user wants to re-deploy the permissions kit after an update.`,
                `Tell them to run this command in a separate terminal (it needs sudo):`,
                ``,
                `    sudo bash ${scriptPath("update")}`,
                ``,
                `Optional flags: --yes  --refresh (re-applies ACLs after deploy).`,
            ].join("\n"),
        },
        "permission-status": {
            description: "Show permissions kit status and diagnostics",
            template: `Show the permissions kit status (mode, user, wrapper, config, projects).`,
        },
        "permission-uninstall": {
            description: "Remove the opencode permissions kit",
            template: [
                `The user wants to remove the opencode permissions kit.`,
                `Tell them to run this command in a separate terminal:`,
                ``,
                `    bash ${scriptPath("uninstall")}`,
                ``,
                `Optional flags: --yes  --dry-run  --debug.`,
            ].join("\n"),
        },
    }
}

// ── Deterministic command output (injected via command.execute.before) ───────

function isCommandName(name: string): name is CommandName {
    return (COMMAND_NAMES as readonly string[]).includes(name)
}

function commandText(name: string): string | null {
    if (!isCommandName(name)) return null
    const stats = getStats()

    switch (name) {
        case "permission-status": {
            if (stats.mode === "hardened") {
                return [
                    `Permission-Control v${VERSION} (hardened)`,
                    `  User: opencode ${stats.userExists ? "exists" : "MISSING"}`,
                    `  Wrapper: ${stats.wrapperExists ? "/usr/local/bin/opencode" : "MISSING"}`,
                    `  Config: ${stats.configFile || "none"}`,
                    `  Projects: ${stats.projectsConf.length} (${stats.projectsConf.join(", ") || "none"})`,
                    `  Cache: ${stats.version || "none"}`,
                ].join("\n")
            }
            return [
                `Permission-Control v${VERSION} (not installed)`,
                `  Hardening not active.`,
                `  Run /permission-install for the hardening command.`,
            ].join("\n")
        }

        case "permission-install": {
            if (stats.mode === "hardened") {
                return [
                    `Permission-Control v${VERSION} — already hardened`,
                    `  User: opencode exists, wrapper at /usr/local/bin/opencode`,
                    `  To change settings (projects, git-config): /permission-config`,
                    `  To re-deploy the kit after an update:       /permission-update`,
                    `  To add projects manually: edit /etc/opencode/projects.conf and run`,
                    `      sudo /usr/local/lib/opencode/protect-projects.sh --force`,
                ].join("\n")
            }
            return [
                `Permission-Control v${VERSION} — install`,
                ``,
                `  Run this command in a terminal (it needs sudo):`,
                ``,
                `      sudo bash ${scriptPath("install")}`,
                ``,
                `  Optional flags: --yes  --projects /path/to/project`,
                `  After install completes, restart opencode.`,
            ].join("\n")
        }

        case "permission-config": {
            if (stats.mode !== "hardened") {
                return [
                    `Permission-Control v${VERSION} — not installed`,
                    `  Run /permission-install first.`,
                ].join("\n")
            }
            return [
                `Permission-Control v${VERSION} — config`,
                ``,
                `  Change settings (project roots, .git/config hardening, ACL refresh):`,
                ``,
                `      sudo bash ${scriptPath("config")}`,
                ``,
                `  Or non-interactive:`,
                `      sudo bash ${scriptPath("config")} projects add /var/www/vhosts/new-project`,
                `      sudo bash ${scriptPath("config")} projects remove /var/www/vhosts/old-project`,
                `      sudo bash ${scriptPath("config")} git-config on|off|status`,
                `      sudo bash ${scriptPath("config")} refresh`,
            ].join("\n")
        }

        case "permission-update": {
            if (stats.mode !== "hardened") {
                return [
                    `Permission-Control v${VERSION} — not installed`,
                    `  Run /permission-install first.`,
                ].join("\n")
            }
            return [
                `Permission-Control v${VERSION} — update`,
                ``,
                `  Re-deploys the kit (wrapper, hooks, sudoers, umask) without touching`,
                `  existing projects.conf, install.conf, opencode.jsonc, or the binary.`,
                ``,
                `  Run this command in a terminal (it needs sudo):`,
                ``,
                `      sudo bash ${scriptPath("update")}`,
                ``,
                `  Optional flags: --yes  --refresh  (re-applies ACLs after deploy)`,
            ].join("\n")
        }

        case "permission-uninstall": {
            return [
                `Permission-Control v${VERSION} — uninstall`,
                ``,
                `  Run this command in a terminal (without sudo prefix):`,
                ``,
                `      bash ${scriptPath("uninstall")}`,
                ``,
                `  Optional flags: --yes  --dry-run  --debug`,
            ].join("\n")
        }
    }
    return null
}

// ── Plugin ───────────────────────────────────────────────────────────────────

export const PermissionKit: Plugin = async ({ client, directory }) => {
    const mode = detectMode()

    if (mode === "install") {
        await client.app.log({
            body: {
                service: "permission-kit",
                level: "warn",
                message: "opencode is NOT hardened. Use /permission-install to get the hardening command.",
                extra: { directory },
            },
        })

        process.stderr.write(`
╔══════════════════════════════════════════════╗
║  opencode permissions kit                    ║
║                                              ║
║  opencode is running with full filesystem    ║
║  access. Harden it via:                      ║
║                                              ║
║    /permission-install                       ║
║                                              ║
║  This will:                                  ║
║  • Create a dedicated 'opencode' user        ║
║  • Deny access to .env, keys, settings       ║
║  • Install a secure wrapper + git hooks      ║
║                                              ║
║  After install restart opencode.             ║
╚══════════════════════════════════════════════╝
`)
    }

    const hooks: Hooks = {
        // ── Register slash commands so /permission-* are real commands ────
        config: async (cfg) => {
            cfg.command = { ...cfg.command, ...commandDefinitions() }
        },

        // ── Events ────────────────────────────────────────────────────────
        event: async ({ event }) => {
            if (event.type !== "session.created") return
            if (mode !== "hardened") return

            const stats = getStats()
            await client.app.log({
                body: {
                    service: "permission-kit",
                    level: "info",
                    message: `Hardened mode active. Projects: ${stats.projectsConf.length}. Config: ${stats.configFile || "none"}`,
                    extra: stats as unknown as Record<string, unknown>,
                },
            })
        },

        // ── Replace command parts with deterministic output ───────────────
        "command.execute.before": async (input, output) => {
            const text = commandText(input.command)
            if (text === null) return
            output.parts.length = 0
            output.parts.push({ type: "text", text } as any)
        },

        "shell.env": async (input, output) => {
            if (mode === "hardened") {
                output.env.OPENCODE_HARDENED = "1"
            }
        },
    }

    return hooks
}
