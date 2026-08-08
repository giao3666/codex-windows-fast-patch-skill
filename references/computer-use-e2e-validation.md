# Computer Use End-to-End Validation

Read this reference when local Computer Use repair succeeds but real app control is still unproven, when initialization works only after a phrase such as `Initialize Computer Use sky`, when `window.app` or `window.id` validation fails, or when the user asks for proof that Computer Use works end to end.

## Evidence levels

Keep these levels separate. Never use a lower level to claim a higher one passed.

| Level | Required evidence | What it proves |
|---|---|---|
| Local files | Marketplace, cache, native-host config, and current runtime identity pass | Files and configuration are internally consistent |
| Runtime API | The current package-matching runtime imports `sky`, calls `list_windows`, and validates every returned Window | The local helper/runtime API is callable |
| Desktop bootstrap | The current Desktop launch has a live `codex-computer-use-*` pipe and startup-correlated logs report `computer-use native pipe startup ready` | Desktop initialized its Computer Use channel |
| Plugin tool injection | A fresh Desktop task invokes the bundled Computer Use skill in a trusted `node_repl`/Code Mode host | The task received the real plugin tool path |
| Read-only app observation | A returned Window is rehydrated and `get_window_state` returns a non-empty screenshot or requested accessibility state | Window selection and capture work |
| Controlled action | The plugin activates the target and performs one safe action, then a fresh observation proves the result | Real UI control works |
| Browser smoke test | Chrome/Edge reaches `https://example.com/` and the plugin reads its URL, title, unique `h1`, and heading text | Native host, extension, browser client, and page inspection work together |
| Provider-native Computer Use | A Responses-compatible provider emits a real `computer_call`, accepts its tool result, and completes a second turn | That provider supports the native Computer Use protocol |

PowerShell `Start-Process`, Win32 `SendKeys`, generic screenshots, or another automation framework may be useful fallbacks, but they are not evidence for the plugin levels above.

## Establish a current baseline

Record the following before repair:

- UTC start time and the current Codex Desktop package version, signature kind, install path, process ID, and process start time.
- SHA-256 of `config.toml` and the stable `openai-bundled` marketplace source. Do not print credentials or unrelated configuration values.
- Current bundled plugin versions and installed/enabled state.
- Current user-local Codex CLI and CUA runtime IDs. Accept only files that match the installed package by length and SHA-256; do not choose a runtime merely because its directory is newest.
- Counts for current negative markers: `bundled_executable_relocation_failed`, `computer-use native pipe startup failed`, `bundled_plugins_reconcile_failed`, and `already added from a different source`.

Do not carry forward an earlier run's success. Store upgrades can change the package, runtime ID, plugin descriptors, and native-host paths.

## Repair and restart sequence

1. Run `scripts\install-computer-use-local.ps1 -VerifyOnly`. This mode may repair local state.
2. Run it again with `-StrictVerifyOnly` after Codex Desktop is fully running. Strict mode is read-only and now requires a live Desktop Computer Use pipe by default.
3. Use `-SkipDesktopPipeCheck` only for offline fixtures or CI that intentionally has no Desktop process. A result obtained with this switch is local-only evidence.
4. If runtime files were repaired or Desktop had cleaned an old runtime, rerun `-VerifyOnly` so Chrome's `extension-host-config.json` is repointed, then rerun strict verification.
5. If the current package-matching user-local runtime is missing, inspect the current launch for `bundled_executable_relocation_failed`. Do not fall back to an old runtime or execute protected WindowsApps binaries.

Strict verification must report all of the following before moving on:

- A current package-matching Codex CLI and CUA runtime ID.
- `computer_use=true` plus an enabled trusted host (`code_mode_host` or, on older builds, `code_mode`). Never enable removed `js_repl` features.
- Valid local marketplace/config/native-host/cache state.
- `list_windows` success with zero invalid Window objects.
- A live Desktop native pipe unless the explicit offline-test switch was used.

This still does not prove tool injection, screenshots, or UI actions.

## Correlate Desktop startup evidence

Inspect events from the same package path, process ID/process UUID, and launch window recorded in the baseline. Require a positive `computer-use native pipe startup ready` after launch. Treat any later `computer-use native pipe startup failed`, `bundled_executable_relocation_failed`, or marketplace-source conflict from that same process as a failure that needs explanation.

Do not search `%USERPROFILE%\.codex\logs_2.sqlite` for marker text and count every hit. Prompts, tool commands, copied audit reports, and transport traces can contain the same strings. Use event target, timestamp, process identity, package path, and the original event body to exclude echoed text.

For marketplace validation, parsed `config.toml` must contain one `marketplaces.openai-bundled` table pointing to the stable local source. After a Desktop restart, current-process logs must no longer report that `openai-bundled` was added from a different source. Do not delete `.tmp` blindly; first identify which source the current Desktop process is reconciling.

## Validate the trusted bootstrap

The bootstrap depends on the installed plugin layout:

- Current descriptor-only layouts import `{ sky }` from `@oai/sky` inside the trusted Desktop `node_repl` host.
- Legacy layouts call the plugin's `setupComputerUseRuntime()` inside that trusted host, then call `sky.list_windows()` through the Desktop-created native pipe. The local verifier must exercise that standard wrapper path and report `client wrapper ok (pipe)`; importing the export or probing a separate helper transport does not prove wrapper initialization.
- `scripts\probe-computer-use-client.mjs` supports a deliberately labelled `fixture` mode for offline regression tests. Fixture output is local-only evidence and must never be recorded as Desktop bootstrap.

An ordinary external Node process is not equivalent to the trusted Desktop host. `Windows Computer Use Sky runtime is unavailable` from a direct external import does not prove the Desktop path is broken.

If a phrase such as `Initialize Computer Use sky` makes a fresh task work, record it as a bootstrap diagnostic and compare successful and failed task logs for tool injection, dynamic tools, native-pipe, and Sky initialization events. Do not make the phrase the permanent fix and do not call it success until a real plugin observation/action passes.

## Regress the Window contract and a real action

Use the bundled Computer Use skill's current guidance and API documentation. Then:

1. Call `list_windows()` and keep the returned objects unchanged.
2. Require every candidate to have a non-empty string `app` and an integer `id >= 0`.
3. Filter to the intended app and stop unless exactly one returned Window remains.
4. Rehydrate only with `{ app, id }` copied from that Window. Never guess, reconstruct, or coerce an ID from unrelated fields.
5. Call `get_window_state` first with the minimum needed output. For screenshot acceptance, require at least one current screenshot ID and a non-empty captured frame without logging image data.
6. Activate the same returned Window, perform one safe action, and immediately capture a fresh state. Do not reuse screenshot IDs, coordinates, or accessibility indexes after state changes.

This is the dedicated regression for `window.app must be a non-empty string and window.id must be an integer >= 0`. A successful `list_windows` call without these steps is insufficient.

## Run the controlled browser smoke test

After native-host configuration passes, use the actual Chrome/browser plugin path:

1. Open a fresh controlled tab at `https://example.com/`.
2. Read and record the final URL and the exact title `Example Domain`.
3. Require exactly one `h1` whose text is `Example Domain`.
4. Record that the extension/native-host connection was used. Do not substitute PowerShell navigation or CDP from an unrelated process.

Run broader ChatGPT or third-party site navigation only after this deterministic smoke test passes.

## Separate local plugin proof from provider proof

The bundled local plugin can operate through trusted Code Mode/`node_repl`; this path may not emit a Responses API `computer_call`. Prove it with recorded plugin tool calls plus real Window observations/actions.

Test provider-native Computer Use separately. Ask for a screenshot-only action, require an actual `computer_call`, return the tool result, and require a successful second response. A normal `/v1/responses` call, `/v1/models` listing, timeout, 502, or closed connection does not prove native Computer Use support. Compare with a known-compatible provider to separate local failures from provider/proxy schema failures.

## Write the audit result

Write new reports as UTF-8 without BOM and leave source logs unchanged. Include:

- Start/end timestamps, package/process/runtime identity, and whether strict mode used the offline pipe bypass.
- Before/after counts for windows, invalid Window objects, native-pipe readiness, screenshots, navigation, marketplace sources, and current-process error markers.
- For each action: target Window `{app,id}`, action name, result, raw Sky error category, retry count, and user-facing explanation. Do not include screenshot payloads, page secrets, tokens, or unrelated titles.
- Separate statuses for `local-runtime`, `desktop-bootstrap`, `plugin-injection`, `window-capture`, `controlled-action`, `browser-smoke`, and `provider-native`.

Use `passed`, `failed`, or `not-tested` for every status. Never summarize a partial result as "Computer Use fully fixed."
