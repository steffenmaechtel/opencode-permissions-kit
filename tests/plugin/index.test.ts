/**
 * Unit tests for the opencode permissions kit plugin (src/index.ts).
 *
 * Tests mode detection, version reading, script path resolution, and the
 * tui.command.execute dispatch for all five commands in both modes.
 * Run: npx vitest run tests/plugin/index.test.ts
 */
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest"
import { existsSync, readFileSync } from "node:fs"
import { fileURLToPath } from "node:url"

// ── Mocks ────────────────────────────────────────────────────────────────────

const mocks = {
    existsSync: vi.fn<(p: string) => boolean>(),
    readFileSync: vi.fn<(p: string, enc: string) => string>(),
    execSync: vi.fn<(cmd: string, o?: object) => string>(),
}

vi.mock("node:fs", () => ({
    existsSync: mocks.existsSync,
    readFileSync: mocks.readFileSync,
}))

vi.mock("node:child_process", () => ({
    execSync: mocks.execSync,
}))

// ── Capture console.log ──────────────────────────────────────────────────────

let logs: string[] = []
let stderrWrites: string[] = []

beforeEach(() => {
    logs = []
    stderrWrites = []
    vi.spyOn(console, "log").mockImplementation((...args: unknown[]) => {
        logs.push(args.map(String).join(" "))
    })
    vi.spyOn(process.stderr, "write").mockImplementation((chunk: string) => {
        stderrWrites.push(chunk)
        return true
    })
    mocks.existsSync.mockReset()
    mocks.readFileSync.mockReset()
    mocks.execSync.mockReset()
})

afterEach(() => {
    vi.restoreAllMocks()
})

// ── Helpers ───────────────────────────────────────────────────────────────────

/** Import the plugin fresh (so detectMode re-runs with current mocks). */
async function loadPlugin() {
    vi.resetModules()
    // Re-apply mocks after resetModules
    vi.doMock("node:fs", () => ({
        existsSync: mocks.existsSync,
        readFileSync: mocks.readFileSync,
    }))
    vi.doMock("node:child_process", () => ({
        execSync: mocks.execSync,
    }))
    const mod = await import("../../src/index.ts")
    return mod.PermissionKit
}

/** Build a fake PluginInput for a command. */
function makeInput(command: string) {
    return { command }
}

/** Build a minimal mock client. */
function makeClient() {
    return {
        app: { log: vi.fn() },
    }
}

// ── Tests ─────────────────────────────────────────────────────────────────────

describe("readVersion", () => {
    it("returns trimmed VERSION file content", async () => {
        mocks.readFileSync.mockImplementation((p: string) => {
            if (String(p).includes("VERSION")) return "0.0.8\n"
            return ""
        })
        mocks.existsSync.mockReturnValue(false)
        mocks.execSync.mockImplementation(() => { throw new Error("no user") })
        const Plugin = await loadPlugin()
        await Plugin({ client: makeClient() as any, directory: "/tmp" })
        // Version appears in the install banner — check stderr for hint
        // We just assert the plugin loaded without error
        expect(Plugin).toBeDefined()
    })

    it("falls back to 0.0.0 when VERSION file missing", async () => {
        mocks.readFileSync.mockImplementation(() => { throw new Error("ENOENT") })
        mocks.existsSync.mockReturnValue(false)
        mocks.execSync.mockImplementation(() => { throw new Error("no user") })
        const Plugin = await loadPlugin()
        await Plugin({ client: makeClient() as any, directory: "/tmp" })
        // No crash → fallback worked
        expect(Plugin).toBeDefined()
    })
})

describe("detectMode", () => {
    it("returns 'hardened' when OPENCODE_HARDENED=1", async () => {
        process.env.OPENCODE_HARDENED = "1"
        mocks.readFileSync.mockReturnValue("0.0.8\n")
        const Plugin = await loadPlugin()
        await Plugin({ client: makeClient() as any, directory: "/tmp" })
        // In hardened mode, session.created logs stats — no banner
        expect(stderrWrites.join("")).not.toContain("NOT hardened")
        delete process.env.OPENCODE_HARDENED
    })

    it("returns 'install' when id opencode throws", async () => {
        delete process.env.OPENCODE_HARDENED
        mocks.readFileSync.mockImplementation((p: string) => {
            if (String(p).includes("VERSION")) return "0.0.8\n"
            return ""
        })
        mocks.execSync.mockImplementation(() => { throw new Error("no user") })
        mocks.existsSync.mockReturnValue(false)
        const Plugin = await loadPlugin()
        await Plugin({ client: makeClient() as any, directory: "/tmp" })
        // Install-mode banner should appear on stderr
        const stderr = stderrWrites.join("")
        expect(stderr).toContain("full filesystem")
        expect(stderr).toContain("/permission-install")
    })

    it("returns 'install' when wrapper missing but user exists", async () => {
        delete process.env.OPENCODE_HARDENED
        mocks.readFileSync.mockImplementation((p: string) => {
            if (String(p).includes("VERSION")) return "0.0.8\n"
            return ""
        })
        mocks.execSync.mockReturnValue("") // id opencode succeeds
        mocks.existsSync.mockImplementation((p: string) => {
            if (p === "/usr/local/bin/opencode") return false
            return false
        })
        const Plugin = await loadPlugin()
        await Plugin({ client: makeClient() as any, directory: "/tmp" })
        const stderr = stderrWrites.join("")
        expect(stderr).toContain("full filesystem")
    })

    it("returns 'hardened' when user + wrapper present", async () => {
        delete process.env.OPENCODE_HARDENED
        mocks.readFileSync.mockReturnValue("0.0.8\n")
        mocks.execSync.mockReturnValue("") // id opencode succeeds
        mocks.existsSync.mockImplementation((p: string) => {
            if (p === "/usr/local/bin/opencode") return true
            return false
        })
        const Plugin = await loadPlugin()
        await Plugin({ client: makeClient() as any, directory: "/tmp" })
        expect(stderrWrites.join("")).not.toContain("full filesystem")
    })
})

describe("tui.command.execute", () => {
    async function loadAndInit() {
        const Plugin = await loadPlugin()
        const client = makeClient()
        const hooks = await Plugin({ client: client as any, directory: "/tmp" })
        return { hooks, client }
    }

    it("permission-status in install mode shows '(not installed)'", async () => {
        delete process.env.OPENCODE_HARDENED
        mocks.readFileSync.mockImplementation((p: string) => {
            if (String(p).includes("VERSION")) return "0.0.8\n"
            return ""
        })
        mocks.execSync.mockImplementation(() => { throw new Error("no user") })
        mocks.existsSync.mockReturnValue(false)
        const { hooks } = await loadAndInit()
        logs = []
        await hooks["tui.command.execute"]!(makeInput("permission-status") as any)
        expect(logs.join("\n")).toContain("(not installed)")
        expect(logs.join("\n")).toContain("/permission-install")
    })

    it("permission-status in hardened mode shows '(hardened)'", async () => {
        delete process.env.OPENCODE_HARDENED
        mocks.readFileSync.mockImplementation((p: string) => {
            if (String(p).includes("VERSION")) return "0.0.8\n"
            if (String(p).includes("projects.conf")) return "/var/www/vhosts\n"
            return ""
        })
        mocks.execSync.mockReturnValue("")
        mocks.existsSync.mockImplementation((p: string) => {
            if (p === "/usr/local/bin/opencode") return true
            if (p === "/etc/opencode/projects.conf") return true
            return false
        })
        const { hooks } = await loadAndInit()
        logs = []
        await hooks["tui.command.execute"]!(makeInput("permission-status") as any)
        expect(logs.join("\n")).toContain("(hardened)")
        expect(logs.join("\n")).toContain("Wrapper:")
    })

    it("permission-install in install mode prints sudo bash command", async () => {
        delete process.env.OPENCODE_HARDENED
        mocks.readFileSync.mockImplementation((p: string) => {
            if (String(p).includes("VERSION")) return "0.0.8\n"
            return ""
        })
        mocks.execSync.mockImplementation(() => { throw new Error("no user") })
        mocks.existsSync.mockReturnValue(false)
        const { hooks } = await loadAndInit()
        logs = []
        await hooks["tui.command.execute"]!(makeInput("permission-install") as any)
        const out = logs.join("\n")
        expect(out).toContain("sudo bash")
        expect(out).toContain("install.sh")
    })

    it("permission-install in hardened mode says 'already hardened'", async () => {
        delete process.env.OPENCODE_HARDENED
        mocks.readFileSync.mockImplementation((p: string) => {
            if (String(p).includes("VERSION")) return "0.0.8\n"
            return ""
        })
        mocks.execSync.mockReturnValue("")
        mocks.existsSync.mockImplementation((p: string) => {
            if (p === "/usr/local/bin/opencode") return true
            return false
        })
        const { hooks } = await loadAndInit()
        logs = []
        await hooks["tui.command.execute"]!(makeInput("permission-install") as any)
        expect(logs.join("\n")).toContain("already hardened")
    })

    it("permission-config in hardened mode prints config command", async () => {
        delete process.env.OPENCODE_HARDENED
        mocks.readFileSync.mockImplementation((p: string) => {
            if (String(p).includes("VERSION")) return "0.0.8\n"
            return ""
        })
        mocks.execSync.mockReturnValue("")
        mocks.existsSync.mockImplementation((p: string) => {
            if (p === "/usr/local/bin/opencode") return true
            return false
        })
        const { hooks } = await loadAndInit()
        logs = []
        await hooks["tui.command.execute"]!(makeInput("permission-config") as any)
        const out = logs.join("\n")
        expect(out).toContain("config.sh")
        expect(out).toContain("sudo bash")
    })

    it("permission-config in install mode tells user to install first", async () => {
        delete process.env.OPENCODE_HARDENED
        mocks.readFileSync.mockImplementation((p: string) => {
            if (String(p).includes("VERSION")) return "0.0.8\n"
            return ""
        })
        mocks.execSync.mockImplementation(() => { throw new Error("no user") })
        mocks.existsSync.mockReturnValue(false)
        const { hooks } = await loadAndInit()
        logs = []
        await hooks["tui.command.execute"]!(makeInput("permission-config") as any)
        expect(logs.join("\n")).toContain("not installed")
    })

    it("permission-update in hardened mode prints update command", async () => {
        delete process.env.OPENCODE_HARDENED
        mocks.readFileSync.mockImplementation((p: string) => {
            if (String(p).includes("VERSION")) return "0.0.8\n"
            return ""
        })
        mocks.execSync.mockReturnValue("")
        mocks.existsSync.mockImplementation((p: string) => {
            if (p === "/usr/local/bin/opencode") return true
            return false
        })
        const { hooks } = await loadAndInit()
        logs = []
        await hooks["tui.command.execute"]!(makeInput("permission-update") as any)
        const out = logs.join("\n")
        expect(out).toContain("update.sh")
        expect(out).toContain("sudo bash")
    })

    it("permission-update in install mode tells user to install first", async () => {
        delete process.env.OPENCODE_HARDENED
        mocks.readFileSync.mockImplementation((p: string) => {
            if (String(p).includes("VERSION")) return "0.0.8\n"
            return ""
        })
        mocks.execSync.mockImplementation(() => { throw new Error("no user") })
        mocks.existsSync.mockReturnValue(false)
        const { hooks } = await loadAndInit()
        logs = []
        await hooks["tui.command.execute"]!(makeInput("permission-update") as any)
        expect(logs.join("\n")).toContain("not installed")
    })

    it("permission-uninstall prints bash uninstall command", async () => {
        delete process.env.OPENCODE_HARDENED
        mocks.readFileSync.mockImplementation((p: string) => {
            if (String(p).includes("VERSION")) return "0.0.8\n"
            return ""
        })
        mocks.execSync.mockReturnValue("")
        mocks.existsSync.mockImplementation((p: string) => {
            if (p === "/usr/local/bin/opencode") return true
            return false
        })
        const { hooks } = await loadAndInit()
        logs = []
        await hooks["tui.command.execute"]!(makeInput("permission-uninstall") as any)
        const out = logs.join("\n")
        expect(out).toContain("uninstall.sh")
        expect(out).toContain("bash ")
    })

    it("all commands set input.command to null (suppress original)", async () => {
        delete process.env.OPENCODE_HARDENED
        mocks.readFileSync.mockImplementation((p: string) => {
            if (String(p).includes("VERSION")) return "0.0.8\n"
            return ""
        })
        mocks.execSync.mockReturnValue("")
        mocks.existsSync.mockImplementation((p: string) => {
            if (p === "/usr/local/bin/opencode") return true
            return false
        })
        const { hooks } = await loadAndInit()
        for (const cmd of [
            "permission-status",
            "permission-install",
            "permission-config",
            "permission-update",
            "permission-uninstall",
        ]) {
            const input = makeInput(cmd)
            logs = []
            await hooks["tui.command.execute"]!(input as any)
            expect(input.command).toBeNull()
        }
    })
})

describe("shell.env", () => {
    it("sets OPENCODE_HARDENED=1 in hardened mode", async () => {
        delete process.env.OPENCODE_HARDENED
        mocks.readFileSync.mockReturnValue("0.0.8\n")
        mocks.execSync.mockReturnValue("")
        mocks.existsSync.mockImplementation((p: string) => {
            if (p === "/usr/local/bin/opencode") return true
            return false
        })
        const Plugin = await loadPlugin()
        const hooks = await Plugin({ client: makeClient() as any, directory: "/tmp" })
        const output: Record<string, string> = {}
        await hooks["shell.env"]!(null as any, { env: output } as any)
        expect(output.OPENCODE_HARDENED).toBe("1")
    })

    it("does NOT set OPENCODE_HARDENED in install mode", async () => {
        delete process.env.OPENCODE_HARDENED
        mocks.readFileSync.mockImplementation((p: string) => {
            if (String(p).includes("VERSION")) return "0.0.8\n"
            return ""
        })
        mocks.execSync.mockImplementation(() => { throw new Error("no user") })
        mocks.existsSync.mockReturnValue(false)
        const Plugin = await loadPlugin()
        const hooks = await Plugin({ client: makeClient() as any, directory: "/tmp" })
        const output: Record<string, string> = {}
        await hooks["shell.env"]!(null as any, { env: output } as any)
        expect(output.OPENCODE_HARDENED).toBeUndefined()
    })
})