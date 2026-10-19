import { test, expect } from 'bun:test'
import { START_RAMP, FIRST_PART_MAX, PARAGRAPH_MAX, RAMP, splitForReading, splitIntoParagraphs, splitIntoParts, wordTimes, wordsSpoken, clock } from './reading.js'

const SAMPLE = `Em muitas situações, uma comunicação respeitosa e objetiva é suficiente.
"Agradeço o convite, mas não poderei participar."
"Hoje não tenho disponibilidade."
Isso não significa que explicações sejam sempre inadequadas. Em relações próximas, oferecer contexto pode demonstrar consideração.
Mas existe uma diferença entre explicar uma decisão e acreditar que precisamos obter autorização para tomá-la.
A clareza comunica respeito. A justificativa interminável pode revelar dificuldade para sustentar a própria escolha.`

const count = part => part.split(' ').length

test('the parts ramp up — 8, 20, 30, then 40 words at most — each filled to at least 75% but the last, and no word lost', () => {
    const parts = splitIntoParts(SAMPLE.repeat(4))
    const limitOf = i => RAMP[Math.min(i, RAMP.length - 1)]
    expect(parts.every((p, i) => count(p) <= limitOf(i))).toBe(true)
    expect(parts.slice(0, -1).every((p, i) => count(p) >= limitOf(i) * 0.75)).toBe(true)
    expect(parts.join(' ').split(' ')).toEqual(SAMPLE.repeat(4).split(/\s+/).filter(Boolean))
})

test('a long first sentence is cut at its comma, but never into a part too short to cover the next one', () => {
    const atComma = splitIntoParts('Quando a gente explica demais, a decisão parece pedir licença a quem ouve.')
    expect(atComma[0]).toBe('Quando a gente explica demais,')
    // A comma after 3 words would be under a second of audio: it is cut at the limit instead.
    const early = splitIntoParts('Em muitas situações, uma comunicação respeitosa e objetiva é suficiente.')
    expect(early[0].split(' ')).toHaveLength(8)
})

test('a first sentence of one or two words takes the next one along, up to 8 words', () => {
    const parts = splitIntoParts('Olá. Em muitas situações, uma comunicação respeitosa e objetiva é suficiente.')
    expect(parts[0]).toBe('Olá. Em muitas situações, uma comunicação respeitosa e')
    expect(parts[1]).toBe('objetiva é suficiente.')
})

test('short sentences are packed together up to the part', () => {
    expect(splitIntoParts('Oi. Tudo bem? Sim.')).toEqual(['Oi. Tudo bem? Sim.'])
})

test("Fish's words are matched to the text's words, punctuation and hyphens included", () => {
    const spoken = [
        { text: 'precisamos', start: 0 }, { text: 'obter', start: 0.4 }, { text: 'autorização', start: 0.64 },
        { text: 'para', start: 1.04 }, { text: 'tomá', start: 1.2 }, { text: 'la', start: 1.52 }, { text: 'A', start: 1.68 }, { text: 'clareza', start: 1.76 },
    ]
    const times = wordTimes('precisamos obter autorização para tomá-la. A clareza', spoken, 2.2)
    expect(times.map(t => t.start)).toEqual([0, 0.4, 0.64, 1.04, 1.2, 1.68, 1.76])
    expect(wordsSpoken(times, 1.3)).toBe(5)
})

test('without timings (Piper) the words are spread over the audio, in order', () => {
    const times = wordTimes('um dois três quatro', [], 4)
    expect(times[0].start).toBe(0)
    expect(times.every((t, i) => i === 0 || t.start > times[i - 1].start)).toBe(true)
    expect(times.at(-1).start).toBeLessThan(4)
})

test('the clock', () => {
    expect(clock(0)).toBe('0:00')
    expect(clock(65.4)).toBe('1:05')
    expect(clock(370)).toBe('6:10')
})

test('paragraphs are never cut: short ones in a row go together, each on its own line, up to the size of a part', () => {
    const parts = splitIntoParagraphs(SAMPLE.repeat(3).replaceAll('suficiente."', 'suficiente."'))
    const paragraphs = SAMPLE.repeat(3).split('\n').map(p => p.trim()).filter(Boolean)
    // Every part is whole paragraphs joined by new lines: splitting them back gives the paragraphs, in order.
    expect(parts.flatMap(p => p.split('\n'))).toEqual(paragraphs)
    expect(parts.length).toBeLessThan(paragraphs.length)
    expect(parts.every(p => p.split(/\s+/).length <= PARAGRAPH_MAX)).toBe(true)
})

test('a paragraph too long is divided only at the end of a sentence, in pieces of about the same size', () => {
    const sentence = 'A clareza comunica respeito, e a justificativa interminável pode revelar dificuldade para sustentar a própria escolha.'
    const paragraph = Array(13).fill(sentence).join(' ') // 13 × 17 = 221 words: no piece size lands on a sentence end by chance
    const parts = splitIntoParagraphs(`${paragraph}\nFim.`)
    expect(parts.at(-1)).toBe('Fim.')
    const pieces = parts.slice(0, -1)
    expect(pieces.length).toBeGreaterThan(2)
    expect(pieces.every(p => p.endsWith('escolha.') && p.split(' ').length <= PARAGRAPH_MAX)).toBe(true)
    expect(pieces.join(' ')).toBe(paragraph)
})

test('a single sentence longer than a part is the only thing cut inside, at a comma', () => {
    const long = Array(10).fill('uma palavra, outra palavra mais').join(' ') + ' fim.' // 51 words, commas inside
    const parts = splitIntoParagraphs(long, 20)
    expect(parts.every(p => p.split(' ').length <= 20)).toBe(true)
    expect(parts.slice(0, -1).every(p => p.endsWith(','))).toBe(true)
    expect(parts.join(' ')).toBe(long)
})

const words = text => text.split(' ').length
const LONG_FIRST = 'Em muitas situações, uma comunicação respeitosa e objetiva é suficiente para resolver o que parecia difícil. Agradeço o convite, mas não poderei participar desta vez. Hoje não tenho disponibilidade. Isso não significa que explicações sejam sempre inadequadas, porque em relações próximas oferecer contexto pode demonstrar consideração. Mas existe uma diferença entre explicar uma decisão e acreditar que precisamos obter autorização para tomá-la, e essa diferença muda tudo.'

test('the start ramps up at natural pauses — a sentence, then whole sentences of 25 and 45 words — then whole paragraphs', () => {
    const text = `${LONG_FIRST}\nA clareza comunica respeito.\nFim.`
    const parts = splitForReading(text)
    // 1. its comma is the 3rd word, under a second of audio: the sentence (16 words) goes whole
    expect(parts[0]).toBe('Em muitas situações, uma comunicação respeitosa e objetiva é suficiente para resolver o que parecia difícil.')
    // 2. whole sentences, up to 25 and then 45 words
    expect(words(parts[1])).toBeLessThanOrEqual(START_RAMP[0])
    expect(words(parts[2])).toBeLessThanOrEqual(START_RAMP[1])
    expect(parts.slice(1).every(p => /[.!?…]$/.test(p))).toBe(true)
    // 3. the rest: the end of the long paragraph and the two short ones, together, each paragraph on its own line
    expect(parts.at(-1).endsWith('muda tudo.\nA clareza comunica respeito.\nFim.')).toBe(true)
    expect(parts.join(' ').split(/\s+/)).toEqual(text.split(/\s+/))
})

test('a short first paragraph does not end the ramp: the next part is still small, made of whole sentences', () => {
    const parts = splitForReading(SAMPLE.repeat(4))
    expect(parts[0]).toBe('Em muitas situações, uma comunicação respeitosa e objetiva é suficiente.')
    expect(words(parts[1].replaceAll('\n', ' '))).toBeLessThanOrEqual(START_RAMP[0])
    expect(words(parts[2].replaceAll('\n', ' '))).toBeLessThanOrEqual(START_RAMP[1])
})

test('a first sentence of up to 12 words goes whole; a short paragraph is one part', () => {
    expect(splitForReading('Oi, tudo bem com você hoje?\nSim.')).toEqual(['Oi, tudo bem com você hoje?', 'Sim.'])
})

test('a first sentence of 13 to 20 words with no early comma goes whole, never cut in the middle', () => {
    const sentence = 'A justificativa interminável pode revelar dificuldade para sustentar a própria escolha diante dos outros.'
    expect(words(sentence)).toBeGreaterThan(FIRST_PART_MAX)
    expect(splitForReading(sentence)[0]).toBe(sentence)
})

test('the sample: no part starts or ends inside a sentence, except the first clause', () => {
    const parts = splitForReading(SAMPLE.repeat(3))
    expect(parts.slice(1).every(p => /[.!?…"]$/.test(p))).toBe(true)
    expect(parts.join(' ').split(/\s+/)).toEqual(SAMPLE.repeat(3).split(/\s+/).filter(Boolean))
})

test('a long first sentence is cut at a clause mark between the 5th and the 12th word', () => {
    const parts = splitForReading('Quando a gente explica demais, a decisão parece pedir licença a quem ouve e a quem não ouve.')
    expect(parts[0]).toBe('Quando a gente explica demais,')
    expect(parts[1]).toBe('a decisão parece pedir licença a quem ouve e a quem não ouve.')
})
