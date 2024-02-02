const LOOKUP_TABLE = [
  10, 254, 20, 2, 40, 4, 80, 6, 160, 8, 60, 10, 14, 12, 26, 14, 12, 16, 24, 18, 48, 20, 96, 22, 192, 24, 72, 26, 16, 28,
  32, 30,
]

export class LengthCounter {
  constructor() {
    this.newHaltValue = false
    this.enabled = false
    this.halt = false
    this.counter = 0
    this.reloadValue = 0
    this.previousValue = 0
  }

  initLengthCounter(haltFlag) {
    this.newHaltValue = haltFlag
  }

  loadLengthCounter(value) {
    if (this.enabled) {
      this.reloadValue = LOOKUP_TABLE[value]
      this.previousValue = this.counter
    }
  }

  reloadCounter() {
    if (this.reloadValue > 0) {
      if (this.counter === this.previousValue) {
        this.counter = this.reloadValue
      }
      this.reloadValue = 0
    }
    this.halt = this.newHaltValue
  }

  tickLengthCounter() {
    if (this.counter > 0 && !this.halt) this.counter--
  }

  get status() {
    return this.counter > 0
  }

  setEnabled(enabled) {
    if (!enabled) this.counter = 0
    this.enabled = enabled
  }

  reset() {
    this.enabled = false
    this.halt = false
    this.counter = 0
    this.newHaltValue = false
    this.reloadValue = 0
    this.previousValue = 0
  }
}
