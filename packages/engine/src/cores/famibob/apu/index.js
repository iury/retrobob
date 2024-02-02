import { APU } from './apu'
import { DMC } from './dmc'
import { Envelope } from './envelope'
import { FrameCounter, FRAME_TYPE } from './frame_counter'
import { LengthCounter } from './length_counter'
import { Mixer } from './mixer'
import { Noise } from './noise'
import { Square, SQUARE_CHANNEL } from './square'
import { Timer } from './timer'
import { Triangle } from './triangle'

/** @enum */
export const AUDIO_CHANNEL = {
  SQUARE1: 0,
  SQUARE2: 1,
  TRIANGLE: 2,
  NOISE: 3,
  DMC: 4,
  FDS: 5,
  MMC5: 6,
  VRC6: 7,
  VRC7: 8,
  NAMCO163: 9,
  SUNSOFT5B: 10,
}

export const DMC_LOOKUP_TABLE_NTSC = [428, 380, 340, 320, 286, 254, 226, 214, 190, 160, 142, 128, 106, 84, 72, 54]

export const DMC_LOOKUP_TABLE_PAL = [398, 354, 316, 298, 276, 236, 210, 198, 176, 148, 132, 118, 98, 78, 66, 50]

export const NOISE_LOOKUP_TABLE_NTSC = [4, 8, 16, 32, 64, 96, 128, 160, 202, 254, 380, 508, 762, 1016, 2034, 4068]

export const NOISE_LOOKUP_TABLE_PAL = [4, 8, 14, 30, 60, 88, 118, 148, 188, 236, 354, 472, 708, 944, 1890, 3778]

export const STEP_CYCLES_NTSC = [
  [7457, 14913, 22371, 29828, 29829, 29830],
  [7457, 14913, 22371, 29829, 37281, 37282],
]

export const STEP_CYCLES_PAL = [
  [8313, 16627, 24939, 33252, 33253, 33254],
  [8313, 16627, 24939, 33253, 41565, 41566],
]

export {
  APU,
  DMC,
  Envelope,
  FrameCounter,
  LengthCounter,
  Mixer,
  Noise,
  Square,
  Timer,
  Triangle,
  FRAME_TYPE,
  SQUARE_CHANNEL,
}
