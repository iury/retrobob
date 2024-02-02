import { Mirroring, Region } from '.'

export class Cartridge {
  /**
   * @param {string} filename
   * @param {number[]} romData
   */
  constructor(filename, romData) {
    if (
      romData[0] === 'N'.charCodeAt(0) &&
      romData[1] === 'E'.charCodeAt(0) &&
      romData[2] === 'S'.charCodeAt(0) &&
      romData[3] === 0x1a
    ) {
      if ((romData[7] & 3) !== 0) throw 'Unsupported system'

      console.log('Parsing NES ROM...')
      console.log(`Filename: ${filename}`)
      console.log(`ROM size: ${romData.length}`)

      this.prgRomSize = 16 * 1024 * romData[4]
      this.chrRomSize = 8 * 1024 * romData[5]
      this.mapperId = (romData[6] >>> 4) | (romData[7] & 0xf0)
      this.trainer = (romData[6] & 4) > 0
      this.battery = (romData[6] & 2) > 0

      if ((romData[6] & 8) > 0) this.mirroring = Mirroring.FOUR_SCREEN
      else if ((romData[6] & 1) > 0) this.mirroring = Mirroring.VERTICAL
      else this.mirroring = Mirroring.HORIZONTAL

      if ((romData[7] & 0xc) === 8) {
        console.log('NES 2.0 file format.')
        this.prgRamSize = 64 << (romData[10] & 0xf || 7)
        this.chrRamSize = 64 << (romData[11] & 0xf)
        this.region = (romData[12] & 3) !== 1 ? Region.NTSC : Region.PAL
      } else {
        console.log('iNES file format.')
        if (['[pal]', '(pal)', '[e]', '(e)', '[europe]', '(europe)'].includes(filename.toLowerCase())) {
          console.log('Region set to PAL based on the file name.')
          this.region = Region.PAL
        } else this.region = Region.NTSC
        this.prgRamSize = 8 * 1024
        this.chrRamSize = 0
      }

      console.table(this)

      const prgFrom = this.trainer ? 528 : 16
      this.prgData = romData.slice(prgFrom, prgFrom + this.prgRomSize)
      this.chrData = romData.slice(romData.length - this.chrRomSize)
      this.trainerData = this.trainer ? romData.slice(16, 528) : []

      // if (this.mapperId === 0 && this.chrData.length === 0 && this.prgData.length === 16 * 1024) {
      //   console.log('No CHR ROM found. Fixing ranges...')
      //   this.chrData = romData.slice(romData.length - 8 * 1024)
      //   this.prgData = romData.slice(prgFrom, prgFrom + 8 * 1024)
      //   this.prgData = [...this.prgData, ...this.prgData]
      // }

      console.log(`Region: ${Object.keys(Region).find((d) => Region[d] === this.region)}`)
      console.log(`Mirroring: ${Object.keys(Mirroring).find((d) => Mirroring[d] === this.mirroring)}`)
      console.log('Loaded PRG ROM size: ', this.prgData.length)
      console.log('Loaded CHR ROM size: ', this.chrData.length)
      console.log('Loaded trainer size: ', this.trainerData.length)
    } else {
      throw 'Invalid file'
    }
  }
}
