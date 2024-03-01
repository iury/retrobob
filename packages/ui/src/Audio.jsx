import { useEffect } from 'react'
import { useAtom, useAtomValue } from 'jotai'
import { Action, Region, engineAtom, audioCtxAtom, audioWorkletAtom, regionAtom } from './global'
import { MyAudioWorklet } from './audio-worklet'
import processorUrl from './audio-processor?url'

export function Audio() {
  const audioCtx = useAtomValue(audioCtxAtom)
  const engine = useAtomValue(engineAtom)
  const region = useAtomValue(regionAtom)
  const [audioWorklet, setAudioWorklet] = useAtom(audioWorkletAtom)

  useEffect(() => {
    if (engine && audioWorklet && region) {
      engine._performAction(Action.CHANGE_REGION, region, 0)
      audioWorklet.setSampleSize(region == Region.NTSC ? 735 : 882)
    }
  }, [engine, audioWorklet, region])

  useEffect(() => {
    const handler = () => {
      if (document.hidden) audioCtx.suspend()
      else audioCtx.resume()
    }
    document.addEventListener('visibilitychange', handler)
    return () => document.removeEventListener('visibilitychange', handler)
  }, [audioCtx])

  useEffect(() => {
    if (audioCtx && engine) {
      ;(async () => {
        await audioCtx.audioWorklet.addModule(processorUrl)
        setAudioWorklet((old) => {
          old?.teardown()
          const worklet = new MyAudioWorklet(audioCtx, engine, engine._getAudioBuffer())
          worklet.connect(audioCtx.destination)
          return worklet
        })
      })()
    }
  }, [audioCtx, engine, setAudioWorklet])

  return <></>
}
