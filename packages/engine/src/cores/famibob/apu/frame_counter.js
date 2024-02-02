import { STEP_CYCLES_NTSC } from '.'

/** @enum */
export const FRAME_TYPE = {
  NONE: 'NONE',
  QUARTER_FRAME: 'QUARTER_FRAME',
  HALF_FRAME: 'HALF_FRAM',
}

const FRAMES = [
  [
    FRAME_TYPE.QUARTER_FRAME,
    FRAME_TYPE.HALF_FRAME,
    FRAME_TYPE.QUARTER_FRAME,
    FRAME_TYPE.NONE,
    FRAME_TYPE.HALF_FRAME,
    FRAME_TYPE.NONE,
  ],
  [
    FRAME_TYPE.QUARTER_FRAME,
    FRAME_TYPE.HALF_FRAME,
    FRAME_TYPE.QUARTER_FRAME,
    FRAME_TYPE.NONE,
    FRAME_TYPE.HALF_FRAME,
    FRAME_TYPE.NONE,
  ],
]

export class FrameCounter {
  constructor(apu) {
    this.apu = apu
    this.irq = false
    this.stepCycles = STEP_CYCLES_NTSC
    this.previousCycle = 0
    this.currentStep = 0
    this.stepMode = 0
    this.inhibitIrq = false
    this.blockTick = 0
    this.newValue = 0
    this.writeDelayCounter = 0
  }

  itNeedsToRun(cycles) {
    return (
      this.newValue >= 0 ||
      this.blockTick > 0 ||
      this.previousCycle + cycles >= this.stepCycles[this.stepMode][this.currentStep] - 1
    )
  }

  run(ref) {
    let cyclesRan = 0

    if (this.previousCycle + ref.cyclesToRun >= this.stepCycles[this.stepMode][this.currentStep]) {
      if (!this.inhibitIrq && this.stepMode === 0 && this.currentStep >= 3) {
        this.irq = true
      }

      const frame = FRAMES[this.stepMode][this.currentStep]
      if (frame != FRAME_TYPE.NONE && this.blockTick === 0) {
        this.apu.frameCounterTick(frame)
        this.blockTick = 2
      }

      if (this.stepCycles[this.stepMode][this.currentStep] < this.previousCycle) {
        cyclesRan = 0
      } else {
        cyclesRan = this.stepCycles[this.stepMode][this.currentStep] - this.previousCycle
      }

      ref.cyclesToRun -= cyclesRan

      this.currentStep++
      if (this.currentStep === 6) {
        this.currentStep = 0
        this.previousCycle = 0
      } else {
        this.previousCycle += cyclesRan
      }
    } else {
      cyclesRan = ref.cyclesToRun
      ref.cyclesToRun = 0
      this.previousCycle += cyclesRan
    }

    if (this.newValue >= 0) {
      this.writeDelayCounter--
      if (this.writeDelayCounter === 0) {
        this.stepMode = (this.newValue & 0x80) === 0x80 ? 1 : 0

        this.writeDelayCounter = -1
        this.currentStep = 0
        this.previousCycle = 0
        this.newValue = -1

        if (this.stepMode === 1 && this.blockTick === 0) {
          this.apu.frameCounterTick(FRAME_TYPE.HALF_FRAME)
          this.blockTick = 2
        }
      }
    }

    if (this.blockTick > 0) {
      this.blockTick--
    }

    return cyclesRan
  }

  reset() {
    this.irq = false
    this.previousCycle = 0
    this.stepMode = 0
    this.currentStep = 0
    this.newValue = this.stepMode === 1 ? 0x80 : 0
    this.writeDelayCounter = 3
    this.inhibitIrq = false
    this.blockTick = 0
  }
}
