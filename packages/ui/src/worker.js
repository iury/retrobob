import { Core as Famibob } from 'engine/famibob'

let canvas, core

onmessage = async ({ data: { event, data } }) => {
  if (event === 'init') {
    canvas = data.canvas
    const ctx = canvas.getContext('2d', { alpha: false })
    ctx.clearRect(0, 0, canvas.width, canvas.height)
  } else if (event === 'file') {
    try {
      if (data.name.toLowerCase().endsWith('.nes')) {
        await core?.cleanup()
        core = new Famibob(data.name, new Uint8Array(data.buffer), canvas.getContext('2d', { alpha: false }))
        canvas.width = core.width
        canvas.height = core.height
        core.play()
      } else {
        postMessage({ event: 'error', data: 'Unknown file extension' })
      }
    } catch (e) {
      postMessage({ event: 'error', data: e })
    }
  } else if (event === 'reset') {
    core?.reset()
  } else if (event === 'pause') {
    core?.pause()
  } else if (event === 'play') {
    core?.play()
  } else if (event === 'savestate') {
    core?.saveState(data)
  } else if (event === 'loadstate') {
    core?.loadState(data)
  } else if (event === 'region') {
    core?.setRegion(data)
  } else if (event === 'keydown') {
    core?.keydown(data.player, data.key)
  } else if (event === 'keyup') {
    core?.keyup(data.player, data.key)
  }
}
