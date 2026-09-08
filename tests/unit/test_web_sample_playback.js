const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const adapter = fs.readFileSync('effects/audio/web_sample_playback.js', 'utf8');

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
            this.loopBegin = begin * this.sampleRate;
            this.loopEnd = duration * this.sampleRate;
        }
        getAudioBuffer() { return { ...this._audioBuffer }; }
    }
    const sample = new Sample();
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
    return { audio, context, nodes, sample, scope, play: (offset = 0, pitch = 1) => new SampleNode(offset, pitch) };
}

function near(actual, expected) { assert.ok(Math.abs(actual - expected) < 1e-7, `${actual} != ${expected}`); }

test('late entry loops the entire recording on one native source, even through a frame stall', () => {
    const f = fixture({ duration: 3, loop: true });
    const voice = f.play(2.9, 4);
    assert.equal(f.nodes[0].loop, true);
    assert.equal(f.nodes[0].loopStart, 0);
    assert.equal(f.nodes[0].loopEnd, 3);
    f.context.currentTime = 10; // no game updates across thirteen loop boundaries
    near(voice.getPlaybackPosition(), 0.9);
    assert.equal(f.nodes.length, 1);
    assert.equal(f.nodes[0].playbackRate.value, 4);
});

test('gun intro plays once and subsequent loops start at the configured frame', () => {
    const f = fixture({ duration: 3, begin: 25216 / 44100, loop: true });
    const voice = f.play();
    near(f.nodes[0].loopStart, 25216 / 44100);
    assert.equal(f.nodes[0].offset, 0);
    f.context.currentTime = 3.1;
    near(voice.getPlaybackPosition(), 25216 / 44100 + 0.1);
    assert.equal(f.nodes.length, 1);
});

test('pause at 4x resumes at the exact accumulated media position and rate', () => {
    const f = fixture();
    const voice = f.play(2, 4);
    f.context.currentTime = 1;
    voice.pause(true);
    f.context.currentTime = 11;
    near(voice.getPlaybackPosition(), 6);
    voice.pause(false);
    near(f.nodes[1].offset, 6);
    assert.equal(f.nodes[1].rateAtStart, 4);
});

test('multiple pauses and speed changes exclude all paused time', () => {
    const f = fixture({ duration: 100 });
    const voice = f.play();
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
    near(f.nodes.at(-1).offset, 7);
    assert.equal(f.nodes.at(-1).rateAtStart, 4);
    f.context.currentTime = 25.5;
    near(voice.getPlaybackPosition(), 9);
});

test('redundant pause/resume does not create sources or move the cursor', () => {
    const f = fixture();
    const voice = f.play();
    f.context.currentTime = 1;
    for (let i = 0; i < 100; i++) voice.pause(false);
    assert.equal(f.nodes.length, 1);
    voice.pause(true);
    f.context.currentTime = 12;
    for (let i = 0; i < 100; i++) voice.pause(true);
    near(voice.getPlaybackPosition(), 1);
    voice.pause(false);
    assert.equal(f.nodes.length, 2);
    near(f.nodes[1].offset, 1);
});

test('stale ended events cannot stop a resumed source and completion is delivered once', () => {
    const f = fixture();
    const voice = f.play();
    const stale = [...f.nodes[0].listeners][0];
    f.context.currentTime = 1;
    voice.pause(true);
    voice.pause(false);
    stale();
    assert.equal(voice.clears, 0);
    const ended = [...f.nodes[1].listeners][0];
    ended(); ended(); voice.clear();
    assert.equal(voice.clears, 1);
    voice.pause(false);
    assert.equal(f.nodes.length, 2);
});

test('sources reuse immutable decoded PCM including after pause', () => {
    const f = fixture();
    const voice = f.play();
    f.play(2);
    voice.pause(true); voice.pause(false);
    for (const node of f.nodes) assert.equal(node.buffer, f.sample._audioBuffer);
});

test('installation is idempotent and rejects incompatible engine interfaces', () => {
    const f = fixture();
    const start = f.audio.SampleNode.prototype.start;
    assert.equal(vm.runInNewContext(adapter, f.scope), true);
    assert.equal(f.audio.SampleNode.prototype.start, start);
    assert.throws(() => vm.runInNewContext(adapter, { GodotAudio: {} }), /Unsupported/);
});
