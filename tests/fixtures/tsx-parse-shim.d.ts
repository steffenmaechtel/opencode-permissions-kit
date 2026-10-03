// Ambient shims for the CI TSX parse gate (tests/tsx-syntax-gate.sh,
// issue #114 / review 0.0.39a C5, TSX half). The shipped tui/*.tsx
// assets import opencode-internal modules whose type declarations are
// not part of this repo — a full type check is impossible by design,
// the gate is parse-only. Without these shims tsc would report:
//   TS2307  unresolved module imports (node:fs, node:os, ...)
//   TS2580  'process' (that declaration lives in @types/node,
//           deliberately not installed)
//   TS2875  the jsx-runtime module of the files' @jsxImportSource
//           pragma (@opentui/solid)
//   TS2709  shorthand wildcard exports cannot be used in type position —
//           hence the two concrete plugin module bodies overriding the
//           wildcard; their members are the only type-position imports
// If an asset starts importing new symbols in type position, extend the
// module bodies here; value imports need nothing (the wildcard covers
// them). This file must stay free of top-level exports/imports —
// otherwise it becomes a module and its ambient declarations stop
// applying globally.
declare module "*"
declare module "@opencode-ai/plugin/tui" {
    export type TuiPlugin = any
    export type TuiPluginModule = any
}
declare module "@opencode/plugin/tui" {
    export const Plugin: any
}
declare const process: any
