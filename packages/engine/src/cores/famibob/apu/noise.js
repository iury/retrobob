import { Envelope, Timer, NOISE_LOOKUP_TABLE_NTSC, AUDIO_CHANNEL } from '.'

export class Noise {
  constructor(mixer) {
    this.envelope = new Envelope()
    this.timer = new Timer(mixer, AUDIO_CHANNEL.NOISE)
    this.shiftRegister = 1
    this.modeFlag = false
    this.lookupTable = NOISE_LOOKUP_TABLE_NTSC
  }

  isMuted() {
    return (this.shiftRegister & 0x01) === 0x01
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

  endFrame() {
    this.timer.endFrame()
  }

  reloadLengthCounter() {
    this.envelope.lengthCounter.reloadCounter()
  }

  run(cycle) {
    while (this.timer.run(cycle)) {
      const feedback = (this.shiftRegister & 0x01) ^ ((this.shiftRegister >>> (this.modeFlag ? 6 : 1)) & 0x01)
      this.shiftRegister >>>= 1
      this.shiftRegister |= feedback << 14
      if (this.isMuted()) {
        this.timer.addOutput(0)
      } else {
        this.timer.addOutput(this.envelope.getVolume())
      }
    }
  }

  reset() {
    this.envelope.reset()
    this.timer.reset()
    this.timer.period = this.lookupTable[0] - 1
    this.shiftRegister = 1
    this.modeFlag = false
  }
}
