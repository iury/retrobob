import { useEffect, useCallback, forwardRef } from 'react'
import { useAtom, useAtomValue } from 'jotai'
import { useAtomCallback } from 'jotai/utils'
import { notifications } from '@mantine/notifications'
import { Overlay, Title } from '@mantine/core'
import { useHotkeys } from '@mantine/hooks'

import {
  Event,
  State,
  Action,
  audioCtxAtom,
  audioWorkletAtom,
  engineAtom,
  hasBatteryAtom,
  overlayAtom,
  ratioAtom,
  regionAtom,
  regionSupportAtom,
  slotAtom,
  stateAtom,
  zoomAtom,
} from './global'

import EngineModule from 'engine'

export const Engine = forwardRef(function Engine(props, ref) {
  const [engine, setEngine] = useAtom(engineAtom)
  const [overlay, setOverlay] = useAtom(overlayAtom)
  const [hasBattery, setHasBattery] = useAtom(hasBatteryAtom)
  const audioCtx = useAtomValue(audioCtxAtom)
  const ratio = useAtomValue(ratioAtom)
  const zoom = useAtomValue(zoomAtom)
  const slot = useAtomValue(slotAtom)

  const eventHandler = useAtomCallback(
    useCallback((get, set, event, value) => {
      if (event != Event.END_FRAME) {
        console.log(`Event ${Object.keys(Event).find((d) => Event[d] === event)} with value ${value} received.`)
      }

      switch (event) {
        case Event.GAME_LOADED: {
          notifications.show({ message: 'Game loaded' })
          break
        }
        case Event.LOAD_FAILED: {
          notifications.show({ message: 'Failed to load', color: 'red' })
          break
        }
        case Event.CORE_UNLOADED: {
          set(stateAtom, State.IDLE)
          set(hasBatteryAtom, false)
          set(regionSupportAtom, false)
          break
        }
        case Event.GAME_RESET: {
          break
        }
        case Event.GAME_PAUSED: {
          set(stateAtom, State.PAUSED)
          break
        }
        case Event.GAME_RESUMED: {
          set(stateAtom, State.PLAYING)
          break
        }
        case Event.STATE_SAVED: {
          get(engineAtom).FS.syncfs(false, (err) => {
            if (err) {
              notifications.show({ message: 'Failed to save', color: 'red' })
            } else {
              notifications.show({ message: `State saved at slot ${value}` })
            }
          })
          break
        }
        case Event.STATE_LOADED: {
          if (value > 0) {
            notifications.show({ message: `State loaded from slot ${value}` })
          }
          break
        }
        case Event.REGION_SUPPORT: {
          set(regionSupportAtom, !!value)
          set(regionAtom, 1)
          break
        }
        case Event.REGION_CHANGED: {
          set(regionAtom, value)
          break
        }
        case Event.RATIO_CHANGED: {
          set(ratioAtom, value)
          break
        }
        case Event.ZOOM_CHANGED: {
          set(zoomAtom, value)
          break
        }
        case Event.SLOT_CHANGED: {
          set(slotAtom, value)
          break
        }
        case Event.HAS_BATTERY: {
          set(hasBatteryAtom, !!value)
          break
        }
        case Event.BATTERY_PERSISTED: {
          get(engineAtom).FS.syncfs(false, () => {})
          break
        }
        case Event.END_FRAME: {
          get(audioWorkletAtom).fill()
          break
        }
      }
    }, []),
  )

  useEffect(() => {
    engine?._performAction(Action.CHANGE_RATIO, ratio, 0)
  }, [engine, ratio])

  useEffect(() => {
    engine?._performAction(Action.CHANGE_ZOOM, zoom, 0)
  }, [engine, zoom])

  useEffect(() => {
    engine?._performAction(Action.CHANGE_SLOT, slot, 0)
  }, [engine, slot])

  useEffect(() => {
    let interval
    if (engine && hasBattery) {
      engine.FS.syncfs(false, (err) => {
        if (err) {
          setHasBattery(false)
        } else {
          interval = setInterval(() => {
            engine._performAction(Action.PERSIST_BATTERY, 0, 0)
          }, 30000)
        }
      })
    }
    return () => clearInterval(interval)
  }, [engine, hasBattery, setHasBattery])

  useEffect(() => {
    if (ref) {
      ;(async () => {
        ref.current.focus()

        const v = await EngineModule({
          canvas: ref.current,
          printErr: (message) => {
            if (message.startsWith('notify: ')) {
              notifications.show({ message: message.substr(8), color: 'red' })
            } else {
              console.log(`ENGINE: ${message}`)
            }
          },
        })

        const fid = v.addFunction(eventHandler, 'vii')
        v._setNotifyEventFn(fid)

        setEngine((old) => {
          old?._terminate()

          v.FS.mkdir('/data')
          v.FS.mount(v.IDBFS, {}, '/data')

          v.FS.syncfs(true, () => {
            // eslint-disable-next-line no-undef
            const version = __APP_VERSION__

            try {
              v.FS.stat(`/data/${version}`)
            } catch {
              v.FS.mkdir(`/data/${version}`)
            }

            v.FS.symlink(`/data/${version}`, '/saves')
          })
          setOverlay(true)

          return v
        })
      })()
    }
  }, [ref, eventHandler, setEngine, setOverlay])

  useHotkeys([
    ['Space', () => {}],
    ['F1', () => {}],
    ['F3', () => {}],
    ['F4', () => {}],
    ['F11', () => {}],
    ['ArrowLeft', () => {}],
    ['ArrowRight', () => {}],
    ['ArrowUp', () => {}],
    ['ArrowDown', () => {}],
  ])

  const overlayClick = useCallback(() => {
    audioCtx.resume()
    setOverlay(false)
  }, [audioCtx, setOverlay])

  const doubleClick = useCallback(() => {
    engine._performAction(Action.FULLSCREEN, 0, 0)
  }, [engine])

  return (
    <>
      <canvas id="canvas" ref={ref} height={720} onDoubleClick={doubleClick} {...props}></canvas>
      {overlay && (
        <Overlay center onClick={overlayClick}>
          <Title c="white">Click to enable audio</Title>
        </Overlay>
      )}
    </>
  )
})
