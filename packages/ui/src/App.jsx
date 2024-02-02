import '@mantine/core/styles.css'

import { useCallback, useState, useEffect, useRef } from 'react'
import {
  MantineProvider,
  Container,
  Button,
  Stack,
  Group,
  Title,
  Text,
  AspectRatio,
  Overlay,
  Table,
  List,
  Alert,
  Anchor,
  Space,
} from '@mantine/core'
import { useFullscreen } from '@mantine/hooks'
import { useDropzone } from 'react-dropzone'
import { useHotkeys } from 'react-hotkeys-hook'

import MyWorker from './worker?worker'

/** @enum */
const State = {
  OFF: 'OFF',
  PLAYING: 'PLAYING',
  PAUSED: 'PAUSED',
}

let audioCtx = new AudioContext()
let audioBuffer

function App() {
  const [worker, setWorker] = useState(null)
  const [state, setState] = useState(State.OFF)
  const [fps, setFps] = useState(0)
  const canvasRef = useRef(null)

  const { toggle: toggleFullscreen, ref: fullscreenRef } = useFullscreen()

  useHotkeys(
    'f3,f11,q,w,a,s,z,x,space,up,down,left,right',
    ({ type, key }) => {
      const mapKeys = {
        q: 'start',
        w: 'select',
        a: 'b',
        s: 'a',
        z: 'b',
        x: 'a',
        ArrowUp: 'up',
        ArrowDown: 'down',
        ArrowLeft: 'left',
        ArrowRight: 'right',
      }

      if (type === 'keyup') {
        if (key === 'F3') reset()
        else if (key === 'F11') toggleFullscreen()
        else if (key === ' ') state === State.PLAYING ? pause() : play()
        else worker.postMessage({ event: 'keyup', data: { player: 1, key: mapKeys[key] } })
      } else if (Object.keys(mapKeys).includes(key)) {
        worker.postMessage({ event: 'keydown', data: { player: 1, key: mapKeys[key] } })
      }
    },
    {
      enabled: state !== State.OFF,
      keydown: true,
      keyup: true,
      preventDefault: true,
    },
    [state, worker],
  )

  useEffect(() => {
    const w = new MyWorker()
    const canvas = canvasRef.current.transferControlToOffscreen()
    w.postMessage({ event: 'init', data: { canvas } }, [canvas])
    setWorker(w)

    const handler = ({ data: { event, data } }) => {
      if (event === 'fps') setFps(data)
      else if (event === 'gameplaying') setState(State.PLAYING)
      else if (event === 'gamepaused') {
        setState(State.PAUSED)
        if (audioBuffer) audioBuffer.getChannelData(0).fill(0)
      } else if (event === 'gameloaded') {
        setState(State.PAUSED)
        // audioBuffer = audioCtx.createBuffer(data.audio.channels, data.audio.length, data.audio.rate)
        // const playBuffer = () => {
        //   if (!audioBuffer) return
        //   const source = audioCtx.createBufferSource()
        //   source.buffer = audioBuffer
        //   source.connect(audioCtx.destination)
        //   source.addEventListener('ended', playBuffer)
        //   source.start()
        // }
        // playBuffer()
      } else if (event === 'audiosample') {
        audioBuffer.copyToChannel(data, 0)
      } else console.log(event, data)
    }

    w.addEventListener('message', handler)
    return () => w.removeEventListener('message', handler)
  }, [])

  const pause = useCallback(() => worker.postMessage({ event: 'pause' }), [worker])
  const play = useCallback(() => worker.postMessage({ event: 'play' }), [worker])
  const reset = useCallback(() => worker.postMessage({ event: 'reset' }), [worker])

  const onDrop = useCallback(
    (files) => {
      if (files.length) {
        audioCtx.resume()
        audioBuffer = null

        const reader = new FileReader()
        reader.onload = () => {
          worker.postMessage(
            {
              event: 'file',
              data: {
                name: files[0].name,
                buffer: reader.result,
              },
            },
            [reader.result],
          )
        }
        reader.readAsArrayBuffer(files[0])
      }
    },
    [worker],
  )

  const { getRootProps, getInputProps, open } = useDropzone({ onDrop, noClick: true, maxFiles: 1 })

  return (
    <MantineProvider>
      <a
        className="github-fork-ribbon right-top fixed"
        href="https://github.com/iury/retrobob"
        data-ribbon="Fork me on GitHub"
        title="Fork me on GitHub"
      >
        Fork me on GitHub
      </a>
      <Container>
        <Stack>
          <Title>retrobob</Title>

          <Group grow>
            <Button onClick={open}>Load ROM file</Button>
            {state !== State.PAUSED && (
              <Button onClick={pause} variant="default" disabled={state !== State.PLAYING}>
                Pause
              </Button>
            )}
            {state === State.PAUSED && (
              <Button variant="default" onClick={play}>
                Play
              </Button>
            )}
            <Button onClick={reset} variant="default" disabled={state === State.OFF}>
              Reset
            </Button>
            <Button onClick={toggleFullscreen} variant="default" disabled={state === State.OFF}>
              Full screen
            </Button>
            {state === State.PLAYING ? <Text style={{ textAlign: 'right', width: '100%' }}>FPS: {fps}</Text> : <Text />}
          </Group>

          <center>
            <AspectRatio ratio={256 / 240} maw={256} ref={fullscreenRef}>
              <canvas ref={canvasRef} width={256} height={240}></canvas>
              <Overlay color="#ddd" backgroundOpacity={state === State.OFF ? 1 : 0} {...getRootProps()}>
                <div>
                  <input {...getInputProps()} />
                  {state === State.OFF && <Text>Drag your ROM file here.</Text>}
                </div>
              </Overlay>
            </AspectRatio>
          </center>

          <Alert color="red" title="No audio">
            This version intentionally doesn&apos;t output audio. See notes below.
          </Alert>

          <Title order={3}>About</Title>
          <Text>
            <Anchor underline="hover" href="http://github.com/iury/retrobob" target="_blank" rel="noreferrer">
              <Text span c="black" fw={700}>
                retrobob
              </Text>
            </Anchor>{' '}
            is a retro gaming emulator that runs directly on your browser.
          </Text>

          <Title order={3}>Supported Systems</Title>
          <Title order={4}>NES / Famicom</Title>
          <Text>Only the main mappers are implemented but most commercial games should work.</Text>

          <Title order={5}>Controls</Title>
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
                  <Table.Td>Start</Table.Td>
                  <Table.Td>Q</Table.Td>
                </Table.Tr>
                <Table.Tr>
                  <Table.Td>Select</Table.Td>
                  <Table.Td>W</Table.Td>
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

          <Title order={5}>Known Issues</Title>
          <List>
            <List.Item>Castlevania 3 (MMC5 mapper is not implemented)</List.Item>
            <List.Item>Super Mario Bros. 3 (graphical glitches)</List.Item>
            <List.Item>Punch-out!! (graphical glitches)</List.Item>
            <List.Item>Battletoads (crashes)</List.Item>
            <List.Item>Battletoads & Double Dragon (unplayable)</List.Item>
          </List>

          <Title order={3}>News</Title>
          <Title order={4}>2024-02-02 - First version is out!</Title>
          <div>
            <p>Hello!</p>
            <p>
              This version is a port of an earlier build that I made using{' '}
              <a href="https://ziglang.org" target="_blank" rel="noreferrer">
                Zig
              </a>
              . I was playing with some options for a new version, such as to use Rust, but in the end I took the
              challenge of writing an emulator entirely in pure JavaScript. This is the result of it.
            </p>
            <p>
              It has an implementation of the NES Audio Processing Unit, but at very late in the development I
              discovered that it is really hard to sync audio samples between a Web Worker and the main thread at 60
              FPS, and to write them all in pure JS. So, it&apos;s unlikely that you&apos;ll be able to run it at 60 FPS
              with audio output enabled. Also, the implementation of the triangle wave seems to be faulty.
            </p>
            <p>
              All the major mappers are implemented: NROM, CNROM, UxROM, AxROM, MMC1, MMC2 and MMC3. There are some
              games with graphical glitches and Battletoads will crash in the second level. Probably the sprite 0 hit
              detection has some bugs and I am missing some memory readings for the MMC2/MMC3 to do their thing.
            </p>
            <p>
              <a href="https://www.nesdev.org/wiki/NES_reference_guide" target="_blank" rel="noreferrer">
                NesDev Wiki
              </a>{' '}
              was the main resource about the NES internals. I also recommend{' '}
              <a href="https://www.masswerk.at/6502/6502_instruction_set.html" target="_blank" rel="noreferrer">
                this site
              </a>{' '}
              for how to do a 6502 CPU implementation. A lot of the PPU and pretty much the entire APU was ported from
              the{' '}
              <a href="https://github.com/SourMesen/Mesen" target="_blank" rel="noreferrer">
                Mesen
              </a>{' '}
              source code. I also rebuild the{' '}
              <a href="https://code.google.com/archive/p/blip-buf/" target="_blank" rel="noreferrer">
                blip-buf
              </a>{' '}
              library entirely in JavaScript.
            </p>
            <p>
              I intend to build the next version using WebAssembly so it can run with audio at 60 FPS, to add support
              for Gamepads and to add more systems in the future. This version will be tagged as an archive for anyone
              who is curious about a 100% implementation using JavaScript only.
            </p>
          </div>
          <Space />
          <Space />
          <Space />
        </Stack>
      </Container>
    </MantineProvider>
  )
}

export default App
