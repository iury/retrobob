import { Region } from '.'

/** @enum */
export const RunOption = {
  FRAME: 'FRAME',
  CPU_CYCLE: 'CPU_CYCLE',
  PPU_CYCLE: 'PPU_CYCLE',
}

export class Clock {
  constructor(region, cpuCycleHandler, ppuCycleHandler) {
    this.setRegion(region)
    this.cpuCycleHandler = cpuCycleHandler
    this.ppuCycleHandler = ppuCycleHandler
  }

  setRegion(region) {
    if (region === Region.NTSC) {
      this.fps = 60.0988
      this.frameCycles = 357_368
      this.cpuDivider = 12
      this.ppuDivider = 4
    } else {
      this.fps = 50.007
      this.frameCycles = 531_960
      this.cpuDivider = 16
      this.ppuDivider = 5
    }

    this.cycleCounter = 0
    this.frameCounter = 0
    this.cpuCounter = 0
    this.ppuCounter = 0
  }

  run(option) {
    let { cpuCounter, ppuCounter } = this
    const { frameCycles, cpuDivider, ppuDivider, cpuCycleHandler, ppuCycleHandler } = this

    switch (option) {
      case RunOption.FRAME: {
        for (let cycle = 0; cycle < frameCycles; cycle++) {
          if (++cpuCounter === cpuDivider) {
            cpuCounter = 0
            cpuCycleHandler()
          }
          if (++ppuCounter === ppuDivider) {
            ppuCounter = 0
            ppuCycleHandler()
          }
        }
        break
      }

      case RunOption.CPU_CYCLE: {
        for (;;) {
          if (++ppuCounter === ppuDivider) {
            ppuCounter = 0
            ppuCycleHandler()
          }
          if (++cpuCounter === cpuDivider) {
            cpuCounter = 0
            cpuCycleHandler()
            break
          }
        }
        break
      }

      case RunOption.PPU_CYCLE: {
        for (;;) {
          if (++cpuCounter === cpuDivider) {
            cpuCounter = 0
            cpuCycleHandler()
          }
          if (++ppuCounter === ppuDivider) {
            ppuCounter = 0
            ppuCycleHandler()
            break
          }
        }
        break
      }
    }

    this.cpuCounter = cpuCounter
    this.ppuCounter = ppuCounter
  }
}
