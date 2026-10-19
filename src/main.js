import { clock, splitForReading, wordTimes, wordsSpoken } from './reading.js'

const { invoke } = window.__TAURI__.core
const { listen } = window.__TAURI__.event
const { getCurrentWindow, currentMonitor, LogicalPosition, LogicalSize } = window.__TAURI__.window

const SIZE_PRESETS = {
    compact:  { w: 320, h: 200 },
    standard: { w: 380, h: 240 },
    spacious: { w: 460, h: 280 },
}
const PLAYER_MARGIN = 24

function getPlayerDims() {
    const name = state.config?.player_size || 'standard'
    return SIZE_PRESETS[name] || SIZE_PRESETS.standard
}

const state = {
    decoderCtx: null,    // AudioContext used ONLY for decodeAudioData (never connected to destination)
    rafId: null,
    sessionId: 0,
    inFlight: false,
    reading: null,       // the reading in progress (startReading)
    audioElement: null,  // the <audio> playing now
    playAbort: null,     // ends the current part's await; called by a jump or a stop
    config: {
        speed: 1.0,
        engine: 'rafael',
        piper_voice: 'pt_BR-faber-medium',
    },
}

// Rafael goes through the Text to Speech server to Fish Audio, which takes three parts at
// a time: three parts are generated ahead, and a fourth waits its turn.
// Piper runs on this Mac, one part at a time, with the next one ready.
const AHEAD = {
    rafael: { inFlight: 3, window: 4 },
    piper: { inFlight: 1, window: 2 },
}
const ENVELOPE_RATE = 60  // envelope samples per second of audio
const SPEED_STEP = 0.25
// Before any part is ready the clock estimates from the text: seconds per
// character at 1x, from Rafael's 40 words in 8.7 s at 1.5x.
const SECONDS_PER_CHAR = 0.057

const el = id => document.getElementById(id)

/** A message in place of the clock and the voice (an error, "Nada selecionado"). */
function setHint(text, withEsc = false) {
    const h = el('hint')
    if (!h) return
    h.innerHTML = ''
    if (withEsc) {
        const kbd = document.createElement('kbd')
        kbd.className = 'kbd'
        kbd.textContent = 'Esc'
        h.appendChild(kbd)
        h.appendChild(document.createTextNode(' ' + text))
    } else {
        h.textContent = text || ''
    }
    document.body.classList.toggle('has-hint', Boolean(text))
}

const capitalize = (w) => w.charAt(0).toUpperCase() + w.slice(1)

function voiceShortName(cfg) {
    if (cfg.engine !== 'piper') return 'Rafael'
    // pt_BR-faber-medium → Faber
    const parts = (cfg.piper_voice || '').split('-')
    return capitalize(parts[1] || cfg.piper_voice || '')
}

const speedLabel = speed => `${Number(speed || 1).toFixed(2).replace('.', ',')}×`

function reflectChips() {
    const cfg = state.config
    const engineEl = el('chip-engine')
    if (engineEl) engineEl.textContent = cfg.engine === 'piper' ? 'Piper' : 'Internet'
    const voiceEl = el('chip-voice')
    if (voiceEl) voiceEl.textContent = voiceShortName(cfg)
    const speedEl = el('chip-speed')
    if (speedEl) speedEl.textContent = speedLabel(cfg.speed)
}

function calcPosition(name, monW, monH, monX, monY, ww, wh) {
    let x, y
    const [v, h] = name === 'center' ? ['middle', 'center'] : name.split('-')
    if (h === 'left') x = monX + PLAYER_MARGIN
    else if (h === 'right') x = monX + monW - ww - PLAYER_MARGIN
    else x = monX + (monW - ww) / 2
    if (v === 'top') y = monY + PLAYER_MARGIN
    else if (v === 'bottom') y = monY + monH - wh - PLAYER_MARGIN
    else y = monY + (monH - wh) / 2
    return { x: Math.round(x), y: Math.round(y) }
}

async function applyPlayerLayout() {
    try {
        const { w, h } = getPlayerDims()
        const win = getCurrentWindow()
        await win.setSize(new LogicalSize(w, h))
        document.body.dataset.size = state.config.player_size || 'standard'

        const pos = state.config.player_position || 'center'
        const monitor = await currentMonitor()
        if (!monitor) return
        const scale = monitor.scaleFactor || 1
        const monW = monitor.size.width / scale
        const monH = monitor.size.height / scale
        const monX = monitor.position.x / scale
        const monY = monitor.position.y / scale
        const { x, y } = calcPosition(pos, monW, monH, monX, monY, w, h)
        await win.setPosition(new LogicalPosition(x, y))
    } catch (err) {
        console.error('failed to apply player layout', err)
    }
}

function base64ToBytes(b64) {
    const bin = atob(b64)
    const out = new Uint8Array(bin.length)
    for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i)
    return out
}

// AudioContext used ONLY for decodeAudioData. Never connected to destination,
// so a broken WKWebView audio session can't make playback silent — playback
// goes through HTMLAudioElement (AVFoundation path) instead.
function getDecoderCtx() {
    if (!state.decoderCtx || state.decoderCtx.state === 'closed') {
        try {
            state.decoderCtx = new (window.AudioContext || window.webkitAudioContext)()
        } catch (err) {
            console.warn('[audio] decoder ctx create failed:', err)
            return null
        }
    }
    return state.decoderCtx
}

function computeEnvelope(audioBuffer, samplesPerSecond) {
    const ch = audioBuffer.getChannelData(0)
    const totalSamples = ch.length
    const sr = audioBuffer.sampleRate
    const windowSize = Math.max(1, Math.floor(sr / samplesPerSecond))
    const frames = Math.max(1, Math.floor(totalSamples / windowSize))
    const env = new Float32Array(frames)
    let peak = 0
    for (let i = 0; i < frames; i++) {
        let sum = 0
        const start = i * windowSize
        const end = Math.min(start + windowSize, totalSamples)
        for (let j = start; j < end; j++) sum += ch[j] * ch[j]
        const rms = Math.sqrt(sum / (end - start))
        env[i] = rms
        if (rms > peak) peak = rms
    }
    if (peak > 0) {
        for (let i = 0; i < frames; i++) env[i] /= peak
    }
    return env
}

/** One part → its audio, ready to play: the blob URL, its length, the loudness envelope and the word times. */
async function synthAndPrep(text, engine, speed) {
    const result = engine === 'piper'
        ? await invoke('synthesize_piper', { text, voice: state.config.piper_voice, speed })
        : await invoke('synthesize', { text, speed })

    const bytes = base64ToBytes(result.audio_b64)
    const url = URL.createObjectURL(new Blob([bytes], { type: result.mime }))

    let envelope = null
    let duration = 0
    const decoder = getDecoderCtx()
    if (decoder) {
        try {
            const buffer = await decoder.decodeAudioData(bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength))
            envelope = computeEnvelope(buffer, ENVELOPE_RATE)
            duration = buffer.duration
        } catch (err) {
            console.warn('[audio] envelope decode failed (meter flat):', err)
        }
    }
    // The base64 stays: if the blob URL fails to load, the part plays from a data URL instead (playPart).
    return { url, b64: result.audio_b64, mime: result.mime, envelope, duration, speed, times: wordTimes(text, result.words || [], duration) }
}

/* ─── The reading ───────────────────────────────────────────────────────
   The selection is cut at its paragraphs, each read whole so the voice keeps
   the sense; only the first paragraph ramps up, at its pauses, so the voice
   starts in seconds (reading.js, splitForReading).
   A few parts are generated ahead of the one playing; the window shows the
   part being read with the word being spoken, the one before and the one
   after, and a bar of the whole text's time. Space pauses, the arrows go
   back or forward a part, minus and plus change the speed. */

function startReading(text, engine, session) {
    return {
        session,
        engine,
        parts: splitForReading(text).map(t => ({ text: t, promise: null, item: null })),
        index: 0,
        paused: false,
        jumped: false,
        resume: null,     // resolves the wait of a paused reading
        shownIndex: -1,   // the part whose words are in the window
    }
}

const isLive = r => r && state.reading === r && state.sessionId === r.session

/** Starts generating the parts the window needs next, as many as the engine allows at once. */
function ensureAhead(r) {
    const { inFlight, window: ahead } = AHEAD[r.engine] || AHEAD.rafael
    let running = r.parts.filter(p => p.promise && !p.item && !p.error).length
    for (let k = r.index; k < Math.min(r.parts.length, r.index + ahead); k++) {
        const part = r.parts[k]
        if (part.promise) continue
        // The part being read is always asked for, even past the limit:
        // after a jump, waiting for a free slot left it never asked.
        if (running >= inFlight && k !== r.index) break
        running++
        part.promise = synthAndPrep(part.text, r.engine, state.config.speed).then(
            item => {
                if (!isLive(r)) {
                    URL.revokeObjectURL(item.url)
                    return item
                }
                part.item = item
                ensureAhead(r)
                return item
            },
            error => {
                part.error = error
                throw error
            }
        )
        part.promise.catch(() => {}) // a part's failure is shown when the reading gets to it
    }
}

/**
 * Plays one part; resolves true when it ends (or a jump or a stop cuts it),
 * false when it could not be played at all. A part whose blob URL fails to
 * load is tried once more from a data URL: on 16/10 a first paragraph that took
 * 14 s made the parts already in fail with "WebKitBlobResource error 1", and
 * the player skipped them all in silence.
 */
function playPart(item) {
    const audio = new Audio()
    audio.preload = 'auto'
    audio.src = item.url
    audio.preservesPitch = true
    audio.playbackRate = state.config.speed / item.speed
    state.audioElement = audio
    return new Promise(resolve => {
        let done = false
        let fromData = false
        const finish = (played = true) => {
            if (done) return
            done = true
            try { audio.pause() } catch {}
            if (state.audioElement === audio) state.audioElement = null
            resolve(played)
        }
        const failed = err => {
            if (done) return
            if (!fromData && item.b64) {
                console.warn('[audio] blob failed, playing from data:', err)
                fromData = true
                audio.src = `data:${item.mime || 'audio/mpeg'};base64,${item.b64}`
                audio.playbackRate = state.config.speed / item.speed
                audio.play().catch(failed)
                return
            }
            console.warn('[audio] part could not be played:', err)
            finish(false)
        }
        state.playAbort = () => finish(true)
        audio.addEventListener('ended', () => finish(true))
        audio.addEventListener('error', () => failed(audio.error))
        audio.play().catch(failed)
    })
}

async function readAll(r) {
    let cancelArmed = false
    while (isLive(r) && r.index < r.parts.length) {
        const i = r.index
        const part = r.parts[i]
        ensureAhead(r)
        let item
        try {
            item = await part.promise
        } catch (err) {
            if (isLive(r)) setHint(String(err))
            return false
        }
        if (!isLive(r)) return false
        if (r.index !== i) continue
        if (r.paused) {
            await new Promise(resolve => { r.resume = resolve })
            r.resume = null
            if (!isLive(r)) return false
            if (r.index !== i) continue
        }
        if (!cancelArmed) {
            invoke('arm_cancel_key').catch(err => console.warn('arm_cancel_key failed (Esc only with the window focused):', err))
            cancelArmed = true
        }
        r.jumped = false
        const played = await playPart(item)
        if (!isLive(r)) return false
        if (!played) {
            setHint('Não foi possível tocar este trecho. Tente de novo.')
            return false
        }
        if (r.jumped) continue
        URL.revokeObjectURL(item.url)
        r.index = i + 1
    }
    return isLive(r)
}

function togglePause() {
    const r = state.reading
    if (!isLive(r)) return
    r.paused = !r.paused
    const audio = state.audioElement
    if (r.paused) {
        audio?.pause()
    } else if (audio) {
        audio.play().catch(() => {})
    } else {
        r.resume?.()
    }
}

/** ← and →: a part back or forward. Back within the first seconds of a part goes to the one before; later, to its start. */
function jump(delta) {
    const r = state.reading
    if (!isLive(r)) return
    const audio = state.audioElement
    let target = r.index + delta
    if (delta < 0 && audio && audio.currentTime * audio.playbackRate > 1.5) target = r.index
    target = Math.max(0, Math.min(r.parts.length - 1, target))
    if (target === r.index && delta > 0) return
    r.index = target
    r.jumped = true
    ensureAhead(r)
    state.playAbort?.()
    r.resume?.()
}

/** − and +: the speed, saved, and applied at once to the part playing. */
async function changeSpeed(delta) {
    const speed = Math.max(0.5, Math.min(2, Math.round((Number(state.config.speed) + delta) * 4) / 4))
    if (speed === state.config.speed) return
    state.config.speed = speed
    const r = state.reading
    const audio = state.audioElement
    const item = r?.parts[r.index]?.item
    if (audio && item) audio.playbackRate = speed / item.speed
    reflectChips()
    try { state.config = await invoke('set_speed', { speed }) } catch (err) { console.warn('set_speed failed', err) }
}

/* ─── The window ─────────────────────────────────────────────────────── */

function partSeconds(r, part) {
    const speed = state.config.speed
    if (part.item?.duration) return part.item.duration * part.item.speed / speed
    return part.text.length * SECONDS_PER_CHAR / speed
}

function renderWords(r) {
    const now = el('now')
    const part = r.parts[r.index]
    now.replaceChildren(...part.text.split(/\s+/).filter(Boolean).map(word => {
        const span = document.createElement('span')
        span.className = 'w'
        span.textContent = word + ' '
        return span
    }))
    el('prev').textContent = r.parts[r.index - 1]?.text ?? ''
    el('next').textContent = r.parts[r.index + 1]?.text ?? ''
    now.scrollTop = 0
    r.shownIndex = r.index
    r.spokenShown = -1
}

function render() {
    const r = state.reading
    if (!isLive(r)) return
    const part = r.parts[r.index]
    if (!part) return
    if (r.shownIndex !== r.index) renderWords(r)

    const audio = state.audioElement
    const playing = Boolean(audio && part.item && !audio.paused)
    el('state').textContent = r.paused ? 'Pausado' : (part.item ? 'Lendo' : 'Preparando')
    document.body.classList.toggle('is-paused', r.paused)
    el('progress').textContent = r.parts.length > 1 ? `trecho ${r.index + 1} de ${r.parts.length}` : ''

    // The words already spoken light up.
    const at = audio && part.item ? audio.currentTime : 0
    const spoken = part.item ? wordsSpoken(part.item.times, at) : 0
    if (spoken !== r.spokenShown) {
        const words = el('now').children
        for (let i = 0; i < words.length; i++) words[i].classList.toggle('is-spoken', i < spoken)
        r.spokenShown = spoken
        // A part longer than the box: the line being spoken stays the first one in view.
        const now = el('now')
        const current = words[Math.max(0, spoken - 1)]
        if (current && now.scrollHeight > now.clientHeight) now.scrollTop = current.offsetTop
    }

    // The bar and the clock: the parts before, plus where this one is, over all of them.
    let before = 0
    let total = 0
    r.parts.forEach((p, i) => {
        const s = partSeconds(r, p)
        if (i < r.index) before += s
        total += s
    })
    const elapsed = before + (part.item && audio ? audio.currentTime * part.item.speed / state.config.speed : 0)
    el('bar').style.width = `${total ? Math.min(100, (elapsed / total) * 100) : 0}%`
    el('clock').textContent = `${clock(elapsed)} de ${clock(total)}`

    // The meter beside the label follows the voice's loudness.
    let amp = 0
    if (playing && part.item.envelope) amp = part.item.envelope[Math.floor(audio.currentTime * ENVELOPE_RATE)] || 0
    const bars = el('meter').children
    for (let i = 0; i < bars.length; i++) {
        const wob = 0.6 + 0.4 * Math.abs(Math.sin(performance.now() / 90 + i * 1.7))
        bars[i].style.transform = `scaleY(${Math.max(0.15, amp * wob)})`
    }
}

function startRender() {
    if (state.rafId) return
    const loop = () => {
        state.rafId = requestAnimationFrame(loop)
        render()
    }
    loop()
}

function stopRender() {
    if (state.rafId) cancelAnimationFrame(state.rafId)
    state.rafId = null
}

function clearWindow() {
    for (const id of ['prev', 'now', 'next', 'progress', 'clock']) {
        const node = el(id)
        if (node) node.textContent = ''
    }
    el('bar').style.width = '0%'
    el('state').textContent = 'Lendo'
    document.body.classList.remove('is-paused')
    setHint('')
}

function teardownAudio() {
    const r = state.reading
    state.reading = null
    if (state.audioElement) {
        try { state.audioElement.pause() } catch {}
        try { state.audioElement.removeAttribute('src') } catch {}
        try { state.audioElement.load() } catch {}
        state.audioElement = null
    }
    try { state.playAbort?.() } catch {}
    state.playAbort = null
    r?.resume?.()
    for (const part of r?.parts ?? []) {
        if (part.item) try { URL.revokeObjectURL(part.item.url) } catch {}
    }
    stopRender()
    invoke('disarm_cancel_key').catch(() => {})
}

async function showWindow() {
    try { await getCurrentWindow().show() } catch {}
}

async function hideWindow() {
    try { await getCurrentWindow().hide() } catch {}
}

async function refreshConfig() {
    try {
        const cfg = await invoke('get_config')
        state.config = cfg
    } catch (err) {
        console.error('failed to load config', err)
    }
}

async function speakSelectionFlow() {
    if (state.inFlight) return
    state.inFlight = true
    const mySession = ++state.sessionId
    teardownAudio()
    clearWindow()
    reflectChips()

    try {
        // Read selection FIRST while the user's app still has focus.
        // Showing or focusing our window before this would steal focus
        // and the simulated Cmd+C would go to the wrong app.
        let text
        try {
            text = await invoke('read_selection')
        } catch (err) {
            if (state.sessionId !== mySession) return
            await applyPlayerLayout()
            await showWindow()
            // Without Accessibility macOS refuses the ⌘C; say so and open the app
            // window, whose status line takes the person to the switch.
            if (/accessibility/i.test(String(err))) {
                setHint('Falta ligar a Acessibilidade para o Text to Speech')
                try { await invoke('open_settings') } catch {}
            } else {
                setHint(String(err))
            }
            setTimeout(() => {
                if (state.sessionId === mySession) hideWindow()
            }, 1800)
            return
        }
        if (state.sessionId !== mySession || !text?.trim()) {
            if (!text?.trim() && state.sessionId === mySession) {
                await applyPlayerLayout()
                await showWindow()
                setHint('Nada selecionado')
                setTimeout(() => {
                    if (state.sessionId === mySession) hideWindow()
                }, 1800)
            }
            return
        }

        const r = startReading(text, state.config.engine === 'piper' ? 'piper' : 'rafael', mySession)
        state.reading = r
        ensureAhead(r)

        // Now safe to show + focus the player — selection is already captured.
        await applyPlayerLayout()
        await showWindow()
        try { await getCurrentWindow().setFocus() } catch (e) { console.warn('setFocus failed', e) }
        startRender()

        const finished = await readAll(r)
        if (finished && state.sessionId === mySession) {
            teardownAudio()
            hideWindow()
        } else if (isLive(r)) {
            // A part failed: the message stays a few seconds, then the window goes.
            teardownAudio()
            setTimeout(() => {
                if (state.sessionId === mySession) hideWindow()
            }, 4000)
        }
    } finally {
        state.inFlight = false
    }
}

function stopFlow() {
    state.sessionId++
    teardownAudio()
    state.inFlight = false
    hideWindow()
}

window.addEventListener('keydown', e => {
    const reading = isLive(state.reading)
    if (e.key === 'Escape') {
        e.preventDefault()
        if (state.inFlight || reading || state.audioElement) stopFlow()
        return
    }
    if (!reading || e.metaKey || e.ctrlKey || e.altKey) return
    if (e.key === ' ') { e.preventDefault(); togglePause() }
    else if (e.key === 'ArrowLeft') { e.preventDefault(); jump(-1) }
    else if (e.key === 'ArrowRight') { e.preventDefault(); jump(1) }
    else if (e.key === '-' || e.key === '_') { e.preventDefault(); changeSpeed(-SPEED_STEP) }
    else if (e.key === '+' || e.key === '=') { e.preventDefault(); changeSpeed(SPEED_STEP) }
}, true)

window.addEventListener('DOMContentLoaded', async () => {
    await refreshConfig()
    reflectChips()
    listen('tts://speak-selection', async () => {
        await refreshConfig()
        speakSelectionFlow()
    })
    listen('tts://stop-speaking', () => {
        stopFlow()
    })
})
