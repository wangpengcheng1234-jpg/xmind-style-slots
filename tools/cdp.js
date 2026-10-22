// 通过 CDP 在 Xmind 渲染进程里执行 JS / 模拟真实按键，用于零风险调试
// 用法:
//   node cdp.js --match <url片段> --eval "<表达式>" | --file <js文件>
//   node cdp.js --match <url片段> --key ctrl+alt+1 [--eval "<表达式>"]
const fs = require("fs");
const WebSocket = require("ws");

const PORT = process.env.CDP_PORT || 9222;

function parseArgs(argv) {
  const out = { match: "editor.html" };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === "--match") out.match = argv[++i];
    else if (a === "--eval") out.eval = argv[++i];
    else if (a === "--file") out.file = argv[++i];
    else if (a === "--key") out.key = argv[++i];
  }
  return out;
}

async function listTargets() {
  const res = await fetch(`http://127.0.0.1:${PORT}/json/list`);
  return await res.json();
}

function connect(wsUrl) {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(wsUrl, { perMessageDeflate: false, maxPayload: 256 * 1024 * 1024 });
    ws.on("open", () => resolve(ws));
    ws.on("error", reject);
  });
}

function call(ws, method, params = {}) {
  return new Promise((resolve, reject) => {
    const id = Math.floor(Math.random() * 1e9);
    const timer = setTimeout(() => reject(new Error("timeout: " + method)), 30000);
    const onMsg = (raw) => {
      let msg;
      try { msg = JSON.parse(raw.toString()); } catch (e) { return; }
      if (msg.id !== id) return;
      clearTimeout(timer);
      ws.off("message", onMsg);
      if (msg.error) reject(new Error(JSON.stringify(msg.error)));
      else resolve(msg.result);
    };
    ws.on("message", onMsg);
    ws.send(JSON.stringify({ id, method, params }));
  });
}

const KEYS = {
  "1": { code: "Digit1", vk: 49 }, "2": { code: "Digit2", vk: 50 },
  "3": { code: "Digit3", vk: 51 }, "4": { code: "Digit4", vk: 52 },
  "5": { code: "Digit5", vk: 53 }, "0": { code: "Digit0", vk: 48 },
  escape: { code: "Escape", vk: 27 },
};

async function pressKey(ws, spec) {
  const parts = spec.toLowerCase().split("+");
  const keyName = parts.pop();
  const mods = { alt: 1, ctrl: 2, meta: 4, shift: 8 };
  let modifiers = 0;
  for (const p of parts) {
    if (!(p in mods)) throw new Error("未知修饰键: " + p);
    modifiers |= mods[p];
  }
  const k = KEYS[keyName] || { code: "Key" + keyName.toUpperCase(), vk: 0 };
  const base = {
    modifiers,
    key: keyName,
    code: k.code,
    windowsVirtualKeyCode: k.vk,
    nativeVirtualKeyCode: k.vk,
  };
  await call(ws, "Input.dispatchKeyEvent", { type: "rawKeyDown", ...base });
  await call(ws, "Input.dispatchKeyEvent", { type: "keyUp", ...base });
}

(async () => {
  const args = parseArgs(process.argv.slice(2));
  const targets = await listTargets();
  const target = targets.find(
    (t) => t.type === "page" && (t.url.includes(args.match) || t.title.includes(args.match))
  );
  if (!target) {
    console.error("未找到目标页面：");
    targets.forEach((t) => console.error(" -", t.type, t.url.slice(0, 110)));
    process.exit(1);
  }
  const ws = await connect(target.webSocketDebuggerUrl);
  await call(ws, "Runtime.enable");

  if (args.key) {
    await pressKey(ws, args.key);
    console.error("[cdp] 已发送按键: " + args.key);
  }

  let expr = args.eval;
  if (args.file) expr = fs.readFileSync(args.file, "utf8");
  if (expr) {
    const prelude =
      "(function(){try{if(!window.__wr){window.webpackChunkxmind_vana.push([[987654],{},function(r){window.__wr=r;}]);}}catch(e){}return 0;})();\n";
    const r = await call(ws, "Runtime.evaluate", {
      expression: prelude + expr,
      returnByValue: true,
      awaitPromise: true,
      userGesture: true,
    });
    if (r.exceptionDetails) {
      console.error("[异常]", JSON.stringify(r.exceptionDetails, null, 2).slice(0, 2500));
    } else {
      const v = r.result.value;
      console.log(typeof v === "string" ? v : JSON.stringify(v, null, 2));
    }
  }
  ws.close();
})().catch((e) => {
  console.error("[错误]", e.message);
  process.exit(1);
});
