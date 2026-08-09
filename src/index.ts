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
 * Install: opencode plugin install @steffenmaechtel/opencode-permissions-kit
 *     or: place plugin.ts in .opencode/plugins/
 */

import type { Plugin } from "@opencode-ai/plugin"
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

// ── Plugin ───────────────────────────────────────────────────────────────────

export const PermissionKit: Plugin = async ({ client, directory }) => {
    const mode = detectMode()

    if (mode === "install") {
        // ── Install Mode (not yet hardened) ──────────────────────────────────
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

    return {
        // ── Events ──────────────────────────────────────────────────────────

        "shell.env": async (input, output) => {
            if (mode === "hardened") {
                output.env.OPENCODE_HARDENED = "1"
            }
        },

        "session.created": async () => {
            if (mode === "hardened") {
                const stats = getStats()
                await client.app.log({
                    body: {
                        service: "permission-kit",
                        level: "info",
                        message: `Hardened mode active. Projects: ${stats.projectsConf.length}. Config: ${stats.configFile || "none"}`,
                        extra: stats,
                    },
                })
            }
        },

        "tui.command.execute": async (input) => {
            switch (input.command) {
                case "permission-status": {
                    input.command = null // suppress original
                    const stats = getStats()
                    if (stats.mode === "hardened") {
                        console.log(`Permission-Control v${VERSION} (hardened)`)
                        console.log(`  User: opencode ${stats.userExists ? "exists" : "MISSING"}`)
                        console.log(`  Wrapper: ${stats.wrapperExists ? "/usr/local/bin/opencode" : "MISSING"}`)
                        console.log(`  Config: ${stats.configFile || "none"}`)
                        console.log(`  Projects: ${stats.projectsConf.length} (${stats.projectsConf.join(", ") || "none"})`)
                        console.log(`  Cache: ${stats.version || "none"}`)
                    } else {
                        console.log(`Permission-Control v${VERSION} (not installed)`)
                        console.log("  Hardening not active.")
                        console.log("  Run /permission-install for the hardening command.")
                    }
                    break
                }

                case "permission-install": {
                    input.command = null // suppress original
                    const stats = getStats()
                    if (stats.mode === "hardened") {
                        console.log(`Permission-Control v${VERSION} — already hardened`)
                        console.log("  User: opencode exists, wrapper at /usr/local/bin/opencode")
                        console.log("  To change settings (projects, git-config): /permission-config")
                        console.log("  To re-deploy the kit after an update:       /permission-update")
                        console.log("  To add projects manually: edit /etc/opencode/projects.conf and run")
                        console.log("      sudo /usr/local/lib/opencode/protect-projects.sh --force")
                    } else {
                        const cmd = scriptPath("install")
                        console.log(`Permission-Control v${VERSION} — install`)
                        console.log("")
                        console.log("  Run this command in a terminal (it needs sudo):")
                        console.log("")
                        console.log(`      sudo bash ${cmd}`)
                        console.log("")
                        console.log("  Optional flags: --yes  --projects /path/to/project")
                        console.log("  After install completes, restart opencode.")
                    }
                    break
                }

                case "permission-config": {
                    input.command = null // suppress original
                    const stats = getStats()
                    if (stats.mode !== "hardened") {
                        console.log(`Permission-Control v${VERSION} — not installed`)
                        console.log("  Run /permission-install first.")
                        break
                    }
                    const cmd = scriptPath("config")
                    console.log(`Permission-Control v${VERSION} — config`)
                    console.log("")
                    console.log("  Change settings (project roots, .git/config hardening, ACL refresh):")
                    console.log("")
                    console.log(`      sudo bash ${cmd}`)
                    console.log("")
                    console.log("  Or non-interactive:")
                    console.log(`      sudo bash ${cmd} projects add /var/www/vhosts/new-project`)
                    console.log(`      sudo bash ${cmd} projects remove /var/www/vhosts/old-project`)
                    console.log(`      sudo bash ${cmd} git-config on|off|status`)
                    console.log(`      sudo bash ${cmd} refresh`)
                    break
                }

                case "permission-update": {
                    input.command = null // suppress original
                    const stats = getStats()
                    if (stats.mode !== "hardened") {
                        console.log(`Permission-Control v${VERSION} — not installed`)
                        console.log("  Run /permission-install first.")
                        break
                    }
                    const cmd = scriptPath("update")
                    console.log(`Permission-Control v${VERSION} — update`)
                    console.log("")
                    console.log("  Re-deploys the kit (wrapper, hooks, sudoers, umask) without touching")
                    console.log("  existing projects.conf, install.conf, opencode.jsonc, or the binary.")
                    console.log("")
                    console.log("  Run this command in a terminal (it needs sudo):")
                    console.log("")
                    console.log(`      sudo bash ${cmd}`)
                    console.log("")
                    console.log("  Optional flags: --yes  --refresh  (re-applies ACLs after deploy)")
                    break
                }

                case "permission-uninstall": {
                    input.command = null // suppress original
                    const cmd = scriptPath("uninstall")
                    console.log(`Permission-Control v${VERSION} — uninstall`)
                    console.log("")
                    console.log("  Run this command in a terminal (without sudo prefix):")
                    console.log("")
                    console.log(`      bash ${cmd}`)
                    console.log("")
                    console.log("  Optional flags: --yes  --dry-run  --debug")
                    break
                }
            }
        },
    }
}
