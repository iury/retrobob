import { LengthCounter } from '.'

export class Envelope {
  constructor() {
    this.lengthCounter = new LengthCounter()
    this.constantVolume = false
    this.volume = 0
    this.start = false
    this.divider = 0
    this.counter = 0
  }

  initEnvelope(value) {
    this.lengthCounter.initLengthCounter((value & 0x20) === 0x20)
    this.constantVolume = (value & 0x10) === 0x10
    this.volume = value & 0x0f
  }

  resetEnvelope() {
    this.start = true
  }

  getVolume() {
    if (this.lengthCounter.status) {
      return this.constantVolume ? this.volume : this.counter
    } else {
      return 0
    }
  }

  tickEnvelope() {
    if (!this.start) {
      this.divider--
      if (this.divider < 0) {
        this.divider = this.volume
        if (this.counter > 0) {
          this.counter--
        } else if (this.lengthCounter.halt) {
          this.counter = 15
        }
      }
    } else {
      this.start = false
      this.counter = 15
      this.divider = this.volume
    }
  }

  reset() {
    this.lengthCounter.reset()
    this.constantVolume = false
    this.volume = 0
    this.start = false
    this.divider = 0
    this.counter = 0
  }
}
