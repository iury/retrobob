import crc32 from 'crc/crc32'
import { test, expect } from 'vitest'
import { BlipBuf } from './blip_buf'

const oversample = 1 << 20
const blipSize = 32

const dump = (blip, buf) => {
  blip.endFrame(blipSize * oversample)
  blip.readSamples(buf, 0, blipSize, false)
  let hash = ''
  for (let i = 1; i < blipSize; i++) hash += `${buf[i] - buf[i - 1]} `
  hash += '\n'
  blip.clear()
  return hash
}

test('blip-buf: blip_add_delta_fast, blip_read_samples', () => {
  const blip = new BlipBuf(blipSize)
  const buf = new Float32Array(blipSize)

  blip.addDeltaFast(2 * oversample, +16384)
  expect(crc32(dump(blip, buf))).toBe(878402093)

  blip.addDeltaFast((2.5 * oversample) >> 0, +16384)
  expect(crc32(dump(blip, buf))).toBe(3045866028)
})

test('blip-buf: blip_add_delta tails', () => {
  const blip = new BlipBuf(blipSize)
  const buf = new Float32Array(blipSize)

  blip.addDelta(0, +16384)
  expect(crc32(dump(blip, buf))).toBe(894419341)

  blip.addDelta((oversample / 2) >> 0, +16384)
  expect(crc32(dump(blip, buf))).toBe(1937473212)
})

test('blip-buf: blip_add_delta interpolation', () => {
  const blip = new BlipBuf(blipSize)
  const buf = new Float32Array(blipSize)

  blip.addDelta((oversample / 2) >> 0, +32768)
  let s = dump(blip, buf)

  blip.addDelta(((oversample / 2) >> 0) + ((oversample / 64) >> 0), +32768)
  s += dump(blip, buf)

  blip.addDelta(((oversample / 2) >> 0) + ((oversample / 32) >> 0), +32768)
  s += dump(blip, buf)

  expect(crc32(s)).toBe(3901029712)
})

test('blip-buf: saturation 1', () => {
  const blip = new BlipBuf(blipSize)
  const buf = new Float32Array(blipSize)

  blip.addDeltaFast(0, +35000)
  blip.endFrame(oversample * blipSize)
  blip.readSamples(buf, 0, blipSize, false)

  expect(buf[20]).toBeCloseTo(1)
})

test('blip-buf: saturation 2', () => {
  const blip = new BlipBuf(blipSize)
  const buf = new Float32Array(blipSize)

  blip.addDeltaFast(0, -35000)
  blip.endFrame(oversample * blipSize)
  blip.readSamples(buf, 0, blipSize, false)

  expect(buf[20]).toBeCloseTo(-1)
})

test('blip-buf: stereo interleave', () => {
  const blip = new BlipBuf(blipSize)
  const buf = new Float32Array(blipSize)
  const stereoBuf = new Float32Array(blipSize * 2)

  blip.addDelta(0, +16384)
  blip.endFrame(blipSize * oversample)
  blip.readSamples(buf, 0, blipSize, false)

  blip.clear()
  blip.addDelta(0, +16384)
  blip.endFrame(blipSize * oversample)
  blip.readSamples(stereoBuf, 0, blipSize, true)

  for (let i = 0; i < blipSize; i++) expect(stereoBuf[i * 2]).toBe(buf[i])
})

test('blip_clear', () => {
  const blip = new BlipBuf(blipSize)
  const buf = new Float32Array(blipSize)

  blip.addDelta(0, 32768)
  blip.addDelta((blipSize + 2) * oversample + oversample / 2, 32768)

  blip.clear()

  for (let n = 2; n--; ) {
    blip.endFrame(blipSize * oversample)
    expect(blip.readSamples(buf, 0, blipSize, false)).toBe(blipSize)
    for (let i = 0; i < blipSize; i++) expect(buf[i]).toBe(0)
  }
})
