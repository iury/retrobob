class AudioProcessor extends AudioWorkletProcessor {
  constructor() {
    super()
    this.cursor = 0
    this.port.onmessage = ({ data: { sharedBuffer, sharedBarrier } }) => {
      this.barrier = new Int32Array(sharedBarrier)
      this.buffer = new Float32Array(sharedBuffer)
    }
  }

  process(inputs, outputs) {
    const output = outputs[0]

    if (this.barrier[0]) {
      if (this.barrier[0] < 0) {
        this.cursor = 0
        this.barrier[0] = 2
      }

      if (this.barrier[0] == 99) return false
      return true
    }

    for (let i = 0; i < 128; i++) {
      output[0][i] = this.buffer[this.cursor++]
      output[1][i] = this.buffer[this.cursor++]
      if (this.cursor == this.buffer.length) this.cursor = 0
      if (this.cursor == this.barrier[1]) this.barrier[0] = 2
    }

    return true
  }
}

registerProcessor('audio-processor', AudioProcessor)
