import { test, expect } from 'vitest'
import { BlipBuf } from './blip_buf'

const oversample = 1 << 20
const frameLen = (20 * oversample + oversample / 4) >> 0
const blipSize = ((frameLen * 2) / oversample) >> 0

const addDeltas = (blip, offset) => {
  blip.addDelta(((frameLen / 2) >> 0) + offset, +1000)
  blip.addDelta(frameLen + offset + 2 * oversample, +1000)
}

test('blip-buf: blip_end_frame, blip_add_delta invariance', () => {
  const one = new Float32Array(blipSize).fill(1)
  const two = new Float32Array(blipSize).fill(-1)

  {
    const blip = new BlipBuf(blipSize)
    addDeltas(blip, 0)
    addDeltas(blip, frameLen)
    blip.endFrame(frameLen * 2)
    expect(blip.readSamples(one, 0, blipSize, false)).toBe(blipSize)
  }

  {
    const blip = new BlipBuf(blipSize)
    addDeltas(blip, 0)
    blip.endFrame(frameLen)
    addDeltas(blip, 0)
    blip.endFrame(frameLen)
    expect(blip.readSamples(two, 0, blipSize, false)).toBe(blipSize)
  }

  expect(one).toEqual(two)
})

test('blip-buf: blip_read_samples invariance', () => {
  const blipSize = ((frameLen * 3) / oversample) >> 0

  const one = new Float32Array(blipSize).fill(+1)
  const two = new Float32Array(blipSize).fill(-1)

  {
    const blip = new BlipBuf(blipSize)

    addDeltas(blip, 0 * frameLen)
    addDeltas(blip, 1 * frameLen)
    addDeltas(blip, 2 * frameLen)
    blip.endFrame(3 * frameLen)

    const actual = blip.readSamples(one, 0, blipSize, false)
    expect(actual).toBe(blipSize)
  }

  {
    const blip = new BlipBuf(blipSize)
    let count = 0

    for (let n = 3; n--; ) {
      addDeltas(blip, 0)
      blip.endFrame(frameLen)
      count += blip.readSamples(two, count, blipSize - count, false)
    }

    expect(count).toBe(blipSize)
  }

  expect(one).toEqual(two)
})

test('blip-buf: blip_max_frame invariance', () => {
  const oversample = 32
  const frameLen = 4000 * oversample
  const blipSize = ((frameLen / oversample) * 3) >> 0

  const one = new Float32Array(blipSize).fill(+1)
  const two = new Float32Array(blipSize).fill(-1)

  {
    const blip = new BlipBuf(blipSize)
    blip.setRates(oversample, 1)

    let count = 0
    for (let n = 3; n--; ) {
      blip.endFrame((frameLen / 2) >> 0)
      blip.addDelta(((frameLen / 2) >> 0) + 2 * oversample, +1000)
      blip.endFrame((frameLen / 2) >> 0)
      count += blip.readSamples(one, count, blipSize - count, false)
    }
    expect(count).toBe(blipSize)
  }

  {
    const blip = new BlipBuf(blipSize)
    blip.setRates(oversample, 1)

    let count = 0
    for (let n = 3; n--; ) {
      blip.addDelta(frameLen + 2 * oversample, +1000)
      blip.endFrame(frameLen)
    }
    count += blip.readSamples(two, count, blipSize - count, false)
    expect(count).toBe(blipSize)
  }

  expect(one).toEqual(two)
})
