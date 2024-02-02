export class BufferMapper {
  data = []

  read(address) {
    return this.data[address] ?? 0
  }

  write(address, value) {
    this.data[address] = value
  }
}
