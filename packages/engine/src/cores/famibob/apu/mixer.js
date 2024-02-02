import { BlipBuf } from '../../../blip_buf'
import { AUDIO_CHANNEL } from '.'

export class Mixer {
  constructor(region) {
    this.region = region
    this.cycleLength = 10000
    this.maxSampleRate = 96000
    this.maxSamplesPerFrame = this.maxSampleRate / 60
    this.timestamps = []
    this.outputBuffer = new Float32Array(this.maxSamplesPerFrame).fill(0)
    this.channelOutput = Array.from({ length: 11 }, () => new Int16Array(this.cycleLength).fill(0))
    this.currentOutput = new Int16Array(11).fill(0)
    this.previousOutput = 0
    this.sampleRate = 96000
    this.clockRate = 0
    this.sampleCount = 0
    this.blipBuf = new BlipBuf(this.maxSamplesPerFrame)
  }

  setRegion(region) {
    this.region = region
    this.updateRates(true)
  }

  addDelta(channel, time, delta) {
    if (delta !== 0) {
      this.timestamps.push(time)
      this.channelOutput[channel][time] += delta
    }
  }

  playAudioBuffer(time) {
    this.endFrame(time)
    this.sampleCount += this.blipBuf.readSamples(this.outputBuffer, this.sampleCount, this.maxSamplesPerFrame, false)
    this.updateRates(false)
  }

  updateRates(force) {
    const clockRate = this.region ? 1789773 : 1662607

    if (force || this.clockRate !== clockRate) {
      this.clockRate = clockRate
      this.blipBuf.setRates(this.clockRate, this.sampleRate)
    }
  }

  getChannelOutput(channel) {
    return this.currentOutput[channel]
  }

  getOutputVolume() {
    const squareOutput = this.getChannelOutput(AUDIO_CHANNEL.SQUARE1) + this.getChannelOutput(AUDIO_CHANNEL.SQUARE2)
    const tndOutput =
      3 * this.getChannelOutput(AUDIO_CHANNEL.TRIANGLE) +
      2 * this.getChannelOutput(AUDIO_CHANNEL.NOISE) +
      this.getChannelOutput(AUDIO_CHANNEL.DMC)

    const squareVolume = Math.trunc(477600 / (8128.0 / squareOutput + 100.0)) >> 0
    const tndVolume = Math.trunc(818350 / (24329.0 / tndOutput + 100.0)) >> 0

    return (
      ((squareVolume +
        tndVolume +
        this.getChannelOutput(AUDIO_CHANNEL.FDS) * 20 +
        this.getChannelOutput(AUDIO_CHANNEL.MMC5) * 43 +
        this.getChannelOutput(AUDIO_CHANNEL.NAMCO163) * 20 +
        this.getChannelOutput(AUDIO_CHANNEL.SUNSOFT5B) * 15 +
        this.getChannelOutput(AUDIO_CHANNEL.VRC6) * 75 +
        this.getChannelOutput(AUDIO_CHANNEL.VRC7)) <<
        16) >>
      16
    )
  }

  endFrame(time) {
    for (const stamp of Array.from(new Set(this.timestamps)).sort((a, b) => a - b)) {
      for (let i = 0; i < 11; i++) {
        this.currentOutput[i] += this.channelOutput[i][stamp]
      }

      const output = this.getOutputVolume() * 4
      this.blipBuf.addDelta(stamp, output - this.previousOutput)
      this.previousOutput = output
    }

    this.blipBuf.endFrame(time)
    this.timestamps = []
    for (let i = 0; i < 11; i++) this.channelOutput[i].fill(0)
  }

  reset() {
    this.sampleOount = 0
    this.previousOutput = 0
    this.blipBuf.clear()
    this.timestamps = []
    this.currentOutput.fill(0)
    for (let i = 0; i < 11; i++) this.channelOutput[i].fill(0)
    this.updateRates(true)
  }
}
