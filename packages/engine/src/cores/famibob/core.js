import { Cartridge, MMU, PPU, Input, Region, Clock, RunOption } from '.'
import { CPU, CycleType } from '../../cpus/6502'
import { APU, Mixer } from './apu'
import { NROM } from './mappers/nrom'
import { CNROM } from './mappers/cnrom'
import { AxROM } from './mappers/axrom'
import { UxROM } from './mappers/uxrom'
import { MMC1 } from './mappers/mmc1'
import { MMC2 } from './mappers/mmc2'
import { MMC3 } from './mappers/mmc3'

/** @enum */
export const CoreState = {
  PLAYING: 'PLAYING',
  PAUSING: 'PAUSING',
  PAUSED: 'PAUSED',
}

export class Core {
  constructor(filename, romData, ctx) {
    console.log(`Creating famibob core...`)

    this.ctx = ctx
    this.cartridge = new Cartridge(filename, romData)
    this.region = this.cartridge.region

    this.width = 256
    this.height = 240
    this.framebuf = new ImageData(this.width, this.height)

    if (this.cartridge.mapperId === 0) {
      this.mapper = new NROM(this.cartridge)
    } else if (this.cartridge.mapperId === 1) {
      this.mapper = new MMC1(this.cartridge)
    } else if (this.cartridge.mapperId === 2) {
      this.mapper = new UxROM(this.cartridge)
    } else if (this.cartridge.mapperId === 3) {
      this.mapper = new CNROM(this.cartridge)
    } else if (this.cartridge.mapperId === 4) {
      this.mapper = new MMC3(this.cartridge)
    } else if (this.cartridge.mapperId === 7) {
      this.mapper = new AxROM(this.cartridge)
    } else if (this.cartridge.mapperId === 9) {
      this.mapper = new MMC2(this.cartridge)
    } else throw 'Unsupported mapper'

    this.ppu = new PPU(this.mapper, this.region)
    this.mixer = new Mixer(this.region)
    this.apu = new APU(this.region, this.mixer)
    this.input = new Input()

    this.mmu = new MMU(
      {
        read: this.mapper.read.bind(this.mapper),
        write: this.mapper.write.bind(this.mapper),
      },
      {
        read: this.ppu.read.bind(this.ppu),
        write: this.ppu.write.bind(this.ppu),
      },
      {
        read: this.apu.read.bind(this.apu),
        write: this.apu.write.bind(this.apu),
      },
      {
        read: this.input.read.bind(this.input),
        write: this.input.write.bind(this.input),
      },
    )

    this.cpu = new CPU(this.mmu)
    this.cpu.rstRequested = true

    this.cpuRunner = this.cpu.run()
    this.clock = new Clock(
      this.region,
      () => this.cpuRun(),
      () => this.ppuRun(),
    )

    this.fps = 0
    postMessage({ event: 'gameloaded', data: { audio: { channels: 1, length: 1600, rate: 96000 } } })
  }

  async saveState(slot) {
    const requiresPause = this.state === CoreState.PLAYING
    if (requiresPause) await this.pause()

    console.log(`Saving state at slot ${slot}...`)

    postMessage({ event: 'savestate', data: slot })
    if (requiresPause) this.play()
  }

  async loadState(slot) {
    await this.pause()

    console.log(`Loading state at slot ${slot}...`)

    postMessage({ event: 'loadstate', data: slot })
    this.play()
  }

  async setRegion(region) {
    const requiresPause = this.state === CoreState.PLAYING
    if (requiresPause) await this.pause()

    console.log(`Changing region to ${Object.keys(Region).find((d) => Region[d] === region)}...`)
    this.region = region
    this.ppu.setRegion(region)
    this.clock.setRegion(region)

    if (requiresPause) this.play()
  }

  reset() {
    console.log(`Resetting...`)
    this.cpu.rstRequested = true
    this.ppu.reset()
    this.play()
  }

  async pause() {
    if (this.state !== CoreState.PLAYING) return
    console.log(`Pausing...`)
    this.state = CoreState.PAUSING
    while (this.state !== CoreState.PAUSED) await new Promise(requestAnimationFrame)
    console.log(`Paused.`)
    postMessage({ event: 'gamepaused' })
  }

  async play() {
    if (this.state === CoreState.PLAYING) return
    this.state = CoreState.PLAYING

    console.log(`Playing...`)
    ;(async () => {
      const fpsReport = setInterval(() => {
        postMessage({ event: 'fps', data: this.fps })
        this.fps = 0
      }, 1000)

      let then = performance.now()
      const interval = 1000 / this.clock.fps

      for (;;) {
        if (this.state === CoreState.PAUSING) {
          while (this.cpu.cycle !== 1) this.clock.run(RunOption.CPU_CYCLE)
          this.state = CoreState.PAUSED
          clearInterval(fpsReport)
          break
        }

        const now = await new Promise(requestAnimationFrame)
        const passed = now - then
        if (passed < interval) continue
        const excess = passed % interval
        then = now - excess

        this.clock.run(RunOption.FRAME)

        this.apu.endFrame()
        if (this.mixer.sampleCount > 0) {
          // postMessage({ event: 'audiosample', data: this.mixer.outputBuffer })
          this.mixer.sampleCount = 0
        }
      }
    })()

    postMessage({ event: 'gameplaying' })
  }

  keydown(player, key) {
    this.input.setKeyDown(player, key)
  }

  keyup(player, key) {
    this.input.setKeyUp(player, key)
  }

  async cleanup() {
    await this.pause()
    console.log(`Cleaning up...`)
  }

  cpuRun() {
    if (this.apu.dmc.transferRequested) {
      this.apu.dmc.transferRequested = false
      this.apu.dmc.setDMCReadBuffer(this.mmu.read(this.apu.dmc.currentAddr))
    }

    this.apu.process()

    if (this.apu.frameCounter.irq) {
      this.apu.frameCounter.irq = false
      this.cpu.irqRequested = true
    }

    if (this.apu.dmc.irq) {
      this.apu.dmc.irq = false
      this.cpu.irqRequested = true
    }

    if (this.ppu.oamdma) {
      if (Array.isArray(this.ppu.oamdma)) {
        if (this.ppu.oamdma[2] === null) {
          this.ppu.oamdma[2] = this.mmu.read((this.ppu.oamdma[0] << 8) | this.ppu.oamdma[1])
        } else {
          this.ppu.write(0x2004, this.ppu.oamdma[2])
          this.ppu.oamdma[2] = null
          if (this.ppu.oamdma[1] === 0xff) this.ppu.oamdma = null
          else this.ppu.oamdma[1]++
        }
      } else {
        const { value } = this.cpuRunner.next()
        if (value === CycleType.GET) {
          this.ppu.oamdma = [this.ppu.oamdma, 0, null]
        }
      }
    } else {
      this.cpuRunner.next()
    }
  }

  ppuRun() {
    this.ppu.run(this.framebuf)

    if (this.ppu.row === this.ppu.vblankLine && this.ppu.dot === 1) {
      this.ctx.putImageData(this.framebuf, 0, 0)
      this.fps++
    }

    if (this.ppu.nmiRequested) {
      this.ppu.nmiRequested = false
      this.cpu.nmiRequested = true
    }

    if (this.mapper.irqRequested) {
      this.mapper.irqRequested = false
      this.cpu.irqRequested = true
    }
  }
}
