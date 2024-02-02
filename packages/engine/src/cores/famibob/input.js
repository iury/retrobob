const mapKeys = {
  a: 0x01,
  b: 0x02,
  select: 0x04,
  start: 0x08,
  up: 0x10,
  down: 0x20,
  left: 0x40,
  right: 0x80,
}

export class Input {
  constructor() {
    this.latch = [0, 0]
    this.state = [0, 0]
    this.strobe = false
  }

  setKeyUp(player, key) {
    this.state[player - 1] &= ~mapKeys[key]
  }

  setKeyDown(player, key) {
    this.state[player - 1] |= mapKeys[key]
  }

  poll() {
    this.latch = [...this.state]
    // clear impossible directions
    for (let i = 0; i < this.latch.length; i++) {
      if ((this.latch[i] & 0x30) === 0x30) this.latch[i] &= ~0x30
      if ((this.latch[i] & 0xc0) === 0xc0) this.latch[i] &= ~0xc0
    }
  }

  read(address) {
    if (this.strobe) this.poll()

    // 0x4016 = controller 1, 0x4017 = controller 2
    if (address === 0x4016) {
      const v = this.latch[0] & 1
      this.latch[0] >>>= 1
      return v
    } else {
      const v = this.latch[1] & 1
      this.latch[1] >>>= 1
      return v
    }
  }

  write(address, value) {
    this.strobe = (value & 1) > 0
    if (this.strobe) this.poll()
  }
}
