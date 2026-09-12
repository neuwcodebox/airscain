const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const adapterPath = path.resolve(__dirname, '../../effects/audio/web_sample_playback.js');
const adapter = fs.readFileSync(adapterPath, 'utf8');

function fixture({ duration = 20, begin = 0, loop = false } = {}) {
    const nodes = [];
    const context = {
        currentTime: 0,
        createBufferSource() {
            const node = {
                playbackRate: { value: 1 }, loop: false, listeners: new Set(),
                connect() {}, disconnect() {}, stop() { this.stopped = true; },
                start(when, offset) { this.offset = offset; this.rateAtStart = this.playbackRate.value; },
                addEventListener(event, fn) { this.listeners.add(fn); },
                removeEventListener(event, fn) { this.listeners.delete(fn); },
            };
            nodes.push(node);
            return node;
        },
    };
    class Sample {
        constructor() {
            this._audioBuffer = { duration };
            this.sampleRate = 44100;
            this.loopMode = loop ? 'forward' : 'disabled';
            this.loopBegin = 0; // Godot Ogg registration does not supply loop_offset.
            this.loopEnd = 0;
        }
        getAudioBuffer() { return { ...this._audioBuffer }; }
    }
    const sample = new Sample();
    Sample.getSample = () => sample;
    Sample.getSampleOrNull = () => sample;
    class SampleNode {
        constructor(offset, pitch = 1) {
            Object.assign(this, { offset, isStarted: false, isCanceled: false, isPaused: false,
                _source: context.createBufferSource(), _sampleNodeBuses: new Map(),
                _positionWorklet: null, _onended: null, _pitchScale: pitch, _playbackRate: 1, clears: 0 });
            this._source.buffer = sample.getAudioBuffer();
            this.connectPositionWorklet(true);
        }
        getSample() { return sample; }
        getSampleNodeBus() {}
        getPlaybackRate() { return this._playbackRate; }
        getPitchScale() { return this._pitchScale; }
        start() {}
        pause() {}
        setPitchScale() {}
        clear() { this.isCanceled = true; this.clears++; this._source?.stop(); }
    }
    const audio = { ctx: context, Sample, SampleNode };
    const scope = { GodotAudio: audio };
    assert.equal(vm.runInNewContext(adapter, scope), true);
    audio.airscainSetLoopRegion("fixture", loop, begin, duration);
    return { audio, context, nodes, sample, scope, create: (offset = 0, pitch = 1) => new SampleNode(offset, pitch),
        play: async (offset = 0, pitch = 1) => { const voice = new SampleNode(offset, pitch); await Promise.resolve(); return voice; } };
}

function assertNear(actual, expected, context = '') {
    const difference = Math.abs(actual - expected);
    assert.ok(difference < 1e-7, `${context || 'value'}: ${actual} != ${expected} (difference ${difference})`);
}

test('late entry loops the entire recording on one native source, even through a frame stall', async () => {
    const f = fixture({ duration: 3, loop: true });
    const voice = await f.play(2.9, 4);
    assert.equal(f.nodes[0].loop, true);
    assert.equal(f.nodes[0].loopStart, 0);
    assert.equal(f.nodes[0].loopEnd, 3);
    f.context.currentTime = 10; // no game updates across thirteen loop boundaries
    assertNear(voice.getPlaybackPosition(), 0.9, 'looped playback position');
    assert.equal(f.nodes.length, 1);
    assert.equal(f.nodes[0].playbackRate.value, 4);
});

test('gun intro plays once and subsequent loops start at the configured frame', async () => {
    const f = fixture({ duration: 3, begin: 25216 / 44100, loop: true });
    const voice = await f.play();
    assertNear(f.nodes[0].loopStart, 25216 / 44100, 'configured loop start');
    assert.equal(f.nodes[0].offset, 0);
    f.context.currentTime = 3.1;
    assertNear(voice.getPlaybackPosition(), 25216 / 44100 + 0.1, 'position after entering loop region');
    assert.equal(f.nodes.length, 1);
});

test('pause at 4x resumes at the exact accumulated media position and rate', async () => {
    const f = fixture();
    const voice = await f.play(2, 4);
    f.context.currentTime = 1;
    voice.pause(true);
    f.context.currentTime = 11;
    assertNear(voice.getPlaybackPosition(), 6, 'paused media position');
    voice.pause(false);
    assertNear(f.nodes[1].offset, 6, 'resume offset');
    assert.equal(f.nodes[1].rateAtStart, 4);
});

test('multiple pauses and speed changes exclude all paused time', async () => {
    const f = fixture({ duration: 100 });
    const voice = await f.play();
    f.context.currentTime = 1;
    voice.setPitchScale(2);
    f.context.currentTime = 2;
    voice.pause(true); // position 3
    f.context.currentTime = 12;
    voice.setPitchScale(4);
    voice.pause(false);
    f.context.currentTime = 13;
    voice.pause(true); // position 7, not 13 or 47
    f.context.currentTime = 25;
    voice.pause(false);
    assertNear(f.nodes.at(-1).offset, 7, 'offset after multiple pauses');
    assert.equal(f.nodes.at(-1).rateAtStart, 4);
    f.context.currentTime = 25.5;
    assertNear(voice.getPlaybackPosition(), 9, 'position after final resume');
});

test('redundant pause/resume does not create sources or move the cursor', async () => {
    const f = fixture();
    const voice = await f.play();
    f.context.currentTime = 1;
    for (let i = 0; i < 100; i++) voice.pause(false);
    assert.equal(f.nodes.length, 1);
    voice.pause(true);
    f.context.currentTime = 12;
    for (let i = 0; i < 100; i++) voice.pause(true);
    assertNear(voice.getPlaybackPosition(), 1, 'cursor while redundantly paused');
    voice.pause(false);
    assert.equal(f.nodes.length, 2);
    assertNear(f.nodes[1].offset, 1, 'cursor after redundant resume');
});

test('stale ended events cannot stop a resumed source', async () => {
    const f = fixture();
    const voice = await f.play();
    const stale = [...f.nodes[0].listeners][0];
    f.context.currentTime = 1;
    voice.pause(true);
    voice.pause(false);
    stale();
    assert.equal(voice.clears, 0);
    assert.equal(f.nodes.length, 2);
});

test('completion of the active source is delivered once', async () => {
    const f = fixture();
    const voice = await f.play();
    voice.pause(true);
    voice.pause(false);
    const ended = [...f.nodes[1].listeners][0];
    ended(); ended(); voice.clear();
    assert.equal(voice.clears, 1);
    voice.pause(false);
    assert.equal(f.nodes.length, 2);
});

test('sources reuse immutable decoded PCM including after pause', async () => {
    const f = fixture();
    const voice = await f.play();
    await f.play(2);
    voice.pause(true); voice.pause(false);
    for (const [index, node] of f.nodes.entries()) {
        assert.equal(node.buffer, f.sample._audioBuffer, `source ${index} reuses the decoded buffer`);
    }
});

test('installation is idempotent', () => {
    const f = fixture();
    const start = f.audio.SampleNode.prototype.start;
    assert.equal(vm.runInNewContext(adapter, f.scope), true);
    assert.equal(f.audio.SampleNode.prototype.start, start);
});

test('installation rejects incompatible engine interfaces', () => {
    assert.throws(() => vm.runInNewContext(adapter, { GodotAudio: {} }), /Unsupported/);
});

test('pause in the initial play call defers the source start', async () => {
    const f = fixture();
    const paused = f.create(2, 4);
    paused.pause(true);
    await Promise.resolve();
    assert.equal(f.nodes[0].offset, undefined);
    assertNear(paused.getPlaybackPosition(), 2, 'initial paused position');
    paused.pause(false);
    assert.equal(f.nodes[1].offset, 2);
    assert.equal(f.nodes[1].rateAtStart, 4);
});

test('stop in the initial play call prevents the source start', async () => {
    const f = fixture();
    const stopped = f.create();
    stopped.clear();
    await Promise.resolve();
    assert.equal(f.nodes[0].offset, undefined);
    assert.equal(stopped.clears, 1);
});
