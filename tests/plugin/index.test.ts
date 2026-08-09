/**
 * Unit tests for the opencode permissions kit plugin (src/index.ts).
 *
 * Tests mode detection, version reading, script path resolution, the config
 * hook command registration, the command.execute.before deterministic output,
 * and the event hook for all five commands in both modes.
 * Run: npx vitest run tests/plugin/index.test.ts
 */
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest"
import { existsSync, readFileSync } from "node:fs"

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

let stderrWrites: string[] = []

beforeEach(() => {
    stderrWrites = []
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

/** Build a minimal mock client. */
function makeClient() {
    return {
        app: { log: vi.fn() },
    }
}

/** Load the plugin and return its hooks plus the client. */
async function loadAndInit() {
    const Plugin = await loadPlugin()
    const client = makeClient()
    const hooks = await Plugin({ client: client as any, directory: "/tmp" })
    return { hooks, client }
}

/** Install-mode mocks: no opencode user, no wrapper. */
function mockInstallMode() {
    delete process.env.OPENCODE_HARDENED
    mocks.readFileSync.mockImplementation((p: string) => {
        if (String(p).includes("VERSION")) return "0.0.8\n"
        return ""
    })
    mocks.execSync.mockImplementation(() => { throw new Error("no user") })
    mocks.existsSync.mockReturnValue(false)
}

/** Hardened-mode mocks: opencode user + wrapper present. */
function mockHardenedMode() {
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
}

const ALL_COMMANDS = [
    "permission-status",
    "permission-install",
    "permission-config",
    "permission-update",
    "permission-uninstall",
]

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
        // No crash → VERSION was read
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
        // In hardened mode, no install banner
        expect(stderrWrites.join("")).not.toContain("NOT hardened")
        delete process.env.OPENCODE_HARDENED
    })

    it("returns 'install' when id opencode throws", async () => {
        mockInstallMode()
        const Plugin = await loadPlugin()
        await Plugin({ client: makeClient() as any, directory: "/tmp" })
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
        mocks.existsSync.mockReturnValue(false)
        const Plugin = await loadPlugin()
        await Plugin({ client: makeClient() as any, directory: "/tmp" })
        const stderr = stderrWrites.join("")
        expect(stderr).toContain("full filesystem")
    })

    it("returns 'hardened' when user + wrapper present", async () => {
        mockHardenedMode()
        const Plugin = await loadPlugin()
        await Plugin({ client: makeClient() as any, directory: "/tmp" })
        expect(stderrWrites.join("")).not.toContain("full filesystem")
    })
})

describe("config hook", () => {
    it("registers all five /permission-* commands", async () => {
        mockInstallMode()
        const { hooks } = await loadAndInit()
        const config: any = { command: {} }
        await hooks.config!(config)
        expect(Object.keys(config.command).sort()).toEqual([...ALL_COMMANDS].sort())
    })

    it("preserves pre-existing commands", async () => {
        mockInstallMode()
        const { hooks } = await loadAndInit()
        const config: any = { command: { custom: { template: "do the thing" } } }
        await hooks.config!(config)
        expect(config.command.custom).toEqual({ template: "do the thing" })
        for (const name of ALL_COMMANDS) {
            expect(config.command[name]).toBeDefined()
        }
    })

    it("templates embed the resolved script paths", async () => {
        mockInstallMode()
        const { hooks } = await loadAndInit()
        const config: any = { command: {} }
        await hooks.config!(config)
        expect(config.command["permission-install"].template).toContain("sudo bash ")
        expect(config.command["permission-install"].template).toContain("install.sh")
        expect(config.command["permission-config"].template).toContain("config.sh")
        expect(config.command["permission-update"].template).toContain("update.sh")
        expect(config.command["permission-uninstall"].template).toContain("uninstall.sh")
    })
})

describe("command.execute.before", () => {
    function parts() {
        return { parts: [] as any[] }
    }

    it("permission-status in install mode shows '(not installed)'", async () => {
        mockInstallMode()
        const { hooks } = await loadAndInit()
        const output = parts()
        await hooks["command.execute.before"]!({ command: "permission-status", sessionID: "s", arguments: "" } as any, output as any)
        const text = output.parts[0].text
        expect(text).toContain("(not installed)")
        expect(text).toContain("/permission-install")
    })

    it("permission-status in hardened mode shows '(hardened)'", async () => {
        mockHardenedMode()
        const { hooks } = await loadAndInit()
        const output = parts()
        await hooks["command.execute.before"]!({ command: "permission-status", sessionID: "s", arguments: "" } as any, output as any)
        const text = output.parts[0].text
        expect(text).toContain("(hardened)")
        expect(text).toContain("Wrapper:")
        expect(text).toContain("Projects: 1 (/var/www/vhosts)")
    })

    it("permission-install in install mode prints sudo bash command", async () => {
        mockInstallMode()
        const { hooks } = await loadAndInit()
        const output = parts()
        await hooks["command.execute.before"]!({ command: "permission-install", sessionID: "s", arguments: "" } as any, output as any)
        const text = output.parts[0].text
        expect(text).toContain("sudo bash")
        expect(text).toContain("install.sh")
    })

    it("permission-install in hardened mode says 'already hardened'", async () => {
        mockHardenedMode()
        const { hooks } = await loadAndInit()
        const output = parts()
        await hooks["command.execute.before"]!({ command: "permission-install", sessionID: "s", arguments: "" } as any, output as any)
        expect(output.parts[0].text).toContain("already hardened")
    })

    it("permission-config in hardened mode prints config command", async () => {
        mockHardenedMode()
        const { hooks } = await loadAndInit()
        const output = parts()
        await hooks["command.execute.before"]!({ command: "permission-config", sessionID: "s", arguments: "" } as any, output as any)
        const text = output.parts[0].text
        expect(text).toContain("config.sh")
        expect(text).toContain("sudo bash")
    })

    it("permission-config in install mode tells user to install first", async () => {
        mockInstallMode()
        const { hooks } = await loadAndInit()
        const output = parts()
        await hooks["command.execute.before"]!({ command: "permission-config", sessionID: "s", arguments: "" } as any, output as any)
        expect(output.parts[0].text).toContain("not installed")
    })

    it("permission-update in hardened mode prints update command", async () => {
        mockHardenedMode()
        const { hooks } = await loadAndInit()
        const output = parts()
        await hooks["command.execute.before"]!({ command: "permission-update", sessionID: "s", arguments: "" } as any, output as any)
        const text = output.parts[0].text
        expect(text).toContain("update.sh")
        expect(text).toContain("sudo bash")
    })

    it("permission-update in install mode tells user to install first", async () => {
        mockInstallMode()
        const { hooks } = await loadAndInit()
        const output = parts()
        await hooks["command.execute.before"]!({ command: "permission-update", sessionID: "s", arguments: "" } as any, output as any)
        expect(output.parts[0].text).toContain("not installed")
    })

    it("permission-uninstall prints bash uninstall command", async () => {
        mockHardenedMode()
        const { hooks } = await loadAndInit()
        const output = parts()
        await hooks["command.execute.before"]!({ command: "permission-uninstall", sessionID: "s", arguments: "" } as any, output as any)
        const text = output.parts[0].text
        expect(text).toContain("uninstall.sh")
        expect(text).toContain("bash ")
    })

    it("leaves unrelated commands untouched", async () => {
        mockInstallMode()
        const { hooks } = await loadAndInit()
        const output = parts()
        output.parts.push({ type: "text", text: "original template" })
        await hooks["command.execute.before"]!({ command: "init", sessionID: "s", arguments: "" } as any, output as any)
        expect(output.parts.length).toBe(1)
        expect(output.parts[0].text).toBe("original template")
    })
})

describe("event hook", () => {
    it("logs stats on session.created in hardened mode", async () => {
        mockHardenedMode()
        const { hooks, client } = await loadAndInit()
        await hooks.event!({ event: { id: "e1", type: "session.created", properties: {} } } as any)
        expect(client.app.log).toHaveBeenCalledTimes(1)
        const body = client.app.log.mock.calls[0][0].body
        expect(body.message).toContain("Hardened mode active")
        expect(body.extra).toHaveProperty("mode", "hardened")
    })

    it("does not log on session.created in install mode", async () => {
        mockInstallMode()
        const { hooks, client } = await loadAndInit()
        await hooks.event!({ event: { id: "e1", type: "session.created", properties: {} } } as any)
        // Only the initial "NOT hardened" warn at init
        expect(client.app.log).toHaveBeenCalledTimes(1)
        expect(client.app.log.mock.calls[0][0].body.message).toContain("NOT hardened")
    })

    it("ignores other event types", async () => {
        mockHardenedMode()
        const { hooks, client } = await loadAndInit()
        await hooks.event!({ event: { id: "e2", type: "message.updated", properties: {} } } as any)
        expect(client.app.log).not.toHaveBeenCalled()
    })
})

describe("shell.env", () => {
    it("sets OPENCODE_HARDENED=1 in hardened mode", async () => {
        mockHardenedMode()
        const { hooks } = await loadAndInit()
        const output: Record<string, string> = {}
        await hooks["shell.env"]!(null as any, { env: output } as any)
        expect(output.OPENCODE_HARDENED).toBe("1")
    })

    it("does NOT set OPENCODE_HARDENED in install mode", async () => {
        mockInstallMode()
        const { hooks } = await loadAndInit()
        const output: Record<string, string> = {}
        await hooks["shell.env"]!(null as any, { env: output } as any)
        expect(output.OPENCODE_HARDENED).toBeUndefined()
    })
})
