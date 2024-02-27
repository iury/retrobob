import { useEffect, useCallback } from 'react'
import { useAtomValue } from 'jotai'
import { Button } from '@mantine/core'
import { notifications } from '@mantine/notifications'
import { IconWindowMaximize } from '@tabler/icons-react'
import { Action, engineAtom } from './global'

export function FullscreenButton() {
  const engine = useAtomValue(engineAtom)

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

  const fullscreenClick = useCallback(() => {
    engine._performAction(Action.FULLSCREEN, 0, 0)
  }, [engine])

  return (
    <Button onClick={fullscreenClick} variant="outline" color="green" leftSection={<IconWindowMaximize size={16} />}>
      Fullscreen
    </Button>
  )
}
