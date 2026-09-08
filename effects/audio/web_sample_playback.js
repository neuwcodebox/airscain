// Godot 4.7 Web Sample adapter. Evaluated in JavaScriptBridge's engine context.
// Keep engine registration, bus routing and completion callbacks; replace only
// transport. AudioContext time, not game frames, owns position and native loops.
(function install(audio) {
    "use strict";
    if (!audio || !audio.Sample || !audio.SampleNode) {
        throw new Error("Unsupported Godot WebAudio sample interface");
    }
    if (audio.airscainPlaybackVersion === 1) return true;
    const proto = audio.SampleNode.prototype;
    for (const method of ["start", "pause", "clear", "setPitchScale", "getSample", "getSampleNodeBus"]) {
        if (typeof proto[method] !== "function") throw new Error("Missing WebAudio method: " + method);
    }
    const clearOriginal = proto.clear;

    // Registered PCM is immutable. Every source can share the same AudioBuffer.
    audio.Sample.prototype.getAudioBuffer = function () { return this._audioBuffer; };

    function bounds(voice) {
        const sample = voice.getSample();
        const duration = sample.getAudioBuffer().duration;
        const end = sample.loopEnd > 0 ? Math.min(duration, sample.loopEnd / sample.sampleRate) : duration;
        const begin = Math.max(0, Math.min(end, sample.loopBegin / sample.sampleRate));
        return { begin, end, loop: sample.loopMode === "forward" && end > begin };
    }

    function position(voice) {
        let cursor = voice._cursor === undefined ? voice.offset : voice._cursor;
        if (voice.isStarted && !voice.isPaused && !voice.isCanceled) {
            cursor += Math.max(0, audio.ctx.currentTime - voice._anchorTime) * voice.getPlaybackRate() * voice.getPitchScale();
        }
        const region = bounds(voice);
        if (region.loop && cursor >= region.end) {
            return region.begin + (cursor - region.begin) % (region.end - region.begin);
        }
        return Math.max(0, Math.min(region.end, cursor));
    }

    function snapshot(voice) {
        if (voice._cursor === undefined) return;
        voice._cursor = position(voice);
        voice._anchorTime = audio.ctx.currentTime;
    }

    function detach(voice) {
        const node = voice._source;
        if (!node) return;
        if (voice._onended) node.removeEventListener("ended", voice._onended);
        if (voice.isStarted) node.stop();
        node.disconnect();
        voice._source = null;
        voice._onended = null;
    }

    function startSource(voice) {
        if (!voice._source) {
            voice._source = audio.ctx.createBufferSource();
            voice._source.buffer = voice.getSample().getAudioBuffer();
            for (const bus of voice._sampleNodeBuses.values()) voice._source.connect(bus.getInputNode());
        }
        const region = bounds(voice);
        voice._source.loop = region.loop;
        voice._source.loopStart = region.begin;
        voice._source.loopEnd = region.end;
        voice._syncPlaybackRate();
        voice._addEndedListener();
        voice._anchorTime = audio.ctx.currentTime;
        voice._source.start(0, voice._cursor);
        voice.isStarted = true;
    }

    proto.start = function () {
        if (this.isStarted || this.isCanceled || this.isPaused) return;
        this._cursor = position(this);
        startSource(this);
    };
    proto.getPlaybackPosition = function () { return position(this); };
    proto.setPitchScale = function (value) {
        snapshot(this);
        this._pitchScale = value;
        this._syncPlaybackRate();
    };
    proto.setPlaybackRate = function (value) {
        snapshot(this);
        this._playbackRate = value;
        this._syncPlaybackRate();
    };
    proto._syncPlaybackRate = function () {
        if (this._source) this._source.playbackRate.value = this.getPlaybackRate() * this.getPitchScale();
    };
    proto.pause = function (enabled = true) {
        if (this.isCanceled || this.isPaused === enabled) return;
        if (enabled) {
            snapshot(this);
            this.isPaused = true;
            detach(this);
        } else {
            this.isPaused = false;
            if (this._cursor === undefined) this._cursor = position(this);
            startSource(this);
        }
    };
    proto.restart = function () {
        if (this.isCanceled) return;
        detach(this);
        this._cursor = bounds(this).begin;
        this.isPaused = false;
        startSource(this);
    };
    proto._addEndedListener = function () {
        const node = this._source;
        if (this._onended) node.removeEventListener("ended", this._onended);
        this._onended = () => {
            // Ignore queued events from a paused/replaced source. Native loops
            // never emit ended at a boundary and never allocate another source.
            if (node !== this._source || this.isPaused || this.isCanceled || node.loop) return;
            this.clear();
        };
        node.addEventListener("ended", this._onended);
    };
    proto.clear = function () {
        if (this.isCanceled) return;
        clearOriginal.call(this);
    };
    // Position is computed from the audio clock, including piecewise rates.
    // Do not attach Godot's frame-counting position worklet to these sources.
    proto.connectPositionWorklet = function (start) {
        if (start) this.start();
        return Promise.resolve();
    };
    audio.airscainPlaybackVersion = 1;
    return true;
})(typeof GodotAudio === "undefined" ? null : GodotAudio);
