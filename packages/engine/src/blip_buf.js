const blStep = [
  [43, -115, 350, -488, 1136, -914, 5861, 21022],
  [44, -118, 348, -473, 1076, -799, 5274, 21001],
  [45, -121, 344, -454, 1011, -677, 4706, 20936],
  [46, -122, 336, -431, 942, -549, 4156, 20829],
  [47, -123, 327, -404, 868, -418, 3629, 20679],
  [47, -122, 316, -375, 792, -285, 3124, 20488],
  [47, -120, 303, -344, 714, -151, 2644, 20256],
  [46, -117, 289, -310, 634, -17, 2188, 19985],
  [46, -114, 273, -275, 553, 117, 1758, 19675],
  [44, -108, 255, -237, 471, 247, 1356, 19327],
  [43, -103, 237, -199, 390, 373, 981, 18944],
  [42, -98, 218, -160, 310, 495, 633, 18527],
  [40, -91, 198, -121, 231, 611, 314, 18078],
  [38, -84, 178, -81, 153, 722, 22, 17599],
  [36, -76, 157, -43, 80, 824, -241, 17092],
  [34, -68, 135, -3, 8, 919, -476, 16558],
  [32, -61, 115, 34, -60, 1006, -683, 16001],
  [29, -52, 94, 70, -123, 1083, -862, 15422],
  [27, -44, 73, 106, -184, 1152, -1015, 14824],
  [25, -36, 53, 139, -239, 1211, -1142, 14210],
  [22, -27, 34, 170, -290, 1261, -1244, 13582],
  [20, -20, 16, 199, -335, 1301, -1322, 12942],
  [18, -12, -3, 226, -375, 1331, -1376, 12293],
  [15, -4, -19, 250, -410, 1351, -1408, 11638],
  [13, 3, -35, 272, -439, 1361, -1419, 10979],
  [11, 9, -49, 292, -464, 1362, -1410, 10319],
  [9, 16, -63, 309, -483, 1354, -1383, 9660],
  [7, 22, -75, 322, -496, 1337, -1339, 9005],
  [6, 26, -85, 333, -504, 1312, -1280, 8355],
  [4, 31, -94, 341, -507, 1278, -1205, 7713],
  [3, 35, -102, 347, -506, 1238, -1119, 7082],
  [1, 40, -110, 350, -499, 1190, -1021, 6464],
  [0, 43, -115, 350, -488, 1136, -914, 5861],
]

const blipMaxRatio = 1 << 20
const timeBits = 52
const timeUnit = 1 << timeBits
const bassShift = 9
const endFrameExtra = 2
const halfWidth = 8
const bufExtra = halfWidth * 2 + endFrameExtra
const phaseBits = 5
const phaseCount = 1 << phaseBits
const deltaBits = 15
const deltaUnit = 1 << deltaBits
const fracBits = timeBits - 32
const maxSample = +32767
const minSample = -32768

const clamp = (num) => Math.min(Math.max(num, minSample), maxSample)

export class BlipBuf {
  constructor(size) {
    if (typeof size !== 'number') throw 'size must be a number'
    if (size < 0) throw 'size must be greater than 0'
    this.size = size
    this.data = new Array(size + bufExtra)
    this.factor = (timeUnit / blipMaxRatio) >> 0
    this.clear()
  }

  setRates(clockRate, sampleRate) {
    if (typeof clockRate !== 'number') throw 'clockRate must be a number'
    if (typeof sampleRate !== 'number') throw 'sampleRate must be a number'
    const factor = (timeUnit * sampleRate) / clockRate
    this.factor = factor >> 0
    if (factor - this.factor < 0 || factor - this.factor >= 1) throw 'maximum exceeded'
    this.factor = Math.ceil(factor)
  }

  clear() {
    this.offset = (this.factor / 2) >> 0
    this.avail = 0
    this.integrator = 0
    this.data.fill(0)
  }

  clocksNeeded(samples) {
    if (typeof samples !== 'number') throw 'samples must be a number'
    if (samples < 0 || this.avail + samples > this.size) throw 'buffer is full'
    const needed = samples * timeUnit
    if (needed < this.offset) return 0
    else return ((needed - this.offset + this.factor - 1) / this.factor) >> 0
  }

  endFrame(t) {
    if (typeof t !== 'number') throw 't must be a number'
    const off = t * this.factor + this.offset
    this.avail += off >>> timeBits
    this.offset = off & (timeUnit - 1)
    if (this.avail > this.size) throw 'buffer overflow'
  }

  removeSamples(count) {
    if (typeof count !== 'number') throw 'count must be a number'
    const remain = this.avail + bufExtra - count
    this.avail -= count
    for (let i = 0; i < remain; i++) this.data[i] = this.data[i + count] ?? 0
    for (let i = 0; i < count; i++) this.data[i + remain] = 0
  }

  readSamples(out, offset, count, stereo) {
    if (!(out instanceof Float32Array)) throw 'out must be a float32 array'
    if (typeof count !== 'number') throw 'count must be a number'
    if (typeof stereo !== 'boolean') throw 'stereo must be a boolean'

    if (count < 0) throw 'count must be greater than 0'
    if (count > this.avail) count = this.avail

    if (count) {
      let pos = offset
      const step = stereo ? 2 : 1
      let sum = this.integrator
      for (let i = 0; i < count; i++) {
        let s = sum >> deltaBits
        sum += this.data[i]
        s = clamp(s)
        out[pos] = s / 32768
        pos += step
        sum -= s << (deltaBits - bassShift)
      }
      this.integrator = sum
      this.removeSamples(count)
    }

    return count
  }

  addDelta(time, delta) {
    if (typeof time !== 'number') throw 'time must be a number'
    if (typeof delta !== 'number') throw 'delta must be a number'

    const fixed = (time * this.factor + this.offset) >>> 32
    let i = this.avail + (fixed >>> fracBits)

    const phaseShift = fracBits - phaseBits
    const phase = (fixed >> phaseShift) & (phaseCount - 1)
    const rev = phaseCount - phase
    let pos = phase

    const interp = (fixed >> (phaseShift - deltaBits)) & (deltaUnit - 1)
    const delta2 = (delta * interp) >>> deltaBits
    delta -= delta2

    if (i > this.size + endFrameExtra) throw 'buffer overflow'

    this.data[i + 0] += blStep[pos][0] * delta + blStep[pos + 1][0] * delta2
    this.data[i + 1] += blStep[pos][1] * delta + blStep[pos + 1][1] * delta2
    this.data[i + 2] += blStep[pos][2] * delta + blStep[pos + 1][2] * delta2
    this.data[i + 3] += blStep[pos][3] * delta + blStep[pos + 1][3] * delta2
    this.data[i + 4] += blStep[pos][4] * delta + blStep[pos + 1][4] * delta2
    this.data[i + 5] += blStep[pos][5] * delta + blStep[pos + 1][5] * delta2
    this.data[i + 6] += blStep[pos][6] * delta + blStep[pos + 1][6] * delta2
    this.data[i + 7] += blStep[pos][7] * delta + blStep[pos + 1][7] * delta2

    pos = rev
    this.data[i + 8] += blStep[pos][7] * delta + blStep[pos - 1][7] * delta2
    this.data[i + 9] += blStep[pos][6] * delta + blStep[pos - 1][6] * delta2
    this.data[i + 10] += blStep[pos][5] * delta + blStep[pos - 1][5] * delta2
    this.data[i + 11] += blStep[pos][4] * delta + blStep[pos - 1][4] * delta2
    this.data[i + 12] += blStep[pos][3] * delta + blStep[pos - 1][3] * delta2
    this.data[i + 13] += blStep[pos][2] * delta + blStep[pos - 1][2] * delta2
    this.data[i + 14] += blStep[pos][1] * delta + blStep[pos - 1][1] * delta2
    this.data[i + 15] += blStep[pos][0] * delta + blStep[pos - 1][0] * delta2
  }

  addDeltaFast(time, delta) {
    if (typeof time !== 'number') throw 'time must be a number'
    if (typeof delta !== 'number') throw 'delta must be a number'

    const fixed = (time * this.factor + this.offset) >>> 32
    const i = this.avail + (fixed >>> fracBits)

    const interp = (fixed >>> (fracBits - deltaBits)) & (deltaUnit - 1)
    const delta2 = delta * interp

    if (i > this.size + endFrameExtra) throw 'buffer overflow'

    this.data[i + 7] += delta * deltaUnit - delta2
    this.data[i + 8] += delta2
  }
}
