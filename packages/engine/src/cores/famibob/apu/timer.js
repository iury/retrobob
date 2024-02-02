export class Timer {
  constructor(mixer, channel) {
    this.mixer = mixer
    this.channel = channel
    this.previousCycle = 0
    this.timer = 0
    this.period = 0
    this.lastOutput = 0
  }

  addOutput(output) {
    if (output !== this.lastOutput) {
      this.mixer.addDelta(this.channel, this.previousCycle, output - this.lastOutput)
      this.lastOutput = output
    }
  }

  run(targetCycle) {
    const cyclesToRun = targetCycle - this.previousCycle

    if (cyclesToRun > this.timer) {
      this.previousCycle += this.timer + 1
      this.timer = this.period
      return true
    }

    this.timer -= cyclesToRun
    this.previousCycle = targetCycle
    return false
  }

  endFrame() {
    this.previousCycle = 0
  }

  reset() {
    this.timer = 0
    this.period = 0
    this.previousCycle = 0
    this.lastOutput = 0
  }
}
