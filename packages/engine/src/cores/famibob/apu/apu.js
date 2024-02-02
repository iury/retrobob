import { Region } from '..'
import {
  Mixer,
  FrameCounter,
  Square,
  Triangle,
  Noise,
  DMC,
  SQUARE_CHANNEL,
  FRAME_TYPE,
  DMC_LOOKUP_TABLE_NTSC,
  DMC_LOOKUP_TABLE_PAL,
  NOISE_LOOKUP_TABLE_NTSC,
  NOISE_LOOKUP_TABLE_PAL,
  STEP_CYCLES_NTSC,
  STEP_CYCLES_PAL,
} from '.'

export class APU {
  constructor(region, mixer) {
    this.enabled = true
    this.region = region
    this.mixer = mixer
    this.currentCycle = 0
    this.previousCycle = 0
    this.needsToRun = false
    this.frameCounter = new FrameCounter(this)
    this.square1 = new Square(mixer, SQUARE_CHANNEL.ONE)
    this.square2 = new Square(mixer, SQUARE_CHANNEL.TWO)
    this.triangle = new Triangle(mixer)
    this.noise = new Noise(mixer)
    this.dmc = new DMC(mixer)
  }

  read(address) {
    this.run()

    const v =
      0 |
      (this.square1.status ? 0x01 : 0) |
      (this.square2.status ? 0x02 : 0) |
      (this.triangle.status ? 0x04 : 0) |
      (this.noise.status ? 0x08 : 0) |
      (this.dmc.status ? 0x10 : 0) |
      (this.frameCounter.irq ? 0x40 : 0) |
      (this.dmc.irq ? 0x80 : 0)

    this.frameCounter.irq = false
    return v
  }

  write(address, value) {
    this.run()
    switch (address) {
      case 0x4000: {
        this.square1.envelope.initEnvelope(value)
        this.needsToRun = true
        this.square1.duty = (value & 0xc0) >>> 6
        if (!this.square1.isMMC5Square) this.square1.updateOutput()
        break
      }
      case 0x4001: {
        this.square1.initSweep(value)
        if (!this.square1.isMMC5Square) this.square1.updateOutput()
        break
      }
      case 0x4002: {
        this.square1.setPeriod((this.square1.realPeriod & 0x0700) | value)
        if (!this.square1.isMMC5Square) this.square1.updateOutput()
        break
      }
      case 0x4003: {
        this.square1.envelope.lengthCounter.loadLengthCounter(value >>> 3)
        this.needsToRun = true
        this.square1.setPeriod((this.square1.realPeriod & 0xff) | ((value & 0x07) << 8))
        this.square1.dutyPos = 0
        this.square1.envelope.resetEnvelope()
        if (!this.square1.isMMC5Square) this.square1.updateOutput()
        break
      }
      case 0x4004: {
        this.square2.envelope.initEnvelope(value)
        this.needsToRun = true
        this.square2.duty = (value & 0xc0) >>> 6
        if (!this.square2.isMMC5Square) this.square2.updateOutput()
        break
      }
      case 0x4005: {
        this.square2.initSweep(value)
        if (!this.square2.isMMC5Square) this.square2.updateOutput()
        break
      }
      case 0x4006: {
        this.square2.setPeriod((this.square2.realPeriod & 0x0700) | value)
        if (!this.square2.isMMC5Square) this.square2.updateOutput()
        break
      }
      case 0x4007: {
        this.square2.envelope.lengthCounter.loadLengthCounter(value >>> 3)
        this.needsToRun = true
        this.square2.setPeriod((this.square2.realPeriod & 0xff) | ((value & 0x07) << 8))
        this.square2.dutyPos = 0
        this.square2.envelope.resetEnvelope()
        if (!this.square2.isMMC5Square) this.square2.updateOutput()
        break
      }
      case 0x4008: {
        this.triangle.linearControlFlag = (value & 0x80) === 0x80
        this.triangle.linearCounterReload = value & 0x7f
        this.triangle.lengthCounter.initLengthCounter(this.triangle.linearControlFlag)
        this.needsToRun = true
        break
      }
      case 0x400a: {
        this.triangle.timer.period = (this.triangle.timer.period & ~0x00ff) | value
        break
      }
      case 0x400b: {
        this.triangle.lengthCounter.loadLengthCounter(value >>> 3)
        this.needsToRun = true
        this.triangle.timer.period = (this.triangle.timer.period & ~0xff00) | ((value & 0x07) << 8)
        this.triangle.linearReloadFlag = true
        break
      }
      case 0x400c: {
        this.noise.envelope.initEnvelope(value)
        this.needsToRun = true
        break
      }
      case 0x400e: {
        this.noise.timer.period = this.noise.lookupTable[value & 0x0f] - 1
        this.noise.modeFlag = (value & 0x80) === 0x80
        break
      }
      case 0x400f: {
        this.noise.envelope.lengthCounter.loadLengthCounter(value >>> 3)
        this.needsToRun = true
        this.noise.envelope.resetEnvelope()
        break
      }
      case 0x4010: {
        this.dmc.irqEnabled = (value & 0x80) === 0x80
        this.dmc.loopFlag = (value & 0x40) === 0x40
        this.dmc.timer.period = this.dmc.lookupTable[value & 0x0f] - 1
        if (!this.dmc.irqEnabled) this.dmc.irq = false
        break
      }
      case 0x4011: {
        this.dmc.outputLevel = value & 0x7f
        this.dmc.timer.addOutput(this.dmc.outputLevel)
        break
      }
      case 0x4012: {
        this.dmc.sampleAddr = 0xc000 | (value << 6)
        break
      }
      case 0x4013: {
        this.dmc.sampleLength = (value << 4) | 0x0001
        break
      }
      case 0x4015: {
        this.dmc.irq = false
        this.square1.setEnabled((value & 0x01) > 0)
        this.square2.setEnabled((value & 0x02) > 0)
        this.triangle.setEnabled((value & 0x04) > 0)
        this.noise.setEnabled((value & 0x08) > 0)
        this.dmc.setEnabled((value & 0x10) > 0)
        break
      }
      case 0x4017: {
        this.frameCounter.newValue = value
        this.frameCounter.writeDelayCounter = 3
        this.frameCounter.inhibitIrq = (value & 0x40) === 0x40
        if (this.frameCounter.inhibitIrq) {
          this.frameCounter.irq = false
        }
        break
      }
    }
  }

  process() {
    if (this.enabled) {
      this.currentCycle++
      if (this.currentCycle === this.mixer.cycleLength - 1) {
        this.endFrame()
      } else if (this.itNeedsToRun(this.currentCycle)) {
        this.run()
      }
    }
  }

  setRegion(region) {
    this.region = region
    this.mixer.setRegion(region)
    this.dmc.lookupTable = region === Region.NTSC ? DMC_LOOKUP_TABLE_NTSC : DMC_LOOKUP_TABLE_PAL
    this.noise.lookupTable = region === Region.NTSC ? NOISE_LOOKUP_TABLE_NTSC : NOISE_LOOKUP_TABLE_PAL
    this.run()
    this.frameCounter.stepCycles = region === Region.NTSC ? STEP_CYCLES_NTSC : STEP_CYCLES_PAL
  }

  endFrame() {
    this.run()
    this.square1.endFrame()
    this.square2.endFrame()
    this.triangle.endFrame()
    this.noise.endFrame()
    this.dmc.endFrame()
    this.mixer.playAudioBuffer(this.currentCycle)
    this.currentCycle = 0
    this.previousCycle = 0
  }

  itNeedsToRun(cycle) {
    if (this.dmc.itNeedsToRun() || this.needsToRun) {
      this.needsToRun = false
      return true
    } else {
      const cycleToRun = cycle - this.previousCycle
      return this.frameCounter.itNeedsToRun(cycleToRun) || this.dmc.irqPending(cycleToRun)
    }
  }

  run() {
    let cyclesToRun = this.currentCycle - this.previousCycle
    while (cyclesToRun > 0) {
      const ref = { cyclesToRun }
      this.previousCycle += this.frameCounter.run(ref)
      cyclesToRun = ref.cyclesToRun

      this.square1.reloadLengthCounter()
      this.square2.reloadLengthCounter()
      this.noise.reloadLengthCounter()
      this.triangle.reloadLengthCounter()
      this.square1.run(this.previousCycle)
      this.square2.run(this.previousCycle)
      this.noise.run(this.previousCycle)
      this.triangle.run(this.previousCycle)
      this.dmc.run(this.previousCycle)
    }
  }

  frameCounterTick(frameType) {
    this.square1.tickEnvelope()
    this.square2.tickEnvelope()
    this.triangle.tickLinearCounter()
    this.noise.tickEnvelope()
    if (frameType === FRAME_TYPE.HALF_FRAME) {
      this.square1.tickLengthCounter()
      this.square2.tickLengthCounter()
      this.triangle.tickLengthCounter()
      this.noise.tickLengthCounter()
      this.square1.tickSweep()
      this.square2.tickSweep()
    }
  }

  reset() {
    this.enabled = true
    this.currentCycle = 0
    this.previousCycle = 0
    this.needsToRun = false
    this.square1.reset()
    this.square2.reset()
    this.triangle.reset()
    this.noise.reset()
    this.dmc.reset()
    this.frameCounter.reset()
    this.mixer.reset()
  }
}
