import { test, expect } from 'vitest'
import { BlipBuf } from './blip_buf'

const oversample = 1 << 20
const blipSize = 2000

test('blip-buf: blip_end_frame, blip_samples_avail', () => {
  const blip = new BlipBuf(blipSize)

  blip.endFrame(oversample)
  expect(blip.avail).toBe(1)

  blip.endFrame(oversample * 2)
  expect(blip.avail).toBe(3)
})

test('blip-buf: blip_end_frame, blip_samples_avail fractional', () => {
  const blip = new BlipBuf(blipSize)

  blip.endFrame(oversample * 2 - 1)
  expect(blip.avail).toBe(1)

  blip.endFrame(1)
  expect(blip.avail).toBe(2)
})

test('blip-buf: blip_end_frame limits', () => {
  const blip = new BlipBuf(blipSize)

  blip.endFrame(0)
  expect(blip.avail).toBe(0)

  blip.endFrame(blipSize * oversample + oversample - 1)
  expect(() => blip.endFrame(1)).toThrow()
})

test('blip-buf: blip_clocks_needed')
{
  const blip = new BlipBuf(blipSize)

  expect(blip.clocksNeeded(0)).toBe(0 * oversample)
  expect(blip.clocksNeeded(2)).toBe(2 * oversample)

  blip.endFrame(1)
  expect(blip.clocksNeeded(0)).toBe(0)
  expect(blip.clocksNeeded(2)).toBe(2 * oversample - 1)
}

test('blip-buf: blip_clocks_needed limits', () => {
  const blip = new BlipBuf(blipSize)

  expect(() => blip.clocksNeeded(-1)).toThrow()

  blip.endFrame(oversample * 2 - 1)
  expect(blip.clocksNeeded(blipSize - 1)).toBe((blipSize - 2) * oversample + 1)

  blip.endFrame(1)
  expect(() => blip.clocksNeeded(blipSize - 1)).toThrow()
})

test('blip-buf: blip_clear', () => {
  const blip = new BlipBuf(blipSize)

  blip.endFrame(2 * oversample - 1)
  blip.clear()
  expect(blip.avail).toBe(0)
  expect(blip.clocksNeeded(1)).toBe(oversample)
})

test('blip-buf: blip_read_samples', () => {
  const blip = new BlipBuf(blipSize)
  const buf = new Float32Array([-1, -1])

  blip.endFrame(3 * oversample + oversample - 1)
  expect(blip.readSamples(buf, 0, 2, false)).toBe(2)
  expect(buf[0]).toBe(0)
  expect(buf[1]).toBe(0)

  expect(blip.avail).toBe(1)
  expect(blip.clocksNeeded(1)).toBe(1)
})

test('blip-buf: blip_read_samples stereo', () => {
  const blip = new BlipBuf(blipSize)
  const buf = new Float32Array([-1, -1, -1])

  blip.endFrame(2 * oversample)
  expect(blip.readSamples(buf, 0, 2, true)).toBe(2)
  expect(buf[0]).toBe(0)
  expect(buf[1]).toBe(-1)
  expect(buf[2]).toBe(0)
})

test('blip-buf: blip_read_samples limits to avail', () => {
  const blip = new BlipBuf(blipSize)
  const buf = new Float32Array([-1, -1])

  blip.endFrame(oversample * 2)
  expect(blip.readSamples(buf, 0, 3, false)).toBe(2)
  expect(blip.avail).toBe(0)
  expect(buf[0]).toBe(0)
  expect(buf[1]).toBe(0)
})

test('blip-buf: blip_read_samples limits', () => {
  const blip = new BlipBuf(blipSize)
  expect(blip.readSamples(new Float32Array(), 0, 1, false)).toBe(0)
  expect(() => blip.readSamples(new Float32Array(), 0, -1, false)).toThrow()
})

test('blip-buf: blip_set_rates', () => {
  const blip = new BlipBuf(blipSize)

  blip.setRates(2, 2)
  expect(blip.clocksNeeded(10)).toBe(10)

  blip.setRates(2, 4)
  expect(blip.clocksNeeded(10)).toBe(5)

  blip.setRates(4, 2)
  expect(blip.clocksNeeded(10)).toBe(20)
})

test('blip-buf: blip_set_rates rounds sample rate up', () => {
  const blip = new BlipBuf(blipSize)
  for (let r = 1; r < 10000; r++) {
    blip.setRates(r, 1)
    expect(blip.clocksNeeded(1)).toBeLessThanOrEqual(r)
  }
})

test('blip-buf: blip_set_rates accuracy', () => {
  const blip = new BlipBuf(blipSize)
  const max_error = 100

  for (let r = blipSize / 2; r < blipSize; r++) {
    for (let c = (r / 2) >> 0; c < 8000000; c += (c / 32) >> 0) {
      blip.setRates(c, r)
      const error = blip.clocksNeeded(r) - c
      expect(error < 0 ? -error : error).toBeLessThan(c / max_error)
    }
  }
})

test('blip-buf: blip_set_rates high accuracy', () => {
  const blip = new BlipBuf(blipSize)

  blip.setRates(1000000, blipSize)
  if (blip.clocksNeeded(blipSize) !== 1000000) return

  for (let r = (blipSize / 2) >> 0; r < blipSize; r++) {
    for (let c = (r / 2) >> 0; c < 200000000; c += (c / 32) >> 0) {
      blip.setRates(c, r)
      expect(blip.clocksNeeded(r)).toBe(c)
    }
  }
})

test('blip-buf: blip_set_rates long-term accuracy', () => {
  const blip = new BlipBuf(blipSize)

  blip.setRates(1000000, blipSize)
  if (blip.clocksNeeded(blipSize) !== 1000000) return

  const clockRate = 1789773
  const sampleRate = 44100
  const secs = 1000

  blip.setRates(clockRate, sampleRate)

  const bufSize = (blipSize / 2) >> 0
  const clockSize = blip.clocksNeeded(bufSize) - 1
  let totalSamples = 0
  let remain = clockRate * secs

  for (;;) {
    const n = remain < clockSize ? remain : clockSize
    if (!n) break

    blip.endFrame(n)
    const buf = new Float32Array(bufSize)
    totalSamples += blip.readSamples(buf, 0, bufSize, false)

    remain -= n
  }

  expect(totalSamples).toBe(sampleRate * secs)
})

test('blip-buf: blip_add_delta limits', () => {
  const blip = new BlipBuf(blipSize)

  blip.addDelta(0, 1)
  blip.addDelta((blipSize + 3) * oversample - 1, 1)

  expect(() => blip.addDelta((blipSize + 3) * oversample, 1)).toThrow()
  expect(() => blip.addDelta(-1, 1)).toThrow()
})

test('blip-buf: blip_add_delta_fast limits', () => {
  const blip = new BlipBuf(blipSize)

  blip.addDeltaFast(0, 1)
  blip.addDeltaFast((blipSize + 3) * oversample - 1, 1)

  expect(() => blip.addDeltaFast((blipSize + 3) * oversample, 1)).toThrow()
  expect(() => blip.addDeltaFast(-1, 1)).toThrow()
})
