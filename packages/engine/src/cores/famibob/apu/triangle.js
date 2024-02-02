import { Timer, LengthCounter, AUDIO_CHANNEL } from '.'

const SEQUENCE = [
  15, 14, 13, 12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1, 0, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15,
]

export class Triangle {
  constructor(mixer) {
    this.lengthCounter = new LengthCounter()
    this.timer = new Timer(mixer, AUDIO_CHANNEL.TRIANGLE)
    this.linearCounter = 0
    this.linearCounterReload = 0
    this.linearReloadFlag = false
    this.linearControlFlag = false
    this.sequencePosition = 0
  }

  setEnabled(enabled) {
    this.lengthCounter.setEnabled(enabled)
  }

  get status() {
    return this.lengthCounter.status
  }

  tickLinearCounter() {
    if (this.linearReloadFlag) {
      this.linearCounter = this.linearCounterReload
    } else if (this.linearCounter > 0) {
      this.linearCounter--
    }
    if (!this.linearControlFlag) {
      this.linearControlFlag = false
    }
  }

  tickLengthCounter() {
    this.lengthCounter.tickLengthCounter()
  }

  endFrame() {
    this.timer.endFrame()
  }

  reloadLengthCounter() {
    this.lengthCounter.reloadCounter()
  }

  run(cycle) {
    while (this.timer.run(cycle)) {
      if (this.lengthCounter.status && this.linearCounter > 0) {
        this.sequencePosition = (this.sequencePosition + 1) & 0x1f
        if (this.timer.period >= 2) {
          this.timer.addOutput(SEQUENCE[this.sequencePosition])
        }
      }
    }
  }

  reset() {
    this.timer.reset()
    this.lengthCounter.reset()
    this.linearCounter = 0
    this.linearCounterReload = 0
    this.linearReloadFlag = false
    this.linearControlFlag = false
    this.sequencePosition = 0
  }
}
