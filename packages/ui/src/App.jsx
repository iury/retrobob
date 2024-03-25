import '@mantine/core/styles.css'
import '@mantine/notifications/styles.css'

import { useCallback, useRef } from 'react'
import { useAtom, useAtomValue } from 'jotai'
import { Notifications } from '@mantine/notifications'

import { Engine } from './Engine'
import { Audio } from './Audio'

import {
  loadGame,
  Action,
  State,
  engineAtom,
  regionAtom,
  ratioAtom,
  zoomAtom,
  slotAtom,
  hasBatteryAtom,
  stateAtom,
  regionSupportAtom,
} from './global'

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
  Text,
  Space,
  Center,
  TypographyStylesProvider,
} from '@mantine/core'

import {
  IconFolderOpen,
  IconPlayerPauseFilled,
  IconPlayerPlayFilled,
  IconRestore,
  IconDownload,
  IconUpload,
} from '@tabler/icons-react'
import { FullscreenButton } from './FullscreenButton'

import { html as readme } from '../../../README.md'
import { html as changelog } from '../../../CHANGELOG.md'
import { html as news } from '../../../NEWS.md'

function App() {
  const engineRef = useRef(null)
  const engine = useAtomValue(engineAtom)
  const state = useAtomValue(stateAtom)
  const regionSupport = useAtomValue(regionSupportAtom)
  const [hasBattery, setHasBattery] = useAtom(hasBatteryAtom)

  const [region, setRegion] = useAtom(regionAtom)
  const [ratio, setRatio] = useAtom(ratioAtom)
  const [zoom, setZoom] = useAtom(zoomAtom)
  const [slot, setSlot] = useAtom(slotAtom)

  const loadGameClick = useCallback(
    (file) => {
      engineRef.current.focus()
      loadGame(engine, file)
    },
    [engine],
  )

  const playClick = useCallback(() => {
    engine._performAction(Action.RESUME_GAME, 0, 0)
  }, [engine])

  const pauseClick = useCallback(() => {
    engine._performAction(Action.PAUSE_GAME, 0, 0)
  }, [engine])

  const resetClick = useCallback(() => {
    engine._performAction(Action.RESET_GAME, 0, 0)
  }, [engine])

  const saveStateClick = useCallback(() => {
    engine._performAction(Action.SAVE_STATE, slot, 0)
  }, [engine, slot])

  const loadStateClick = useCallback(() => {
    engine._performAction(Action.LOAD_STATE, slot, 0)
  }, [engine, slot])

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
            <Space />
            <Space />

            <Group align="flex-end">
              <FileButton onChange={loadGameClick} multiple={false}>
                {(props) => (
                  <Button {...props} leftSection={<IconFolderOpen size={16} />}>
                    Load ROM
                  </Button>
                )}
              </FileButton>

              <Tooltip label="Play">
                <Button onClick={playClick} variant="outline" color="green" disabled={state !== State.PAUSED}>
                  <IconPlayerPlayFilled size={16} />
                </Button>
              </Tooltip>

              <Tooltip label="Pause">
                <Button onClick={pauseClick} variant="outline" color="yellow" disabled={state !== State.PLAYING}>
                  <IconPlayerPauseFilled size={16} />
                </Button>
              </Tooltip>

              <Tooltip label="Reset">
                <Button onClick={resetClick} variant="light" color="red" disabled={state === State.IDLE}>
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
                <Button onClick={saveStateClick} variant="default" disabled={state === State.IDLE}>
                  <IconDownload size={16} />
                </Button>
              </Tooltip>

              <Tooltip label="Load state">
                <Button onClick={loadStateClick} variant="default" disabled={state === State.IDLE}>
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

                <FullscreenButton />
              </Group>
            </Group>

            <Center my="xl">
              <Audio />
              <Engine ref={engineRef} />
            </Center>

            {hasBattery && (
              <Alert title="🔋 Battery Enabled">
                <Stack>
                  <Text size="md">The game state will persist every 15 seconds.</Text>
                  <Text>
                    <Button onClick={() => setHasBattery(false)} variant="default">
                      Disable Battery
                    </Button>
                  </Text>
                </Stack>
              </Alert>
            )}

            <TypographyStylesProvider>
              <base target="_blank" />
              <div dangerouslySetInnerHTML={{ __html: readme }} />
            </TypographyStylesProvider>

            <TypographyStylesProvider>
              <base target="_blank" />
              <div dangerouslySetInnerHTML={{ __html: changelog }} />
            </TypographyStylesProvider>

            <TypographyStylesProvider>
              <base target="_blank" />
              <div dangerouslySetInnerHTML={{ __html: news }} />
            </TypographyStylesProvider>

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
