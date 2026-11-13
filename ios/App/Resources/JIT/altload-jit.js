// AltLoad's JIT script.
//
// AltLoad runs this in a JIT session after launching the app suspended. It
// attaches, lets the app run, and answers the app's requests for JIT memory until
// the app says it's done, exits, or goes quiet.
//
// A request is a brk instruction with the request in registers:
//   brk #0xf00d, x16 = 0            done: AltLoad detaches
//   brk #0xf00d, x16 = 1, x0, x1    make [x0, x0 + x1) usable for JIT; with x0 = 0,
//                                   allocate it first and return it in x0
//   brk #0xf00d, x16 = 2, x0, x1    run the script text at x0 (x1 bytes) here; it
//                                   can add handlers for more requests
//   brk #0x68, x0, x1               the same, older form
//   brk #0x69, x0, x1               the older form of a JIT request: AltLoad
//                                   prepares the region once, then detaches
//
// AltLoad provides: send_command(packet), continue_for(resume, ms),
// prepare_memory_region(address, length), get_pid(), log(text).
// A script the app sends can read tid, pc, x0, x1 and x16, and add handlers to
// `commands` (by x16, for brk #0xf00d) or `legacyCommands` (by brk immediate).

var FIRST_REQUEST_MS = 8000;  // an app that hasn't asked by then only needed the attach
var IDLE_MS = 300000;         // how long to stay after the last request
var SIGSTOP = 0x11;

var tid = null, pc = 0n, x0 = 0n, x1 = 0n, x16 = 0n;
var detached = false, ended = "", requests = 0;

// A register as debugserver sends it: bytes in hex, least significant first.
function hexToBigLE(hex) {
  var value = 0n;
  for (var i = hex.length - 2; i >= 0; i -= 2) value = (value << 8n) | BigInt(parseInt(hex.substr(i, 2), 16));
  return value;
}

function bigToHexLE(value) {
  var v = BigInt.asUintN(64, value), out = "";
  for (var i = 0; i < 8; i++) {
    var b = Number(v & 0xffn);
    out += (b < 16 ? "0" : "") + b.toString(16);
    v >>= 8n;
  }
  return out;
}

function hexToText(hex) {
  var bytes = "";
  for (var i = 0; i + 1 < hex.length; i += 2) {
    var c = parseInt(hex.substr(i, 2), 16);
    if (c === 0) break;
    bytes += "%" + hex.substr(i, 2);
  }
  try { return decodeURIComponent(bytes); } catch (e) { return unescape(bytes); }
}

// "T05thread:1a2b;00:…;10:…;20:…;" → { signal, thread, regs: { number: BigInt } }
function parseStop(reply) {
  var m = /^T([0-9a-fA-F]{2})/.exec(reply);
  if (!m) return null;
  var stop = { signal: parseInt(m[1], 16), thread: null, regs: {} };
  reply.substr(3).split(";").forEach(function (pair) {
    var i = pair.indexOf(":");
    if (i < 0) return;
    var key = pair.substr(0, i), value = pair.substr(i + 1);
    if (key === "thread") stop.thread = value;
    else if (/^[0-9a-fA-F]{1,2}$/.test(key) && value.length === 16) stop.regs[parseInt(key, 16)] = hexToBigLE(value);
  });
  return stop.thread ? stop : null;
}

// The immediate of an AArch64 brk, from the four bytes `m` returns; null for anything else.
function brkImmediate(memoryHex) {
  if (!memoryHex || memoryHex.length !== 8) return null;
  var word = Number(hexToBigLE(memoryHex));
  if (((word & 0xFFE0001F) >>> 0) !== 0xD4200000) return null;
  return (word >>> 5) & 0xFFFF;
}

function setRegister(number, value) {
  var reply = send_command("P" + number.toString(16) + "=" + bigToHexLE(value) + ";thread:" + tid + ";");
  if (reply && reply.charAt(0) === "E") throw new Error("debugserver couldn't set a register (" + reply + ").");
}

function leave(reason) {
  send_command("D");
  detached = true;
  ended = reason;
}

function runAppScript(address, length) {
  if (length <= 0n) return;
  var source = hexToText(send_command("m" + address.toString(16) + "," + length.toString(16)));
  log("The app sent a script (" + source.length + " characters).");
  try { (0, eval)(source); } catch (e) { log("The app's script failed: " + e); }
}

// Prepares [x0, x0 + x1), allocating it first when x0 is 0. Returns its address.
function prepareRegion() {
  if (x0 === 0n && x1 === 0n) return null;
  var address = x0;
  if (address === 0n) {
    var reply = send_command("_M" + x1.toString(16) + ",rx");
    if (!reply || reply.charAt(0) === "E") throw new Error("debugserver couldn't allocate JIT memory (" + reply + ").");
    address = BigInt("0x" + reply);
  }
  prepare_memory_region(address, x1);
  requests++;
  return address;
}

var commands = {
  0: function () { leave("app"); },
  1: function () { var a = prepareRegion(); if (a !== null) setRegister(0, a); },
  2: function () { runAppScript(x0, x1); }
};

var legacyCommands = {
  0x68: function () { runAppScript(x0, x1); },
  0x69: function () { prepareRegion(); leave("app"); }
};

var pid = get_pid();
var attach = send_command("vAttach;" + pid.toString(16));
if (!attach || attach.charAt(0) === "E") {
  throw new Error("debugserver refused to attach (" + attach + "). The app has to be signed for development, as AltLoad signs it.");
}
log("Attached to process " + pid + ".");

var resume = "c";
while (!detached) {
  var reply = continue_for(resume, requests === 0 ? FIRST_REQUEST_MS : IDLE_MS);
  resume = "c";
  if (!reply) { leave(requests === 0 ? "attach" : "quiet"); break; }
  if (/^[WX]/.test(reply)) { detached = true; ended = "exited"; break; }
  var stop = parseStop(reply);
  if (!stop || stop.regs[0x20] === undefined) continue;
  tid = stop.thread;
  pc = stop.regs[0x20];
  x0 = stop.regs[0x00] || 0n;
  x1 = stop.regs[0x01] || 0n;
  x16 = stop.regs[0x10] || 0n;

  var immediate = brkImmediate(send_command("m" + pc.toString(16) + ",4"));
  var handler = immediate === 0xf00d ? commands[Number(x16)] : (immediate === null ? undefined : legacyCommands[immediate]);
  if (immediate !== 0xf00d && !handler) {
    // Not a request: the app gets its signal back, as it would without a
    // debugger. A stop signal is dropped, since it would pause the app.
    if (stop.signal !== SIGSTOP) resume = "vCont;S" + (stop.signal < 16 ? "0" : "") + stop.signal.toString(16) + ":" + tid;
    continue;
  }
  // Every request carries on after its brk.
  setRegister(0x20, pc + 4n);
  if (handler) handler(reply);
  else log("Skipped a request AltLoad doesn't know (x16 = " + x16 + ").");
}

({ requests: requests, ended: ended });
