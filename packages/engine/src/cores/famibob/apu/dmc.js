import { Timer, AUDIO_CHANNEL, DMC_LOOKUP_TABLE_NTSC } from '.'
import { fixRange16 } from '../../../utils'

export class DMC {
  constructor(mixer) {
    this.irq = false
    this.timer = new Timer(mixer, AUDIO_CHANNEL.DMC)
    this.sampleAddr = 0
    this.sampleLength = 0
    this.outputLevel = 0
    this.irqEnabled = false
    this.loopFlag = false
    this.currentAddr = 0
    this.bytesRemaining = 0
    this.readBuffer = 0
    this.bufferEmpty = true
    this.shiftRegister = 0
    this.bitsRemaining = 0
    this.silenceFlag = true
    this.needsToRun = false
    this.needsInit = 0
    this.lookupTable = DMC_LOOKUP_TABLE_NTSC
    this.transferRequested = false
  }

  initSample() {
    this.currentAddr = this.sampleAddr
    this.bytesRemaining = this.sampleLength
    this.needsToRun = this.bytesRemaining > 0
  }

  startDMCTransfer() {
    if (this.bufferEmpty && this.bytesRemaining > 0) {
      this.transferRequested = true
    }
  }

  setDMCReadBuffer(value) {
    if (this.bytesRemaining > 0) {
      this.readBuffer = value
      this.bufferEmpty = false
      this.currentAddr = fixRange16(this.currentAddr + 1)
      if (this.currentAddr === 0) this.currentAddr = 0x8000
      this.bytesRemaining--
      if (this.bytesRemaining === 0) {
        this.needsToRun = false
        if (this.loopFlag) {
          this.initSample()
        } else if (this.irqEnabled) {
          this.irq = true
        }
      }
    }
  }

  setEnabled(enabled) {
    if (!enabled) {
      this.bytesRemaining = 0
      this.needsToRun = false
    } else if (this.bytesRemaining === 0) {
      this.initSample()
      this.needsInit = 2
    }
  }

  get status() {
    return this.bytesRemaining > 0
  }

  itNeedsToRun() {
    if (this.needsInit > 0) {
      this.needsInit--
      if (this.needsInit === 0) {
        this.startDMCTransfer()
      }
    }
    return this.needsToRun
  }

  irqPending(cyclesToRun) {
    if (this.irqEnabled && this.bytesRemaining > 0) {
      const cyclesToEmptyBuffer = (this.bitsRemaining + (this.bytesRemaining - 1) * 8) * this.timer.period
      if (cyclesToRun >= cyclesToEmptyBuffer) return true
    }
    return false
  }

  endFrame() {
    this.timer.endFrame()
  }

  run(cycle) {
    while (this.timer.run(cycle)) {
      if (!this.silenceFlag) {
        if ((this.shiftRegister & 0x01) > 0) {
          if (this.outputLevel <= 125) {
            this.outputLevel += 2
          }
        } else {
          if (this.outputLevel >= 2) {
            this.outputLevel -= 2
          }
        }
        this.shiftRegister >>>= 1
      }

      this.bitsRemaining--
      if (this.bitsRemaining === 0) {
        this.bitsRemaining = 8
        if (this.bufferEmpty) {
          this.silenceFlag = true
        } else {
          this.silenceFlag = false
          this.shiftRegister = this.readBuffer
          this.bufferEmpty = true
          this.startDMCTransfer()
        }
      }

      this.timer.addOutput(this.outputLevel)
    }
  }

  reset() {
    this.timer.reset()
    this.sampleAddr = 0xc000
    this.sampleLength = 1
    this.outputLevel = 0
    this.irqEnabled = false
    this.loopFlag = false
    this.currentAddr = 0
    this.bytesRemaining = 0
    this.readBuffer = 0
    this.bufferEmpty = true
    this.shiftRegister = 0
    this.bitsRemaining = 8
    this.silenceFlag = true
    this.needsToRun = false
    this.transferRequested = false
    this.timer.period = this.lookupTable[0] - 1
    this.timer.timer = this.timer.period
  }
}
