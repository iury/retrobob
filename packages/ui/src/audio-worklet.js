export class MyAudioWorklet extends AudioWorkletNode {
  constructor(ctx, engine, address) {
    super(ctx, 'audio-processor', { outputChannelCount: [2] })

    this.engine = engine
    this.address = address
    this.offset = 0

    this.sharedBarrier = new SharedArrayBuffer(2 * 4)
    this.barrier = new Int32Array(this.sharedBarrier)

    this.setSampleSize(735)
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
