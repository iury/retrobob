import '@mantine/core/styles.css'
import '@mantine/notifications/styles.css'

import { useEffect, useState, useCallback, useRef } from 'react'
import { Notifications, notifications } from '@mantine/notifications'
import { useHotkeys } from '@mantine/hooks'

import {
  ColorSchemeScript,
  MantineProvider,
  Container,
  Stack,
  Group,
  Alert,
  FileButton,
  Button,
  Tooltip,
  NativeSelect,
  Title,
  Text,
  Table,
  List,
  Anchor,
  Space,
  Overlay,
  Center,
} from '@mantine/core'

import {
  IconFolderOpen,
  IconPlayerPauseFilled,
  IconPlayerPlayFilled,
  IconRestore,
  IconWindowMaximize,
  IconDownload,
  IconUpload,
} from '@tabler/icons-react'

import Engine from 'engine'

const Action = {
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

const Event = {
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

const State = { IDLE: 1, PLAYING: 2, PAUSED: 3 }
const Core = { FAMIBOB: 1 }
const Region = { NTSC: 1, PAL: 2 }
const Ratio = { NATIVE: 1, NTSC: 2, PAL: 3, STANDARD: 4, WIDESCREEN: 5 }

import processorUrl from './processor?url'
const audioCtx = new (window.AudioContext || window.webkitAudioContext)({ sampleRate: 48000 })
let audioWorklet

class MyAudioWorklet extends AudioWorkletNode {
  constructor(ctx, engine, address) {
    super(ctx, 'audio-processor', { outputChannelCount: [2] })

    this.engine = engine
    this.address = address
    this.offset = 0

    this.sharedBarrier = new SharedArrayBuffer(2 * 4)
    this.barrier = new Int32Array(this.sharedBarrier)

    this.setSampleSize(800)
  }

  fill() {
    this.buffer.subarray(this.offset, this.offset + this.sampleSize * 2).set(this.data)
    this.offset += this.sampleSize * 2
    if (this.offset == this.buffer.length) this.offset = 0

    this.barrier[1] = this.offset
    if (this.barrier[0] > 0) this.barrier[0]--
  }

  setSampleSize(size) {
    this.barrier[0] = -1

    this.sampleSize = size
    this.offset = 0

    this.sharedBuffer = new SharedArrayBuffer(size * 4 * 2 * 3)
    this.buffer = new Float32Array(this.sharedBuffer)
    this.data = this.engine.HEAPF32.subarray(this.address / 4, this.address / 4 + size * 2)

    this.port.postMessage({ sharedBuffer: this.sharedBuffer, sharedBarrier: this.sharedBarrier })
  }

  teardown() {
    this.barrier[0] = 99
  }
}

function App() {
  const canvasRef = useRef(null)
  const [overlay, setOverlay] = useState(false)
  const [engine, setEngine] = useState(null)
  const [state, setState] = useState(State.IDLE)
  const [region, setRegion] = useState(Region.NTSC)
  const [ratio, setRatio] = useState(Ratio.NATIVE)
  const [regionSupport, setRegionSupport] = useState(false)
  const [slot, setSlot] = useState(1)
  const [hasBattery, setHasBattery] = useState(false)

  const [zoom, setZoom] = useState(() => {
    const v = localStorage.getItem('zoom')
    return v ? parseInt(v) : 3
  })

  useEffect(() => {
    const handler = () => {
      if (document.hidden) audioCtx.suspend()
      else audioCtx.resume()
    }
    document.addEventListener('visibilitychange', handler)
    return () => document.removeEventListener('visibilitychange', handler)
  }, [])

  useEffect(() => {
    engine?._performAction(Action.CHANGE_REGION, region, 0)
    audioWorklet?.setSampleSize(region == Region.NTSC ? 800 : 960)
  }, [engine, region])

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
          }, 300000)
        }
      })
    }
    return () => clearInterval(interval)
  }, [engine, hasBattery])

  const eventHandler = (engine, event, value) => {
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
        setState(State.IDLE)
        setHasBattery(false)
        setRegionSupport(false)
        break
      }
      case Event.GAME_RESET: {
        break
      }
      case Event.GAME_PAUSED: {
        setState(State.PAUSED)
        break
      }
      case Event.GAME_RESUMED: {
        setState(State.PLAYING)
        break
      }
      case Event.STATE_SAVED: {
        engine.FS.syncfs(false, (err) => {
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
        setRegionSupport(!!value)
        break
      }
      case Event.REGION_CHANGED: {
        setRegion(value)
        break
      }
      case Event.RATIO_CHANGED: {
        setRatio(value)
        break
      }
      case Event.ZOOM_CHANGED: {
        localStorage.setItem('zoom', value)
        setZoom(value)
        break
      }
      case Event.SLOT_CHANGED: {
        setSlot(value)
        break
      }
      case Event.HAS_BATTERY: {
        setHasBattery(!!value)
        break
      }
      case Event.BATTERY_PERSISTED: {
        engine.FS.syncfs(false, () => {})
        break
      }
      case Event.END_FRAME: {
        audioWorklet.fill()
        break
      }
    }
  }

  const loadGame = useCallback(
    (file) => {
      canvasRef.current.focus()

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
      } else {
        eventHandler(engine, Event.LOAD_FAILED, 0)
        engine._performAction(Action.UNLOAD_CORE, 0, 0)
        notifications.show({ message: 'Unsupported file' })
      }
    },
    [engine],
  )

  const loadSTB = async () => {
    notifications.show({ message: 'Loading...' })
    const response = await fetch('/super_tilt_bro_[e].nes')
    const data = await response.arrayBuffer()
    loadGame(new File([data], 'super_tilt_bro_[e].nes'))
  }

  const pause = useCallback(() => {
    engine._performAction(Action.PAUSE_GAME, 0, 0)
  }, [engine])

  const play = useCallback(() => {
    engine._performAction(Action.RESUME_GAME, 0, 0)
  }, [engine])

  const reset = useCallback(() => {
    engine._performAction(Action.RESET_GAME, 0, 0)
  }, [engine])

  const toggleFullscreen = useCallback(() => {
    engine._performAction(Action.FULLSCREEN, 0, 0)
  }, [engine])

  const saveState = useCallback(() => {
    engine._performAction(Action.SAVE_STATE, slot, 0)
  }, [engine, slot])

  const loadState = useCallback(() => {
    engine._performAction(Action.LOAD_STATE, slot, 0)
  }, [engine, slot])

  const overlayClick = () => {
    audioCtx.resume()
    setOverlay(false)
  }

  useEffect(() => {
    const handler = () => {
      if (!document.fullscreenElement) {
        setTimeout(() => {
          engine._performAction(Action.FULLSCREEN, 2, 0)
        }, 0)
      }
    }

    const errorHandler = () => {
      if (!document.fullscreenElement) {
        notifications.show({
          message: 'Fullscreen denied by the browser. Click on the fullscreen button.',
          color: 'red',
        })
        setTimeout(() => {
          engine._performAction(Action.FULLSCREEN, 2, 0)
        }, 0)
      }
    }

    document.addEventListener('fullscreenchange', handler)
    document.addEventListener('fullscreenerror', errorHandler)
    return () => {
      document.removeEventListener('fullscreenchange', handler)
      document.removeEventListener('fullscreenerror', errorHandler)
    }
  }, [engine])

  useEffect(() => {
    ;(async () => {
      if (canvasRef) {
        canvasRef.current.focus()

        await audioCtx.audioWorklet.addModule(processorUrl)

        Engine({
          canvas: canvasRef.current,
          printErr: (message) => {
            if (message.startsWith('notify: ')) {
              notifications.show({ message: message.substr(8), color: 'red' })
            } else {
              console.log(`ENGINE: ${message}`)
            }
          },
        }).then((v) => {
          const fid = v.addFunction(eventHandler.bind(this, v), 'vii')
          v._setNotifyEventFn(fid)

          audioWorklet = new MyAudioWorklet(audioCtx, v, v._getAudioBuffer())
          audioWorklet.connect(audioCtx.destination)

          setEngine((prev) => {
            try {
              prev?._terminate()
            } catch (e) {
              console.error(e)
            }

            v.FS.mkdir('/data')
            v.FS.mount(v.IDBFS, {}, '/data')
            v.FS.syncfs(true, () => {})
            setOverlay(true)

            return v
          })
        })
      }
    })()
  }, [canvasRef])

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

  return (
    <>
      <ColorSchemeScript defaultColorScheme="auto" />
      <MantineProvider defaultColorScheme="auto">
        <Notifications position="top-left" autoClose={2000} />

        <a
          className="github-fork-ribbon right-top fixed"
          href="https://github.com/iury/retrobob"
          data-ribbon="Fork me on GitHub"
          title="Fork me on GitHub"
        >
          Fork me on GitHub
        </a>

        <Container size="xl">
          <Stack>
            <Title mt="xl">retrobob</Title>

            <Group align="flex-end">
              <FileButton onChange={loadGame} multiple={false}>
                {(props) => (
                  <Button {...props} leftSection={<IconFolderOpen size={16} />}>
                    Load ROM
                  </Button>
                )}
              </FileButton>

              <Tooltip label="Play">
                <Button onClick={play} variant="outline" color="green" disabled={state !== State.PAUSED}>
                  <IconPlayerPlayFilled size={16} />
                </Button>
              </Tooltip>

              <Tooltip label="Pause">
                <Button onClick={pause} variant="outline" color="yellow" disabled={state !== State.PLAYING}>
                  <IconPlayerPauseFilled size={16} />
                </Button>
              </Tooltip>

              <Tooltip label="Reset">
                <Button onClick={reset} variant="light" color="red" disabled={state === State.IDLE}>
                  <IconRestore size={16} />
                </Button>
              </Tooltip>

              <NativeSelect
                value={slot.toString()}
                data={[
                  { label: 'Slot 1', value: 1 },
                  { label: 'Slot 2', value: 2 },
                  { label: 'Slot 3', value: 3 },
                  { label: 'Slot 4', value: 4 },
                  { label: 'Slot 5', value: 5 },
                  { label: 'Slot 6', value: 6 },
                  { label: 'Slot 7', value: 7 },
                  { label: 'Slot 8', value: 8 },
                  { label: 'Slot 9', value: 9 },
                ]}
                onChange={(evt) => setSlot(parseInt(evt.currentTarget.value))}
              />

              <Tooltip label="Save state">
                <Button onClick={saveState} variant="default" disabled={state === State.IDLE}>
                  <IconDownload size={16} />
                </Button>
              </Tooltip>

              <Tooltip label="Load state">
                <Button onClick={loadState} variant="default" disabled={state === State.IDLE}>
                  <IconUpload size={16} />
                </Button>
              </Tooltip>

              <Group grow align="flex-end" style={{ flexGrow: 1 }}>
                <NativeSelect
                  label="Region"
                  value={region.toString()}
                  data={[
                    { label: 'NTSC', value: 1 },
                    { label: 'PAL', value: 2 },
                  ]}
                  disabled={!regionSupport || state == State.IDLE}
                  onChange={(evt) => setRegion(parseInt(evt.currentTarget.value))}
                />

                <NativeSelect
                  label="Aspect ratio"
                  value={ratio.toString()}
                  data={[
                    { label: 'Native', value: 1 },
                    { label: 'NTSC (8:7 PAR)', value: 2 },
                    { label: 'PAL (11:8 PAR)', value: 3 },
                    { label: 'Standard (4:3)', value: 4 },
                    { label: 'Widescreen (16:9)', value: 5 },
                  ]}
                  onChange={(evt) => setRatio(parseInt(evt.currentTarget.value))}
                />

                <NativeSelect
                  label="Zoom"
                  value={zoom.toString()}
                  data={[
                    { label: '1x', value: 1 },
                    { label: '2x', value: 2 },
                    { label: '3x', value: 3 },
                    { label: '4x', value: 4 },
                  ]}
                  onChange={(evt) => setZoom(parseInt(evt.currentTarget.value))}
                />

                <Button
                  onClick={toggleFullscreen}
                  variant="outline"
                  color="green"
                  leftSection={<IconWindowMaximize size={14} />}
                >
                  Fullscreen
                </Button>
              </Group>
            </Group>

            <Center my="xl">
              <canvas id="canvas" ref={canvasRef} height={720} onDoubleClick={toggleFullscreen}></canvas>
            </Center>

            {overlay && (
              <Overlay center onClick={overlayClick}>
                <Title c="white">Click to enable audio</Title>
              </Overlay>
            )}

            {hasBattery && (
              <Alert title="🔋 Battery Enabled">
                The game state will persist every 5 minutes. A small pause may be noticeable.
              </Alert>
            )}

            <Title order={3}>About</Title>
            <Text>
              <Anchor underline="hover" href="http://github.com/iury/retrobob" target="_blank" rel="noreferrer">
                <strong>retrobob</strong>
              </Anchor>{' '}
              is a retro gaming emulator that runs directly on your browser.
            </Text>
            <Text>
              Don&apos;t have a ROM? Try{' '}
              <Anchor underline="hover" onClick={loadSTB}>
                Super Tilt Bro
              </Anchor>
              , a free game made by{' '}
              <Anchor underline="hover" href="https://sgadrat.itch.io/super-tilt-bro" target="_blank" rel="noreferrer">
                sgadrat
              </Anchor>
              .
            </Text>

            <Title order={3}>Controls</Title>
            <Text>A gamepad (Xbox/PS) or keyboard:</Text>
            <Group grow>
              <Table>
                <Table.Thead>
                  <Table.Tr>
                    <Table.Th>Action</Table.Th>
                    <Table.Th>Key</Table.Th>
                  </Table.Tr>
                </Table.Thead>
                <Table.Tbody>
                  <Table.Tr>
                    <Table.Td>Fullscreen</Table.Td>
                    <Table.Td>F11</Table.Td>
                  </Table.Tr>
                  <Table.Tr>
                    <Table.Td>Save state</Table.Td>
                    <Table.Td>F1</Table.Td>
                  </Table.Tr>
                  <Table.Tr>
                    <Table.Td>Load state</Table.Td>
                    <Table.Td>F4</Table.Td>
                  </Table.Tr>
                  <Table.Tr>
                    <Table.Td>Reset</Table.Td>
                    <Table.Td>F3</Table.Td>
                  </Table.Tr>
                  <Table.Tr>
                    <Table.Td>Pause / Resume</Table.Td>
                    <Table.Td>Space</Table.Td>
                  </Table.Tr>
                  <Table.Tr>
                    <Table.Td>D-pad</Table.Td>
                    <Table.Td>Arrow keys</Table.Td>
                  </Table.Tr>
                  <Table.Tr>
                    <Table.Td>Select</Table.Td>
                    <Table.Td>Q</Table.Td>
                  </Table.Tr>
                  <Table.Tr>
                    <Table.Td>Start</Table.Td>
                    <Table.Td>W or Enter</Table.Td>
                  </Table.Tr>
                  <Table.Tr>
                    <Table.Td align="center">NES / Famicom</Table.Td>
                  </Table.Tr>
                  <Table.Tr>
                    <Table.Td>B</Table.Td>
                    <Table.Td>Z or A</Table.Td>
                  </Table.Tr>
                  <Table.Tr>
                    <Table.Td>A</Table.Td>
                    <Table.Td>X or S</Table.Td>
                  </Table.Tr>
                </Table.Tbody>
              </Table>
              <Text />
            </Group>

            <Title order={3}>Supported Systems</Title>
            <Title order={4}>NES / Famicom</Title>
            <Text>Only the main mappers are implemented but most commercial games should work.</Text>

            <Title order={5}>Known Issues</Title>
            <List>
              <List.Item>Castlevania 3 (MMC5 mapper is not implemented)</List.Item>
              <List.Item>Batman: Return of the Joker (FME-7 mapper is not implemented)</List.Item>
              <List.Item>Battletoads and BT&DD (random crashes)</List.Item>
            </List>

            <Title order={3}>News</Title>
            <Title order={4}>2024-02-17 - Now using WebAssembly</Title>
            <div>
              <p>
                <Anchor underline="hover" href="https://ziglang.org" target="_blank" rel="noreferrer">
                  Zig
                </Anchor>{' '}
                is back. Now using the power of WebAssembly!
              </p>
              <p>
                All rendering and input are handled by the{' '}
                <Anchor underline="hover" href="https://emscripten.org" target="_blank" rel="noreferrer">
                  emscripten
                </Anchor>{' '}
                and{' '}
                <Anchor underline="hover" href="https://www.raylib.com" target="_blank" rel="noreferrer">
                  raylib
                </Anchor>{' '}
                library. Now you can save and load your game state, play using a gamepad, change the aspect ratio, and
                change the console region to NTSC or PAL.
              </p>
              <p>
                There were heavy synchronization issues to tackle. The audio part was done from scratch to take
                advantage of AudioWorklets. You can occasionally hear some artifacts, but these are due of the main
                thread needing to rely on setTimeout to do the frame ticking. Since it is not highly accurate, it will
                get eventually out of sync with the audio thread.
              </p>
              <p>
                Battletoads will crash on the second stage. It is very hard to emulate it correctly since it needs a lot
                of timing precision. I may eventually try again to make it run, but I prefer to do an emulator of
                another system for now.
              </p>
            </div>
            <Title order={4}>2024-02-02 - First version is out!</Title>
            <div>
              <p>
                This version is a port of an earlier build that I made using{' '}
                <Anchor underline="hover" href="https://ziglang.org" target="_blank" rel="noreferrer">
                  Zig
                </Anchor>
                . I was playing with some options for a new version, such as to use Rust, but in the end I took the
                challenge of writing an emulator entirely in pure JavaScript. This is the result of it.
              </p>
              <p>
                It has an implementation of the NES Audio Processing Unit, but at very late in the development I
                discovered that it is really hard to sync audio samples between a Web Worker and the main thread at 60
                FPS, and to write them all in pure JS. So, it&apos;s unlikely that you&apos;ll be able to run it at 60
                FPS with audio output enabled. Also, the implementation of the triangle wave seems to be faulty.
              </p>
              <p>
                All the major mappers are implemented: NROM, CNROM, UxROM, AxROM, MMC1, MMC2 and MMC3. There are some
                games with graphical glitches and Battletoads will crash in the second level. Probably the sprite 0 hit
                detection has some bugs and I am missing some memory readings for the MMC2/MMC3 to do their thing.
              </p>
              <p>
                <Anchor
                  underline="hover"
                  href="https://www.nesdev.org/wiki/Nesdev_Wiki"
                  target="_blank"
                  rel="noreferrer"
                >
                  NesDev Wiki
                </Anchor>{' '}
                was the main resource about the NES internals. I also recommend{' '}
                <Anchor
                  underline="hover"
                  href="https://www.masswerk.at/6502/6502_instruction_set.html"
                  target="_blank"
                  rel="noreferrer"
                >
                  this site
                </Anchor>{' '}
                for how to do a 6502 CPU implementation. A lot of the PPU and pretty much the entire APU was ported from
                the{' '}
                <Anchor underline="hover" href="https://github.com/SourMesen/Mesen" target="_blank" rel="noreferrer">
                  Mesen
                </Anchor>{' '}
                source code. I also rebuild the{' '}
                <Anchor
                  underline="hover"
                  href="https://code.google.com/archive/p/blip-buf/"
                  target="_blank"
                  rel="noreferrer"
                >
                  blip-buf
                </Anchor>{' '}
                library entirely in JavaScript.
              </p>
              <p>
                I intend to build the next version using WebAssembly so it can run with audio at 60 FPS, to add support
                for gamepads and to add more systems in the future. This version will be tagged as an archive for anyone
                who is curious about a 100% implementation using JavaScript only.
              </p>
            </div>
            <Space />
            <Space />
            <Space />
          </Stack>
        </Container>
      </MantineProvider>
    </>
  )
}

export default App
