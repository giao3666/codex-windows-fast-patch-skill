import { EventEmitter } from "node:events";
import { createConnection } from "node:net";
import { isAbsolute } from "node:path";
import { pathToFileURL } from "node:url";

const clientArgument = process.argv[2];
const nodeModulesArgument = process.argv[3];
const mode = process.argv[4] ?? "fixture";
const pipePath = process.argv[5] ?? "\\\\.\\pipe\\codex-computer-use-fixture";

if (!clientArgument || !nodeModulesArgument) {
  throw new Error(
    "usage: node probe-computer-use-client.mjs <client-path> <node-modules> [fixture|pipe] [pipe-path]",
  );
}
if (mode !== "fixture" && mode !== "pipe") {
  throw new Error(`unsupported Computer Use client probe mode: ${mode}`);
}

function frame(message) {
  const payload = Buffer.from(JSON.stringify(message), "utf8");
  const result = Buffer.alloc(4 + payload.length);
  result.writeUInt32LE(payload.length, 0);
  payload.copy(result, 4);
  return result;
}

function parseFrame(buffer) {
  if (buffer.length < 4) {
    return null;
  }
  const length = buffer.readUInt32LE(0);
  if (buffer.length < 4 + length) {
    return null;
  }
  return {
    message: JSON.parse(buffer.subarray(4, 4 + length).toString("utf8")),
    remaining: buffer.subarray(4 + length),
  };
}

function createFixtureSocket() {
  const socket = new EventEmitter();
  let pending = Buffer.alloc(0);
  let ended = false;
  socket.write = (chunk) => {
    pending = Buffer.concat([pending, Buffer.from(chunk)]);
    queueMicrotask(() => {
      while (!ended) {
        const decoded = parseFrame(pending);
        if (decoded == null) {
          break;
        }
        pending = decoded.remaining;
        const request = decoded.message;
        const requestedMethod = request?.params?.method;
        const result =
          requestedMethod === "list_windows"
            ? [{ app: "msedge.exe", id: 7, title: "fixture-only" }]
            : null;
        socket.emit("data", frame({
          id: request.id,
          jsonrpc: "2.0",
          result,
        }));
      }
    });
    return true;
  };
  socket.end = () => {
    if (ended) {
      return;
    }
    ended = true;
    queueMicrotask(() => socket.emit("close"));
  };
  return socket;
}

const nativePipe = {
  createConnection: (requestedPath) => {
    if (mode === "fixture") {
      if (requestedPath !== pipePath) {
        throw new Error(`fixture pipe path mismatch: ${requestedPath}`);
      }
      return createFixtureSocket();
    }
    return createConnection(requestedPath);
  },
};

globalThis.nodeRepl = {
  config: {},
  nativePipe,
  env: {
    NODE_REPL_NODE_MODULE_DIRS: nodeModulesArgument,
    SKY_CUA_NATIVE_PIPE_DIRECTORY: pipePath,
  },
  setResponseMeta: () => {},
};

const clientUrl = isAbsolute(clientArgument)
  ? pathToFileURL(clientArgument).href
  : clientArgument;
const client = await import(clientUrl);
if (typeof client.setupComputerUseRuntime !== "function") {
  throw new Error("setupComputerUseRuntime export is missing");
}

const setupResult = await client.setupComputerUseRuntime();
const sky = setupResult ?? globalThis.sky;
if (sky == null || globalThis.sky !== sky) {
  throw new Error("setupComputerUseRuntime did not install globalThis.sky");
}
if (typeof sky?.list_windows !== "function") {
  throw new Error("setupComputerUseRuntime did not expose sky.list_windows");
}

try {
  const windows = await sky.list_windows();
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

  console.log(JSON.stringify({
    ok: true,
    mode,
    setupCalled: true,
    method: "list_windows",
    count: windows.length,
    windowContract: true,
    invalidWindowCount: 0,
  }));
} finally {
  if (typeof sky.close === "function") {
    await sky.close();
  }
}
