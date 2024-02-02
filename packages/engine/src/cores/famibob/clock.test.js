import { test, expect } from 'vitest'
import { Region, Clock, RunOption } from '.'

test('ntsc clock', () => {
  let cpu = 0
  let ppu = 0
  const clock = new Clock(
    Region.NTSC,
    () => cpu++,
    () => ppu++,
  )

  for (let i = 0; i < 60; i++) clock.run(RunOption.FRAME)

  expect(cpu / 60).toBeCloseTo(29780 + 2 / 3, 1)
  expect(ppu / 60).toBeCloseTo(89342, 1)
})

test('pal clock', () => {
  let cpu = 0
  let ppu = 0
  const clock = new Clock(
    Region.PAL,
    () => cpu++,
    () => ppu++,
  )

  for (let i = 0; i < 50; i++) clock.run(RunOption.FRAME)

  expect(cpu / 50).toBeCloseTo(33247.5, 1)
  expect(ppu / 50).toBeCloseTo(106392, 1)
})
