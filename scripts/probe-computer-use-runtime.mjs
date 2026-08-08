import { isAbsolute } from "node:path";
import { pathToFileURL } from "node:url";

const entryArgument = process.argv[2];
if (!entryArgument) {
  throw new Error("usage: node probe-computer-use-runtime.mjs <sky-entry-path-or-url>");
}

globalThis.nodeRepl = {
  config: {},
  nativePipe: {},
  env: {
    NODE_REPL_NODE_MODULE_DIRS:
      process.env.NODE_REPL_NODE_MODULE_DIRS ?? process.env.NODE_PATH ?? "",
  },
  notify: () => {},
};

const entryUrl = isAbsolute(entryArgument)
  ? pathToFileURL(entryArgument).href
  : entryArgument;
const mod = await import(entryUrl);
if (typeof mod.sky !== "object" || mod.sky === null) {
  throw new Error("sky export is missing");
}
if (typeof mod.sky.list_windows !== "function") {
  throw new Error("sky.list_windows export is missing");
}

const windows = await mod.sky.list_windows();
if (!Array.isArray(windows)) {
  throw new Error(`sky.list_windows returned ${typeof windows}`);
}

const invalidIndexes = windows.flatMap((window, index) => {
  const valid =
    window != null &&
    typeof window === "object" &&
    typeof window.app === "string" &&
    window.app.trim().length > 0 &&
    Number.isInteger(window.id) &&
    window.id >= 0;
  return valid ? [] : [index];
});
if (invalidIndexes.length > 0) {
  throw new Error(
    `sky.list_windows violated the Window contract at indexes ${invalidIndexes.join(",")}; ` +
      "window.app must be non-empty and window.id must be a non-negative integer",
  );
}

console.log(
  JSON.stringify({
    ok: true,
    exports: Object.keys(mod).sort(),
    method: "list_windows",
    resultType: "array",
    count: windows.length,
    windowContract: true,
    invalidWindowCount: 0,
  }),
);
