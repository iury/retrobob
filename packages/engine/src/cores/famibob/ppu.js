import { fixRange8 } from '../../utils'
import { Region } from '.'

const COLOR_PALETTE = [
  0x666666ff, 0x002a88ff, 0x1412a7ff, 0x3b00a4ff, 0x5c007eff, 0x6e0040ff, 0x6c0600ff, 0x561d00ff, 0x333500ff,
  0x0b4800ff, 0x005200ff, 0x004f08ff, 0x00404dff, 0x000000ff, 0x000000ff, 0x000000ff, 0xadadadff, 0x155fd9ff,
  0x4240ffff, 0x7527feff, 0xa01accff, 0xb71e7bff, 0xb53120ff, 0x994e00ff, 0x6b6d00ff, 0x388700ff, 0x0c9300ff,
  0x008f32ff, 0x007c8dff, 0x000000ff, 0x000000ff, 0x000000ff, 0xfffeffff, 0x64b0ffff, 0x9290ffff, 0xc676ffff,
  0xf36affff, 0xfe6eccff, 0xfe8170ff, 0xea9e22ff, 0xbcbe00ff, 0x88d800ff, 0x5ce430ff, 0x45e082ff, 0x48cddeff,
  0x4f4f4fff, 0x000000ff, 0x000000ff, 0xfffeffff, 0xc0dfffff, 0xd3d2ffff, 0xe8c8ffff, 0xfbc2ffff, 0xfec4eaff,
  0xfeccc5ff, 0xf7d8a5ff, 0xe4e594ff, 0xcfef96ff, 0xbdf4abff, 0xb3f3ccff, 0xb5ebf2ff, 0xb8b8b8ff, 0x000000ff,
  0x000000ff,
]

export class PPU {
  constructor(mapper, region) {
    this.mapper = mapper
    this.setRegion(region)

    // PPUCTRL ($2000)
    this.ctrl = {
      /** base nametable address (00: 0x2000; 01: 0x2400; 10: 0x2800; 11: 0x2C00) */
      nametableSelect: 0,
      /** VRAM address increment per CPU read/write of PPUDATA
       * (0: add 1, going across; 1: add 32, going down) */
      incrementMode: false,
      /** sprite pattern table address for 8x8 sprites
       * (0: 0x0000; 1: 0x1000; ignored in 8x16 mode) */
      spriteSelect: false,
      /** background pattern table address (0: 0x0000; 1: 0x1000) */
      backgroundSelect: false,
      /** large sprites (0: 8x8 pixels; 1: 8x16 pixels) */
      largeSprites: false,
      /** PPU master/slave select */
      isMaster: false,
      /** generate an NMI at the start of vblank (0: off; 1: on) */
      nmi: false,
    }

    // PPUMASK ($2001)
    this.mask = {
      /** grayscale (0: normal color, 1: grayscale) */
      grayscale: false,
      /** 1: show background in leftmost 8 pixels of screen, 0: hide */
      leftmostBackground: false,
      /** show sprites in leftmost 8 pixels of screen, 0: hide */
      leftmostSprites: false,
      /** show background */
      showBackground: false,
      /** show sprites */
      showSprites: false,
      /** emphasize red (green on PAL) */
      intensifyRed: false,
      /** emphasize green (red on PAL) */
      intensifyGreen: false,
      /** emphasize blue */
      intensifyBlue: false,
    }

    // PPUSTATUS ($2002)
    this.status = {
      /** vblank has started (0: not in vblank; 1: in vblank)
       * set at dot 1 of line 241; cleared after reading $2002
       * and at dot 1 of the prerender line. */
      vblank: false,
      /** sprite 0 hit. set when a nonzero pixel of sprite 0 overlaps a
       * nonzero background pixel; cleared at dot 1 of the prerender line. */
      sprite0Hit: false,
      /** sprite overflow. set whenever more than eight sprites appear on
       * a scanline during sprite evaluation. cleared at dot 1 of the
       * prerender line. */
      overflow: false,
    }

    // OAMADDR ($2003)
    this.oamaddr = 0

    // OAMDATA ($2004)
    this.oamdata = new Array(256)
    this.oamdata.fill(0)

    // PPUSCROLL ($2005)
    this.scroll = {
      /** during rendering, specifies the starting coarse-x scroll for the next
       * scanline and the starting y scroll for the screen.
       * otherwise holds the scroll or address before transferring it to v */
      t: 0,
      /** fine-x position of the current scroll, used during rendering alongside v */
      x: 0,
      /** toggles on each write to either PPUSCROLL or PPUADDR,
       * indicating whether this is the first or second write.
       * clears on reads of PPUSTATUS */
      w: false,
    }

    // PPUADDR ($2006)
    this.ppuaddr = 0

    // PPUDATA ($2007)
    this.ppudata = 0

    // background
    this.palette = new Array(32)
    this.palette.fill(0)
    this.bgtile = [0, 0]
    this.bgattr = [0, 0]
    this.pattern = [0, 0]
    this.bgtileaddr = 0
    this.bgnextattr = 0

    // sprite
    this.secondaryOamdata = new Array(256)
    this.secondaryOamdata.fill(0)
    this.secondaryOamaddr = 0
    this.oambuffer = 0
    this.spriteCnt = 0
    this.spriteIdx = 0
    this.sprite0Visible = false
    this.spriteTiles = new Array(8)
    this.hasSprite = new Array(256)
    this.hasSprite.fill(false)

    // sprite evaluation
    this.sprite0Added = false
    this.spriteInRange = false
    this.copyFinished = false
    this.overflowCnt = 0
    this.spriteAddrH = 0
    this.spriteAddrL = 0

    this.buffer = 0
    this.latch = 0
    this.row = 0
    this.dot = -1

    this.oddFrame = false
    this.booting = true
    this.bootingCounter = 0
  }

  setRegion(region) {
    this.region = region
    this.vblankLine = region === Region.NTSC ? 241 : 291
    this.prerenderLine = region === Region.NTSC ? 261 : 311
  }

  reset() {
    for (const k of Object.keys(this.ctrl)) this.ctrl[k] = false
    for (const k of Object.keys(this.mask)) this.mask[k] = false
    for (const k of Object.keys(this.status)) this.status[k] = false
    this.ctrl.nametableSelect = 0
    this.scroll.t = 0
    this.scroll.x = 0
    this.scroll.w = false
    this.booting = true
    this.bootingCounter = 0
  }

  read(address) {
    if (address === 0x2002) {
      // PPUSTATUS

      // hardware bug
      if (this.row === this.vblankLine && this.dot === 0) {
        this.preventVblank = true
        this.status.vblank = true
      }

      this.latch =
        (this.latch & 0x1f) |
        (this.status.vblank ? 0x80 : 0) |
        (this.status.sprite0Hit ? 0x40 : 0) |
        (this.status.overflow ? 0x20 : 0)

      this.scroll.w = false
      this.status.vblank = false
    } else if (address === 0x2004) {
      // OAMDATA
      if (this.rendering && this.row !== this.prerenderLine) {
        if (this.dot >= 257 && this.dot <= 320) {
          const step = (this.dot - 257) % 8 > 3 ? 3 : (this.dot - 257) % 8
          this.secondaryOamaddr = (((this.dot - 257) / 8) >>> 0) * 4 + step
          this.oambuffer = this.secondaryOamdata[this.secondaryOamaddr]
        }

        this.latch = this.oambuffer
      } else {
        this.latch = this.oamdata[this.oamaddr]
      }
    } else if (address === 0x2007) {
      // PPUDATA
      if ((this.ppuaddr & 0x3fff) >= 0x3f00) {
        let addr = this.ppuaddr & 0x1f
        if ([0x10, 0x14, 0x18, 0x1c].includes(addr)) addr &= ~0x10
        this.latch = this.palette[addr] | (this.latch & 0xc0)
        if (this.mask.grayscale) this.latch &= 0x30
      } else {
        this.latch = this.buffer
      }

      // put PPUDATA in the buffer for the next read
      this.buffer = this.mapper.read(this.ppuaddr & 0x3fff)
      this.incrementAddr()
    }

    return this.latch
  }

  write(address, value) {
    this.latch = value

    if (address === 0x2000) {
      // PPUCTRL
      if (this.booting) return

      const prevNmi = this.ctrl.nmi

      this.ctrl.backgroundSelect = value & 0b11
      this.ctrl.incrementMode = (value & 0x4) > 0
      this.ctrl.spriteSelect = (value & 0x8) > 0
      this.ctrl.backgroundSelect = (value & 0x10) > 0
      this.ctrl.largeSprites = (value & 0x20) > 0
      this.ctrl.isMaster = (value & 0x40) > 0
      this.ctrl.nmi = (value & 0x80) > 0

      if (this.status.vblank && !prevNmi && this.ctrl.nmi) {
        this.nmiRequested = true
      }

      // t: ...GH.. ........ <- d: ......GH
      this.scroll.t = (this.scroll.t & ~0xc00) | ((value & 0b11) << 10)
    } else if (address === 0x2001) {
      // PPUMASK
      if (this.booting) return

      this.mask.grayscale = (value & 0x1) > 0
      this.mask.leftmostBackground = (value & 0x2) > 0
      this.mask.leftmostSprites = (value & 0x4) > 0
      this.mask.showBackground = (value & 0x8) > 0
      this.mask.showSprites = (value & 0x10) > 0
      this.mask.intensifyRed = (value & 0x20) > 0
      this.mask.intensifyGreen = (value & 0x40) > 0
      this.mask.intensifyBlue = (value & 0x80) > 0

      if (this.region === Region.PAL) {
        // it is swapped in PAL
        const v = this.mask.intensifyRed
        this.mask.intensifyRed = this.mask.intensifyGreen
        this.mask.intensifyGreen = v
      }
    } else if (address === 0x2003) {
      // OAMADDR
      this.oamaddr = value
    } else if (address === 0x2004) {
      // OAMDATA
      if (this.rendering) {
        // glitch behavior when it is rendering
        this.oamaddr = (this.oamaddr + 4) & 0xff
      } else {
        let v = value
        // OAM byte 2: bits 2, 3 and 4 are unimplemented
        if ((this.oamaddr & 0b11) === 0b10) v &= 0xe3
        this.oamdata[this.oamaddr] = v
        this.oamaddr = (this.oamaddr + 1) & 0xff
      }
    } else if (address === 0x2005) {
      // PPUSCROLL
      if (this.booting) return

      if (!this.scroll.w) {
        // t: ....... ...ABCDE <- d: ABCDE...
        // x:              FGH <- d: .....FGH
        // w:                  <- 1
        this.scroll.t = (this.scroll.t & ~0x1f) | (value >>> 3)
        this.scroll.x = value & 0x7
        this.scroll.w = true
      } else {
        // t: FGH..AB CDE..... <- d: ABCDEFGH
        // w:                  <- 0
        this.scroll.t = (this.scroll.t & ~0x73e0) | ((value & 0xf8) << 2) | ((value & 7) << 12)
        this.scroll.w = false
      }
    } else if (address === 0x2006) {
      // PPUADDR
      if (this.booting) return

      if (!this.scroll.w) {
        // t: 0CDEFGH ........ <- d: ..CDEFGH (bit 14 is cleared)
        // w:                  <- 1
        this.scroll.t = (this.scroll.t & ~0xff00) | ((value & 0x3f) << 8)
        this.scroll.w = true
      } else {
        // t: ....... ABCDEFGH <- d: ABCDEFGH
        // v: <...all bits...> <- t: <...all bits...>
        // w:                  <- 0
        this.scroll.t = (this.scroll.t & ~0xff) | value
        this.ppuaddr = this.scroll.t
        this.scroll.w = false
      }
    } else if (address === 0x2007) {
      // PPUDATA
      if ((this.ppuaddr & 0x3fff) >= 0x3f00) {
        // palette starts at 0x3F00 and it is mirrored every 0x20 bytes
        // addresses 3F10/3F14/3F18/3F1C are mirrors of 3F00/3F04/3F08/3F0C
        const addr = this.ppuaddr & 0x1f
        const v = value & 0x3f
        if (addr === 0x00 || addr === 0x10) {
          this.palette[0x00] = v
          this.palette[0x10] = v
        } else if (addr === 0x04 || addr === 0x14) {
          this.palette[0x04] = v
          this.palette[0x14] = v
        } else if (addr === 0x08 || addr === 0x18) {
          this.palette[0x08] = v
          this.palette[0x18] = v
        } else if (addr === 0x0c || addr === 0x1c) {
          this.palette[0x0c] = v
          this.palette[0x1c] = v
        } else {
          this.palette[addr] = v
        }
      } else {
        if (this.rendering) {
          // glitch behavior when it is rendering
          this.mapper.write(this.ppuaddr & 0x3fff, this.ppuaddr & 0xff)
        } else {
          this.mapper.write(this.ppuaddr & 0x3fff, value)
        }
      }

      this.incrementAddr()
    } else if (address === 0x4014) {
      // OAMDMA
      this.oamdma = value
    }
  }

  incrementAddr() {
    if (!this.rendering) {
      // PPUCTRL.incrementMode says how much the address will increment, by 1 or 32
      this.ppuaddr = (this.ppuaddr + (this.ctrl.incrementMode ? 0x20 : 0x01)) & 0x7fff
    } else {
      // odd behavior when it is rendering
      this.incrementX()
      this.incrementY()
    }
  }

  incrementX() {
    if ((this.ppuaddr & 0x1f) === 0x1f) {
      // switch horizontal nametable
      this.ppuaddr = (this.ppuaddr & ~0x1f) ^ 0x0400
    } else {
      this.ppuaddr++
    }
  }

  incrementY() {
    if ((this.ppuaddr & 0x7000) !== 0x7000) {
      this.ppuaddr += 0x1000
    } else {
      this.ppuaddr &= ~0x7000
      let y = (this.ppuaddr & 0x03e0) >>> 5
      if (y === 29) {
        y = 0
        // switch vertical nametable
        this.ppuaddr ^= 0x0800
      } else if (y === 31) {
        y = 0
      } else {
        y++
      }
      this.ppuaddr = (this.ppuaddr & ~0x03e0) | (y << 5)
    }
  }

  loadTile() {
    if (this.rendering) {
      if (this.dot % 8 === 1) {
        const nmaddr = 0x2000 | (this.ppuaddr & 0x0fff)
        const idx = this.mapper.read(nmaddr)
        this.bgtileaddr = (idx << 4) | (this.ppuaddr >>> 12) | (this.ctrl.backgroundSelect ? 0x1000 : 0)
        this.pattern[0] |= this.bgtile[0]
        this.pattern[1] |= this.bgtile[1]
        this.bgattr[0] = this.bgattr[1]
        this.bgattr[1] = this.bgnextattr
      }

      if (this.dot % 8 === 3) {
        const attraddr =
          0x23c0 | (this.ppuaddr & 0x0c00) | ((this.ppuaddr >>> 4) & 0x38) | ((this.ppuaddr >>> 2) & 0x07)
        const shift = (((this.ppuaddr >>> 4) & 0x04) | (this.ppuaddr & 0x02)) & 0x7
        this.bgnextattr = ((this.mapper.read(attraddr) >>> shift) & 0x3) << 2
      }

      if (this.dot % 8 === 5) {
        this.bgtile[0] = this.mapper.read(this.bgtileaddr)
        this.mapper.checkA12?.(this.bgtileaddr)
      }

      if (this.dot % 8 === 7) {
        this.bgtile[1] = this.mapper.read(this.bgtileaddr + 8)
        this.mapper.checkA12?.(this.bgtileaddr + 8)
      }
    }
  }

  loadSprite(tile, attr, x, y) {
    if (this.spriteIdx < this.spriteCnt && y < 240) {
      let offset
      const largeSprites = this.ctrl.largeSprites ? 15 : 7
      const row = this.row !== this.prerenderLine ? this.row : -1
      if ((attr & 0x80) === 0x80) {
        offset = fixRange8(largeSprites - fixRange8(row - y))
      } else {
        offset = fixRange8(row - y)
      }

      const tileaddr = this.ctrl.largeSprites
        ? ((tile & 1 ? 0x1000 : 0) | ((tile & ~1) << 4)) + (offset >= 8 ? offset + 8 : offset)
        : ((tile << 4) | (this.ctrl.spriteSelect ? 0x1000 : 0)) + offset

      const low = this.mapper.read(tileaddr)
      this.mapper.checkA12?.(tileaddr)
      const high = this.mapper.read(tileaddr + 8)
      this.mapper.checkA12?.(tileaddr + 8)

      this.spriteTiles[this.spriteIdx] = {
        x,
        pattern: [low, high],
        paletteOffset: ((attr & 0x03) << 2) | 0x10,
        bgPriority: (attr & 0x20) === 0x20,
        flipH: (attr & 0x40) === 0x40,
      }

      if (this.row >= 0) {
        for (let i = 0; i < 8; i++) {
          if (x + i + 1 < 257) this.hasSprite[x + i] = true
        }
      }
    } else {
      const tileaddr = this.ctrl.largeSprites ? 0x1fe0 : this.ctrl.spriteSelect ? 0x1ff0 : 0x0ff0
      this.mapper.read(tileaddr)
      this.mapper.checkA12?.(tileaddr)
      this.mapper.read(tileaddr + 8)
      this.mapper.checkA12?.(tileaddr + 8)
    }

    this.spriteIdx = fixRange8(this.spriteIdx + 1)
  }

  spriteEvaluation() {
    if (this.rendering) {
      if (this.dot < 65) {
        this.oambuffer = 0xff
        this.secondaryOamdata[(this.dot - 1) >>> 1] = 0xff
      } else {
        if (this.dot === 65) {
          this.sprite0Added = false
          this.spriteInRange = false
          this.secondaryOamaddr = 0
          this.overflowCnt = 0
          this.copyFinished = false
          this.spriteAddrH = (this.oamaddr >>> 2) & 0x3f
          this.spriteAddrL = this.oamaddr & 0x03
        } else if (this.dot === 256) {
          this.sprite0Visible = this.sprite0Added
          this.spriteCnt = this.secondaryOamaddr >>> 2
        }

        if (this.dot & 1) {
          this.oambuffer = this.oamdata[this.oamaddr]
        } else {
          if (this.copyFinished) {
            this.spriteAddrH = (this.spriteAddrH + 1) & 0x3f
            if (this.secondaryOamaddr >= 0x20) {
              this.oambuffer = this.secondaryOamdata[this.secondaryOamaddr & 0x1f]
            }
          } else {
            if (
              !this.spriteInRange &&
              this.row >= this.oambuffer &&
              this.row < this.oambuffer + (this.ctrl.largeSprites ? 16 : 8)
            ) {
              this.spriteInRange = true
            }

            if (this.secondaryOamaddr < 0x20) {
              this.secondaryOamdata[this.secondaryOamaddr] = this.oambuffer

              if (this.spriteInRange) {
                this.spriteAddrL++
                this.secondaryOamaddr++
                if (this.spriteAddrH === 0) this.sprite0Added = true

                if ((this.secondaryOamaddr & 0x03) === 0) {
                  this.spriteInRange = false
                  this.spriteAddrL = 0
                  this.spriteAddrH = (this.spriteAddrH + 1) & 0x3f
                  if (this.spriteAddrH === 0) this.copyFinished = true
                }
              } else {
                this.spriteAddrH = (this.spriteAddrH + 1) & 0x3f
                if (this.spriteAddrH === 0) this.copyFinished = true
              }
            } else {
              this.oambuffer = this.secondaryOamdata[this.secondaryOamaddr & 0x1f]

              if (this.spriteInRange) {
                this.status.overflow = true
                this.spriteAddrL++

                if (this.spriteAddrL === 4) {
                  this.spriteAddrH = (this.spriteAddrH + 1) & 0x3f
                  this.spriteAddrL = 0
                }

                if (this.overflowCnt === 0) {
                  this.overflowCnt = 3
                } else if (--this.overflowCnt === 0) {
                  this.copyFinished = true
                  this.spriteAddrL = 0
                }
              } else {
                this.spriteAddrH = (this.spriteAddrH + 1) & 0x3f
                this.spriteAddrL = (this.spriteAddrL + 1) & 0x03
                if (this.spriteAddrH === 0) this.copyFinished = true
              }
            }
          }

          this.oamaddr = (this.spriteAddrL & 0x03) | (this.spriteAddrH << 2)
        }
      }
    }
  }

  render(x, y, framebuf) {
    if (!this.rendering) {
      if ((this.ppuaddr & 0x3fff) >= 0x3f00) {
        framebuf.data[y * 1024 + x * 4] = (COLOR_PALETTE[this.palette[this.ppuaddr & 0x1f]] & 0xff000000) >>> 24
        framebuf.data[y * 1024 + x * 4 + 1] = (COLOR_PALETTE[this.palette[this.ppuaddr & 0x1f]] & 0xff0000) >>> 16
        framebuf.data[y * 1024 + x * 4 + 2] = (COLOR_PALETTE[this.palette[this.ppuaddr & 0x1f]] & 0xff00) >>> 8
        framebuf.data[y * 1024 + x * 4 + 3] = 0xff
      } else {
        // color at position 0 is the universal background color
        framebuf.data[y * 1024 + x * 4] = (COLOR_PALETTE[this.palette[0]] & 0xff0000) >>> 24
        framebuf.data[y * 1024 + x * 4 + 1] = (COLOR_PALETTE[this.palette[0]] & 0xff0000) >>> 16
        framebuf.data[y * 1024 + x * 4 + 2] = (COLOR_PALETTE[this.palette[0]] & 0xff00) >>> 8
        framebuf.data[y * 1024 + x * 4 + 3] = 0xff
      }
      return
    }

    const bgVisible = this.mask.showBackground && (x >= 8 || this.mask.leftmostBackground)
    const spriteVisible = this.mask.showSprites && (x >= 8 || this.mask.leftmostSprites)
    let color = 0

    if (bgVisible) {
      const offset = this.scroll.x
      const colorIdx = (((this.pattern[0] << offset) & 0x8000) >>> 15) | (((this.pattern[1] << offset) & 0x8000) >>> 14)
      let bgColorIdx = (offset + (x % 8) < 8 ? this.bgattr[0] : this.bgattr[1]) + colorIdx
      if ((bgColorIdx & 0x3) === 0) bgColorIdx = 0
      color = bgColorIdx
    }

    if (spriteVisible && this.hasSprite[x]) {
      for (let i = 0; i < this.spriteCnt; i++) {
        const sprite = this.spriteTiles[i]
        const shift = this.dot - sprite.x - 1
        if (shift >= 0 && shift < 8) {
          const spriteColorIdx = sprite.flipH
            ? ((sprite.pattern[0] >>> shift) & 0x01) | (((sprite.pattern[1] >>> shift) & 0x01) << 1)
            : (((sprite.pattern[0] << shift) & 0x80) >>> 7) | (((sprite.pattern[1] << shift) & 0x80) >>> 6)

          if (spriteColorIdx !== 0) {
            if (i === 0 && color !== 0 && this.sprite0Visible && !this.status.sprite0Hit && x !== 255) {
              this.status.sprite0Hit = true
            }

            if (!sprite.bgPriority || color === 0) {
              color = sprite.paletteOffset + spriteColorIdx
              if ((color & 0x3) === 0) color = 0
            }

            break
          }
        }
      }
    }

    color = this.palette[color & 0x1f]
    if (this.mask.grayscale) color &= 0x30
    var rgbColor = COLOR_PALETTE[color]

    if ((this.mask.intensifyRed || this.mask.intensifyGreen || this.mask.intensifyBlue) && (color & 0xf) <= 0xd) {
      let red = 1.0
      let green = 1.0
      let blue = 1.0

      if (this.mask.intensifyRed) {
        green *= 0.84
        blue *= 0.84
      }

      if (this.mask.intensifyGreen) {
        red *= 0.84
        blue *= 0.84
      }

      if (this.mask.intensifyBlue) {
        red *= 0.84
        green *= 0.84
      }

      red = Math.min(0xff, Math.trunc(((rgbColor & 0xff000000) >>> 24) * red))
      green = Math.min(0xff, Math.trunc(((rgbColor & 0xff0000) >>> 16) * green))
      blue = Math.min(0xff, Math.trunc(((rgbColor & 0xff00) >>> 8) * blue))

      rgbColor = 0x0000ff | (red << 24) | (green << 16) | (blue << 8)
    }

    framebuf.data[y * 1024 + x * 4] = (rgbColor & 0xff000000) >>> 24
    framebuf.data[y * 1024 + x * 4 + 1] = (rgbColor & 0xff0000) >>> 16
    framebuf.data[y * 1024 + x * 4 + 2] = (rgbColor & 0xff00) >>> 8
    framebuf.data[y * 1024 + x * 4 + 3] = 0xff
  }

  process(framebuf) {
    this.rendering = this.mask.showBackground || this.mask.showSprites

    if (this.dot <= 256) {
      this.loadTile()

      if (this.rendering && (this.dot & 0x07) === 0) {
        this.incrementX()
        if (this.dot === 256) this.incrementY()
      }

      if (this.row !== this.prerenderLine) {
        this.render(this.dot - 1, this.row, framebuf)
        this.pattern[0] <<= 1
        this.pattern[1] <<= 1
        this.spriteEvaluation()
      } else if (this.dot < 9) {
        if (this.dot === 1) {
          this.status.vblank = false
          this.status.sprite0Hit = false
          this.status.overflow = false
        }

        if (this.rendering && this.oamaddr >= 0x08) {
          this.oamdata[this.dot - 1] = this.oamdata[(this.oamaddr & 0xf8) + this.dot - 1]
        }
      }
    } else if (this.dot >= 257 && this.dot <= 320) {
      if (this.dot === 257) {
        this.spriteIdx = 0
        this.hasSprite.fill(false)
        if (this.rendering) {
          // v: ....A.. ...BCDEF <- t: ....A.. ...BCDEF
          this.ppuaddr = (this.ppuaddr & ~0x41f) | (this.scroll.t & 0x41f)
        }
      }

      if (this.rendering) {
        this.oamaddr = 0

        switch ((this.dot - 257) % 8) {
          case 0: {
            // garbage NT fetch
            const addr = 0x2000 | (this.ppuaddr & 0x0fff)
            this.mapper.read(addr)
            break
          }
          case 2: {
            // garbage NT fetch
            const addr =
              0x23c0 | (this.ppuaddr & 0x0c00) | ((this.ppuaddr >>> 4) & 0x38) | ((this.ppuaddr >>> 2) & 0x07)
            this.mapper.read(addr)
            break
          }
          case 4: {
            const spriteaddr = this.spriteIdx * 4
            this.loadSprite(
              this.secondaryOamdata[spriteaddr + 1],
              this.secondaryOamdata[spriteaddr + 2],
              this.secondaryOamdata[spriteaddr + 3],
              this.secondaryOamdata[spriteaddr],
            )
            break
          }
        }

        if (this.row === this.prerenderLine && this.dot >= 280 && this.dot <= 304) {
          // v: GHIA.BC DEF..... <- t: GHIA.BC DEF.....
          this.ppuaddr = (this.ppuaddr & ~0x7be0) | (this.scroll.t & 0x7be0)
        }
      }
    } else if (this.dot >= 321 && this.dot <= 336) {
      this.loadTile()

      if (this.rendering) {
        if (this.dot === 321) {
          this.oambuffer = this.secondaryOamdata[0]
        } else if (this.dot === 328 || this.dot === 336) {
          this.pattern[0] <<= 8
          this.pattern[1] <<= 8
          this.incrementX()
        }
      }
    } else if (this.dot === 337 || this.dot === 339) {
      if (this.rendering) {
        this.bgtileaddr = this.mapper.read(0x2000 | (this.ppuaddr & 0x0fff))
      }
    }
  }

  run(framebuf) {
    if (
      this.region === Region.NTSC &&
      this.rendering &&
      this.oddFrame &&
      this.dot === 339 &&
      this.row === this.prerenderLine
    ) {
      this.dot = 0
      this.row = 0
      this.oddFrame = !this.oddFrame
    } else if (this.dot++ === 340) {
      this.dot = 0
      if (this.row++ === this.prerenderLine) {
        this.row = 0
        this.oddFrame = !this.oddFrame
      }
    }

    if (!this.booting) {
      if (this.row === this.vblankLine) {
        if (this.dot === 1) {
          if (this.preventVblank) {
            this.preventVblank = false
          } else {
            this.status.vblank = true
            if (this.ctrl.nmi) {
              this.nmiRequested = true
            }
          }
        }
      }

      if (this.dot === 0 && this.row === 0) this.spriteCnt = 0

      if (this.dot !== 0 && (this.row < 240 || this.row === this.prerenderLine)) {
        this.process(framebuf)
      } else {
        this.rendering = false
      }
    }

    if (this.booting) {
      // hardware warm up cycles
      if (this.bootingCounter++ === (this.region === Region.NTSC ? 88974 : 106022)) {
        this.booting = false
        this.bootingCounter = 0
        console.log('PPU booting completed.')
      }
    }
  }
}
