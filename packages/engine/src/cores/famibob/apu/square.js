import { AUDIO_CHANNEL, Envelope, Timer } from '.'

/** @enum */
export const SQUARE_CHANNEL = { ONE: 'ONE', TWO: 'TWO' }

const DUTY_SEQUENCES = [
  [0, 0, 0, 0, 0, 0, 0, 1],
  [0, 0, 0, 0, 0, 0, 1, 1],
  [0, 0, 0, 0, 1, 1, 1, 1],
  [1, 1, 1, 1, 1, 1, 0, 0],
]

export class Square {
  constructor(mixer, channel) {
    this.channel = channel
    this.envelope = new Envelope()
    this.timer = new Timer(mixer, channel === SQUARE_CHANNEL.ONE ? AUDIO_CHANNEL.SQUARE1 : AUDIO_CHANNEL.SQUARE2)
    this.isMMC5Square = false
    this.duty = 0
    this.dutyPos = 0
    this.sweepEnabled = false
    this.sweepPeriod = 0
    this.sweepNegate = false
    this.sweepShift = 0
    this.reloadSweep = false
    this.sweepDivider = 0
    this.sweepTargetPeriod = 0
    this.realPeriod = 0
  }

  initSweep(value) {
    this.sweepEnabled = (value & 0x80) === 0x80
    this.sweepNegate = (value & 0x08) === 0x08
    this.sweepPeriod = ((value & 0x70) >>> 4) + 1
    this.sweepShift = value & 0x07
    this.updateTargetPeriod()
    this.reloadSweep = true
  }

  updateTargetPeriod() {
    const shiftResult = this.realPeriod >>> this.sweepShift
    if (this.sweepNegate) {
      this.sweepTargetPeriod = this.realPeriod - shiftResult
      if (this.channel === SQUARE_CHANNEL.ONE) {
        this.sweepTargetPeriod--
      }
    } else {
      this.sweepTargetPeriod = this.realPeriod + shiftResult
    }
  }

  updateOutput() {
    if (this.isMuted()) {
      this.timer.addOutput(0)
    } else {
      this.timer.addOutput(DUTY_SEQUENCES[this.duty][this.dutyPos] * this.envelope.getVolume())
    }
  }

  setPeriod(newPeriod) {
    this.realPeriod = newPeriod
    this.timer.period = this.realPeriod * 2 + 1
    this.updateTargetPeriod()
  }

  isMuted() {
    return this.realPeriod < 8 || (!this.sweepNegate && this.sweepTargetPeriod > 0x7ff)
  }

  setEnabled(enabled) {
    this.envelope.lengthCounter.setEnabled(enabled)
  }

  get status() {
    return this.envelope.lengthCounter.status
  }

  tickEnvelope() {
    this.envelope.tickEnvelope()
  }

  tickLengthCounter() {
    this.envelope.lengthCounter.tickLengthCounter()
  }

  tickSweep() {
    this.sweepDivider--
    if (this.sweepDivider === 0) {
      if (this.sweepShift > 0 && this.sweepEnabled && this.realPeriod >= 8 && this.sweepTargetPeriod <= 0x7ff) {
        this.setPeriod(this.sweepTargetPeriod)
      }
      this.sweepDivider = this.sweepPeriod
    }

    if (this.reloadSweep) {
      this.sweepDivider = this.sweepPeriod
      this.reloadSweep = false
    }
  }

  endFrame() {
    this.timer.endFrame()
  }

  reloadLengthCounter() {
    this.envelope.lengthCounter.reloadCounter()
  }

  run(cycle) {
    while (this.timer.run(cycle)) {
      this.dutyPos = (this.dutyPos - 1) & 0x07
      this.updateOutput()
    }
  }

  reset() {
    this.envelope.reset()
    this.timer.reset()
    this.duty = 0
    this.dutyPos = 0
    this.realPeriod = 0
    this.sweepEnabled = false
    this.sweepPeriod = 0
    this.sweepNegate = false
    this.sweepShift = 0
    this.reloadSweep = false
    this.sweepDivider = 0
    this.sweepTargetPeriod = 0
    this.updateTargetPeriod()
  }
}
