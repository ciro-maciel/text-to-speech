// The reading's pure logic, apart from the window so it can be tested with bun
// (reading.test.js): how a selection becomes parts, which word is being
// spoken, and the clock.

// Measured on 15/10/2026 at 1.5x on the published server: 8 words are ready
// in 2.5 s (2.0 s of audio), 20 in 4.6 s (4.9 s), 40 in 7.4 s (8.7 s). A short
// first part starts the voice in 2.5 s instead of ~7; each next part must be
// ready when the ones before it have played, so the parts grow step by step
// and each is filled to its size (a part cut short leaves the next one late).
export const RAMP = [8, 20, 30, 40]
// The web page also builds the whole MP3 to download: past the first parts,
// bigger ones get more audio per request (1000 characters, about 170 words,
// took 25 s — 6.8 words a second, against 5.4 for 40 words). They stop at 100
// words: a jump ahead waits for its part, and 170 words left the page silent
// for 50 s after a jump (measured 15/10).
export const RAMP_WEB = [8, 20, 30, 40, 60, 100]

const SENTENCE_END = /(?<=[.!?…])\s+|\n+/
const CLAUSE_END = /[,;:—)]$/

/**
 * Where to cut a sentence longer than `limit` words: after the last comma-like
 * mark that leaves at least `shortest` words, or at the limit. The first part
 * must not be too short either: 3 words are under a second of audio, and the
 * second part takes 4.6 s to be ready.
 */
function cutAt(words, limit, shortest) {
    for (let i = limit; i >= shortest; i--) {
        if (CLAUSE_END.test(words[i - 1])) return i
    }
    return limit
}

/**
 * The selection → parts in reading order: sentences packed into parts of at
 * most ramp[0] words, then ramp[1], and so on, the last size for the rest. A
 * sentence longer than the part is cut at a clause, or at the limit.
 */
export function splitIntoParts(text, ramp = RAMP) {
    const queue = String(text)
        .split(SENTENCE_END)
        .map(s => s.trim().split(/\s+/).filter(Boolean))
        .filter(words => words.length)
    const parts = []
    let current = []
    const limit = () => ramp[Math.min(parts.length, ramp.length - 1)]
    const flush = () => {
        if (current.length) parts.push(current.join(' '))
        current = []
    }
    while (queue.length) {
        const sentence = queue.shift()
        if (current.length + sentence.length <= limit()) {
            current.push(...sentence)
        } else if (current.length && current.length < limit() * 0.75) {
            // A part this short ("Olá.") would be over before the next one is
            // ready: it takes the next sentence's first words, to a comma if
            // there is one.
            const room = limit() - current.length
            const cut = cutAt(sentence, room, Math.ceil(room / 2))
            current.push(...sentence.slice(0, cut))
            flush()
            queue.unshift(sentence.slice(cut))
        } else if (current.length) {
            flush()
            queue.unshift(sentence)
        } else {
            const cut = cutAt(sentence, limit(), parts.length ? Math.ceil(limit() / 2) : 5)
            current = sentence.slice(0, cut)
            flush()
            queue.unshift(sentence.slice(cut))
        }
    }
    flush()
    return parts
}

/**
 * THE MAC APP CUTS AT PARAGRAPHS (Ciro, 16/10/2026): the ramp above cut
 * sentences in the middle to start fast, and the voice lost the sense of
 * what it read. Here each paragraph is read whole; short ones in a row go
 * together in one part, up to `max` words, each still on its own line (a
 * text of one-line paragraphs was 71 requests, and its MP3 took 81 s instead
 * of 64). Only a paragraph longer than `max` words is divided, at the end of
 * a sentence, into pieces of about the same size. A single sentence longer
 * than `max` is the one case cut inside, at its last comma.
 */
export const PARAGRAPH_MAX = 80

export function splitIntoParagraphs(text, max = PARAGRAPH_MAX) {
    const parts = []
    let packed = [] // whole short paragraphs waiting to go together
    let packedWords = 0
    const flushPacked = () => {
        if (packed.length) parts.push(packed.join('\n'))
        packed = []
        packedWords = 0
    }
    for (const paragraph of String(text).split(/\n+/).map(p => p.trim()).filter(Boolean)) {
        const total = paragraph.split(/\s+/).length
        if (total <= max) {
            if (packedWords + total > max) flushPacked()
            packed.push(paragraph)
            packedWords += total
            continue
        }
        flushPacked()
        // Sentences, each no longer than `max` (a longer one is cut at a comma).
        const sentences = []
        for (const sentence of paragraph.split(/(?<=[.!?…])\s+/)) {
            let words = sentence.split(/\s+/).filter(Boolean)
            while (words.length > max) {
                const cut = cutAt(words, max, Math.ceil(max / 2))
                sentences.push(words.slice(0, cut))
                words = words.slice(cut)
            }
            if (words.length) sentences.push(words)
        }
        // Packed into pieces of about the same size, none over `max`.
        const target = Math.ceil(total / Math.ceil(total / max))
        let current = []
        for (const sentence of sentences) {
            if (current.length && (current.length + sentence.length > max || current.length >= target)) {
                parts.push(current.join(' '))
                current = []
            }
            current.push(...sentence)
        }
        if (current.length) parts.push(current.join(' '))
    }
    flushPacked()
    return parts
}

/**
 * THE START OF A READING (Ciro, 16/10/2026): a whole first paragraph of 80
 * words took ~12 s before the voice. The start ramps up — only there, and
 * only at natural pauses, so no sense is lost:
 *
 * 1. the first part is the first sentence if it has up to 12 words (ready in
 *    ~2.5 s); a longer one is cut at its first clause mark (, ; : —) between
 *    the 5th and the 12th word; with none, the whole sentence if it has up to
 *    20; only a longer one with no mark is cut at the 12th word;
 * 2. then whole sentences, up to 25 words, then up to 45 — across paragraphs:
 *    a short first paragraph used to be followed at once by 80 words of whole
 *    paragraphs, ready only after the first had played (7 s of silence, 16/10);
 * 3. from there, whole paragraphs (splitIntoParagraphs): the rest of the one
 *    the ramp stopped in, then the others, short ones packed together.
 *
 * Measured at 1.5x: 8 words ready in 2.5 s and 2.0 s long, 20 in 4.6 s and
 * 4.9 s, 40 in 7.4 s and 8.7 s; three parts go at once, from the start.
 */
export const FIRST_PART_MAX = 12
export const START_RAMP = [25, 45]

function firstClause(words) {
    if (words.length <= FIRST_PART_MAX) return words.length
    for (let i = 5; i <= FIRST_PART_MAX; i++) {
        if (CLAUSE_END.test(words[i - 1])) return i
    }
    if (words.length <= 20) return words.length
    for (let i = FIRST_PART_MAX + 1; i <= 20; i++) {
        if (CLAUSE_END.test(words[i - 1])) return i
    }
    return FIRST_PART_MAX
}

/**
 * A text copied from a PDF or a book breaks its lines in the middle of the
 * sentences ("people who receive the / favor often / feel used."); cut at
 * paragraphs, each of those lines was read as one, with a pause in the middle
 * of the sentence (19/10/2026). A line joins the next one unless it ends a
 * sentence (. ! ? … : ; maybe followed by a quote or a parenthesis), or it is
 * a short line, like a title, followed by one that starts with a capital.
 */
const LINE_ENDS_SENTENCE = /[.!?…:;]["'”’»)\]]*$/
const STARTS_UPPER = /^["'“‘«(\[—–-]*[A-ZÀ-ÖØ-Þ0-9]/

export function unwrapLines(text) {
    const lines = String(text).split('\n').map(l => l.trim())
    let out = ''
    for (let i = 0; i < lines.length; i++) {
        const line = lines[i]
        if (!line) {
            if (out && !out.endsWith('\n')) out += '\n'
            continue
        }
        out += line
        const next = lines[i + 1]
        if (next === undefined) break
        const isTitle = line.split(/\s+/).length <= 6 && STARTS_UPPER.test(next) && !/[,\-–—]$/.test(line)
        out += !next || LINE_ENDS_SENTENCE.test(line) || isTitle ? '\n' : ' '
    }
    return out.replace(/\n+/g, '\n').trim()
}

export function splitForReading(text, max = PARAGRAPH_MAX) {
    // Every sentence of the text, and whether it ends its paragraph.
    const sentences = []
    for (const paragraph of unwrapLines(text).split(/\n+/).map(p => p.trim()).filter(Boolean)) {
        const own = paragraph.split(/(?<=[.!?…])\s+/).map(x => x.split(/\s+/).filter(Boolean)).filter(w => w.length)
        own.forEach((words, i) => sentences.push({ words, ends: i === own.length - 1 }))
    }
    if (!sentences.length) return []
    // A part's text: its sentences, a new line where a paragraph ends inside it.
    const join = list => list.map((x, i) => x.words.join(' ') + (i < list.length - 1 ? (x.ends ? '\n' : ' ') : '')).join('')

    const head = sentences.shift()
    const cut = firstClause(head.words)
    const parts = [head.words.slice(0, cut).join(' ')]
    if (cut < head.words.length) sentences.unshift({ words: head.words.slice(cut), ends: head.ends })

    for (const limit of START_RAMP) {
        if (!sentences.length) break
        const part = []
        let size = 0
        while (sentences.length && (!part.length || size + sentences[0].words.length <= limit)) {
            const next = sentences.shift()
            part.push(next)
            size += next.words.length
        }
        // A single sentence longer than a whole part is still cut at its commas.
        parts.push(...(size > max ? splitIntoParagraphs(join(part), max) : [join(part)]))
    }

    // The rest, back into paragraphs: the end of the one the ramp stopped in, then the others.
    const rest = []
    let paragraph = []
    for (const x of sentences) {
        paragraph.push(x.words.join(' '))
        if (x.ends) {
            rest.push(paragraph.join(' '))
            paragraph = []
        }
    }
    if (paragraph.length) rest.push(paragraph.join(' '))
    return [...parts, ...splitIntoParagraphs(rest.join('\n'), max)]
}

const letters = text =>
    String(text)
        .toLowerCase()
        .normalize('NFD')
        .replace(/[̀-ͯ]/g, '')
        .replace(/[^a-z0-9]/g, '')

/**
 * The part's own words, as shown, each with the second it starts in the part's
 * audio. With Fish's timings (`spoken`: [{ text, start }]) the words are matched
 * in order by their letters — "tomá-la." is Fish's "tomá" and "la"; without
 * them (Piper), or past the last one matched, the start is the word's place in
 * the text times the audio's length.
 */
export function wordTimes(text, spoken = [], duration = 0) {
    const tokens = String(text).split(/\s+/).filter(Boolean)
    const total = tokens.reduce((n, t) => n + t.length + 1, 0) || 1
    let offset = 0
    let j = 0
    let last = 0
    return tokens.map(token => {
        const estimate = (offset / total) * duration
        offset += token.length + 1
        const target = letters(token)
        let start
        if (target && j < spoken.length) {
            start = spoken[j].start
            let heard = ''
            while (j < spoken.length && heard.length < target.length) heard += letters(spoken[j++].text)
        } else if (!target) {
            start = last
        } else {
            start = Math.max(estimate, last)
        }
        last = Math.max(start, last)
        return { text: token, start: last }
    })
}

/** How many of `times` have started at `seconds`. */
export function wordsSpoken(times, seconds) {
    let n = 0
    while (n < times.length && times[n].start <= seconds) n++
    return n
}

export function clock(seconds) {
    const s = Math.max(0, Math.round(seconds))
    return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`
}
