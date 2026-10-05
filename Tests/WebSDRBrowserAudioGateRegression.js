// Run with: node Tests/WebSDRBrowserAudioGateRegression.js
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const source = fs.readFileSync(path.join(__dirname, '../YAAM/WebSDRBrowserSession.swift'), 'utf8');
const match = source.match(/let audioGate = WKUserScript\(source: """([\s\S]*?)""", injectionTime:/);
assert.ok(match, 'WebSDR audio script must be present');

class AudioNode {
  constructor(context) { this.context = context; this.connections = []; }
  connect(destination) { this.connections.push(destination); return destination; }
  disconnect() { this.connections = []; }
}
class AudioDestinationNode extends AudioNode {}
const context = {
  sampleRate: 12000,
  createScriptProcessor: () => new AudioNode(context),
  createGain: () => Object.assign(new AudioNode(context), { gain: { value: 0 } }),
};
const bridged = [];
const window = { AudioNode, webkit: { messageHandlers: { yaamAudio: { postMessage: item => bridged.push(item) } } } };
vm.runInNewContext(match[1], { window, AudioNode, AudioDestinationNode,
  Uint8Array, Int16Array, Math, Date, btoa: binary => Buffer.from(binary, 'binary').toString('base64') });

const destination = new AudioDestinationNode(context);
const firstSource = new AudioNode(context);
firstSource.connect(destination);
const firstTap = window.__yaamActiveTap;
const firstGain = window.__yaamGains[0];
const frame = { inputBuffer: { getChannelData: () => new Float32Array(8192).fill(0.25) } };
firstTap.onaudioprocess(frame);
assert.equal(bridged.length, 0, 'bridge should batch short callbacks');
firstTap.onaudioprocess(frame);
assert.equal(bridged.length, 1);
assert.equal(Buffer.from(bridged[0].pcm, 'base64').length, 24000);

const secondSource = new AudioNode(context);
secondSource.connect(destination);
assert.equal(firstTap.onaudioprocess, null, 'old tap must stop after reconnect');
assert.equal(firstTap.connections.length, 0, 'old tap must be disconnected');
assert.equal(firstGain.connections.length, 0, 'old listening gate must be disconnected');
assert.equal(window.__yaamGains.length, 1, 'listening gates must not accumulate');
assert.notEqual(window.__yaamActiveTap, firstTap);
console.log('WebSDR browser audio gate regression passed');
