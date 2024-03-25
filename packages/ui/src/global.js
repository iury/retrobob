import { atom } from 'jotai'
import { atomWithStorage } from 'jotai/utils'
import { notifications } from '@mantine/notifications'

export const Action = {
  LOAD_CORE: 1,
  LOAD_GAME: 2,
  RESUME_GAME: 3,
  PAUSE_GAME: 4,
  RESET_GAME: 5,
  CHANGE_REGION: 8,
  UNLOAD_CORE: 9,
  CHANGE_SLOT: 11,
  SAVE_STATE: 12,
  LOAD_STATE: 13,
  PERSIST_BATTERY: 14,
  FULLSCREEN: 21,
  CHANGE_RATIO: 22,
  CHANGE_ZOOM: 23,
}

export const Event = {
  CORE_LOADED: 1,
  GAME_LOADED: 2,
  LOAD_FAILED: 92,
  GAME_RESUMED: 3,
  GAME_PAUSED: 4,
  GAME_RESET: 5,
  REGION_CHANGED: 8,
  CORE_UNLOADED: 9,
  SLOT_CHANGED: 11,
  STATE_SAVED: 12,
  STATE_LOADED: 13,
  BATTERY_PERSISTED: 14,
  RATIO_CHANGED: 22,
  ZOOM_CHANGED: 23,
  HAS_BATTERY: 73,
  REGION_SUPPORT: 79,
  END_FRAME: 99,
}

export const Core = { FAMIBOB: 1, GAMEBOB: 2, SUPERBOB: 3 }
export const State = { IDLE: 1, PLAYING: 2, PAUSED: 3 }
export const Region = { NTSC: 1, PAL: 2 }
export const Ratio = { NATIVE: 1, NTSC: 2, PAL: 3, STANDARD: 4, WIDESCREEN: 5 }

export const audioCtxAtom = atom(new (window.AudioContext || window.webkitAudioContext)({ sampleRate: 44100 }))
export const audioWorkletAtom = atom(null)
export const engineAtom = atom(null)
export const overlayAtom = atom(false)
export const stateAtom = atom(State.IDLE)
export const ratioAtom = atom(Ratio.NATIVE)
export const regionAtom = atom(Region.NTSC)
export const regionSupportAtom = atom(false)
export const slotAtom = atom(1)
export const hasBatteryAtom = atom(false)
export const zoomAtom = atomWithStorage('zoom', 3)

export function loadGame(engine, file) {
  if (file.name.toLowerCase().endsWith('.nes')) {
    engine._performAction(Action.LOAD_CORE, Core.FAMIBOB, 0)

    const reader = new FileReader()
    reader.onload = () => {
      const data = new Uint8Array(reader.result)
      const m = engine._malloc(data.length)
      engine.HEAPU8.set(data, m)
      engine._performAction(Action.LOAD_GAME, data.length, m)
      engine._free(m)

      // eslint-disable-next-line no-useless-escape
      if (/([\[\(])(e|pal|europe)([\)\]])/.test(file.name.toLowerCase())) {
        engine._performAction(Action.CHANGE_REGION, Region.PAL, 0)
      } else {
        engine._performAction(Action.CHANGE_REGION, Region.NTSC, 0)
      }
    }
    reader.readAsArrayBuffer(file)
  } else if (file.name.toLowerCase().endsWith('.gb') || file.name.toLowerCase().endsWith('.gbc')) {
    engine._performAction(Action.LOAD_CORE, Core.GAMEBOB, 0)

    const reader = new FileReader()
    reader.onload = () => {
      const data = new Uint8Array(reader.result)
      const m = engine._malloc(data.length)
      engine.HEAPU8.set(data, m)
      engine._performAction(Action.LOAD_GAME, data.length, m)
      engine._free(m)
    }
    reader.readAsArrayBuffer(file)
  } else if (file.name.toLowerCase().endsWith('.sfc') || file.name.toLowerCase().endsWith('.smc')) {
    engine._performAction(Action.LOAD_CORE, Core.SUPERBOB, 0)

    const reader = new FileReader()
    reader.onload = () => {
      const data = new Uint8Array(reader.result)
      const m = engine._malloc(data.length)
      engine.HEAPU8.set(data, m)
      engine._performAction(Action.LOAD_GAME, data.length, m)
      engine._free(m)
    }
    reader.readAsArrayBuffer(file)
  } else {
    engine._performAction(Action.UNLOAD_CORE, 0, 0)
    notifications.show({ message: 'Failed to load', color: 'red' })
    notifications.show({ message: 'Unsupported file' })
  }
}
