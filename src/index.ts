/**
 * opencode permissions kit — Plugin
 *
 * Two modes:
 *   Setup mode  — hardening not active, guides user through first-time setup
 *   Hardened mode — protection active, provides status + diagnostics
 *
 * Install: opencode plugin install @steffenmaechtel/opencode-permissions-kit
 *     or: place plugin.ts in .opencode/plugins/
 */

import type { Plugin } from "@opencode-ai/plugin"
import { existsSync, readFileSync } from "node:fs"
import { execSync } from "node:child_process"

// ── Types ────────────────────────────────────────────────────────────────────

type Mode = "setup" | "hardened"

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

    try { execSync("id opencode", { stdio: "ignore" }) } catch { return "setup" }

    if (!existsSync("/usr/local/bin/opencode")) return "setup"

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

export const PermissionKit: Plugin = async ({ client, $, directory }) => {
    const mode = detectMode()

    if (mode === "setup") {
        // ── Setup Mode ──────────────────────────────────────────────────────
        await client.app.log({
            body: {
                service: "permission-kit",
                level: "warn",
                message: "openCode is NOT hardened. Run setup.sh to enable Linux-ACL protection.",
                extra: { directory },
            },
        })

        console.log(`
╔══════════════════════════════════════════════╗
║  opencode permissions kit                    ║
║                                              ║
║  openCode is running with full filesystem    ║
║  access. Harden it via:                      ║
║                                              ║
║    sudo ./files/setup.sh                     ║
║                                              ║
║  This will:                                  ║
║  • Create a dedicated 'opencode' user        ║
║  • Deny access to .env, keys, settings       ║
║  • Install a secure wrapper + git hooks      ║
║                                              ║
║  After setup restart openCode.               ║
╚══════════════════════════════════════════════╝
        `.trim())
        process.exit(0)
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
            if (input.command === "permission-status") {
                const stats = getStats()
                input.command = null // suppress original

                if (stats.mode === "hardened") {
                    console.log("Permission-Control v0.0.2 (hardened)")
                    console.log(`  User: opencode ${stats.userExists ? "exists" : "MISSING"}`)
                    console.log(`  Wrapper: ${stats.wrapperExists ? "/usr/local/bin/opencode" : "MISSING"}`)
                    console.log(`  Config: ${stats.configFile || "none"}`)
                    console.log(`  Projects: ${stats.projectsConf.length} (${stats.projectsConf.join(", ") || "none"})`)
                    console.log(`  Cache: ${stats.version || "none"}`)
                } else {
                    console.log("Permission-Control (setup mode)")
                    console.log("  Hardening not active.")
                    console.log("  Run: cd <repo> && sudo ./files/setup.sh")
                }
            }
        },
    }
}
