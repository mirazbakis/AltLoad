// Runs AltLoad's JIT script against a fake debugserver for a few app behaviours.
// Usage: node scripts/test-jit-script.js
const fs = require("fs");
const vm = require("vm");
const assert = require("assert");
const source = fs.readFileSync(__dirname + "/../ios/App/Resources/JIT/altload-jit.js", "utf8");

const le = (v) => { let s = ""; v = BigInt.asUintN(64, BigInt(v)); for (let i = 0; i < 8; i++) { s += Number(v & 0xffn).toString(16).padStart(2, "0"); v >>= 8n; } return s; };
const brk = (imm) => le(0xD4200000 | (imm << 5)).slice(0, 8);
const stopReply = (sig, regs) => `T${sig.toString(16).padStart(2, "0")}thread:1a2b;` + Object.entries(regs).map(([k, v]) => `${Number(k).toString(16).padStart(2, "0")}:${le(v)};`).join("") + "metype:6;";

// `events`: what the app does each time it's resumed: {brk, x0, x1, x16} | {signal} | "exit" | "quiet".
function run(events, memory = {}) {
  const log = [], sent = [], prepared = [], resumes = [];
  let i = 0, regs = {};
  const ctx = {
    get_pid: () => 4242,
    log: (t) => log.push(t),
    prepare_memory_region: (a, l) => { prepared.push([a, l]); return "OK"; },
    send_command: (p) => {
      sent.push(p);
      if (p.startsWith("vAttach;")) return "T11thread:1a2b;";
      if (p.startsWith("m")) {
        const [addr, len] = p.slice(1).split(",").map((h) => BigInt("0x" + h));
        if (addr === 0x100000n) return regs.instr;
        if (memory[addr]) return Buffer.from(memory[addr]).toString("hex");
        return "E01";
      }
      if (p.startsWith("_M")) return "2a0000";
      return "OK";
    },
    continue_for: (resume, ms) => {
      resumes.push([resume, ms]);
      const e = events[i++];
      if (e === undefined || e === "quiet") return "";
      if (e === "exit") return "W00";
      if (e.signal) { regs = { instr: "1f2003d5" }; return stopReply(e.signal, { 0x20: 0x100000 }); }
      regs = { instr: brk(e.brk) };
      return stopReply(5, { 0: e.x0 || 0, 1: e.x1 || 0, 0x10: e.x16 || 0, 0x20: 0x100000 });
    },
  };
  ctx.globalThis = ctx;
  const result = vm.runInNewContext(source, ctx);
  return { result, log, sent, prepared, resumes };
}

// A region, then done.
let r = run([{ brk: 0xf00d, x16: 1, x0: 0x8000000, x1: 0x8000 }, { brk: 0xf00d, x16: 0 }]);
assert.deepStrictEqual(r.prepared, [[0x8000000n, 0x8000n]]);
assert.ok(r.sent.includes("P0=0000000800000000;thread:1a2b;"), "x0 answered");
assert.ok(r.sent.includes("P20=0400100000000000;thread:1a2b;"), "steps over the brk");
assert.strictEqual(r.sent[r.sent.length - 1], "D");
assert.strictEqual(r.result.ended, "app"); assert.strictEqual(r.result.requests, 1);
assert.deepStrictEqual(r.resumes.map((x) => x[1]), [8000, 300000]);

// Allocate first when x0 is 0.
r = run([{ brk: 0xf00d, x16: 1, x0: 0, x1: 0x4000 }, { brk: 0xf00d, x16: 0 }]);
assert.ok(r.sent.includes("_M4000,rx"));
assert.deepStrictEqual(r.prepared, [[0x2a0000n, 0x4000n]]);
assert.ok(r.sent.includes("P0=00002a0000000000;thread:1a2b;"));

// The older form: prepare once, then leave.
r = run([{ brk: 0x69, x0: 0x9000000, x1: 0x10000 }]);
assert.deepStrictEqual(r.prepared, [[0x9000000n, 0x10000n]]);
assert.strictEqual(r.result.ended, "app");

// No request: only the attach was needed.
r = run(["quiet"]);
assert.strictEqual(r.result.ended, "attach"); assert.strictEqual(r.sent[r.sent.length - 1], "D");

// A signal that isn't a request goes back to the app; then it exits.
r = run([{ signal: 0x0b }, "exit"]);
assert.deepStrictEqual(r.resumes.map((x) => x[0]), ["c", "vCont;S0b:1a2b"]);
assert.strictEqual(r.result.ended, "exited");

// An unknown brk is not stepped over: the app gets its trap back.
r = run([{ brk: 0x1 }, "exit"]);
assert.ok(!r.sent.some((p) => p.startsWith("P20=")));
assert.deepStrictEqual(r.resumes[1][0], "vCont;S05:1a2b");

// A script from the app adds a handler for a new request.
const appScript = "commands[3] = function () { log('custom x0=' + x0); requests++; };";
r = run([{ brk: 0xf00d, x16: 2, x0: 0x7000, x1: appScript.length }, { brk: 0xf00d, x16: 3, x0: 7 }, { brk: 0xf00d, x16: 0 }], { [0x7000n]: appScript });
assert.ok(r.log.some((l) => l === "custom x0=7"), r.log.join(" | "));
assert.strictEqual(r.result.requests, 1); assert.strictEqual(r.result.ended, "app");

// Same through the older brk #0x68.
r = run([{ brk: 0x68, x0: 0x7000, x1: appScript.length }, { brk: 0xf00d, x16: 3, x0: 9 }, "quiet"], { [0x7000n]: appScript });
assert.ok(r.log.includes("custom x0=9")); assert.strictEqual(r.result.ended, "quiet");

// A refused attach is an error.
assert.throws(() => vm.runInNewContext(source, { get_pid: () => 1, log() {}, send_command: () => "E08", continue_for() {}, prepare_memory_region() {} }), /refused to attach/);

console.log("all JIT script tests passed");
