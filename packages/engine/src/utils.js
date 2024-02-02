export function uint8add(...args) {
  const [value, overflow] = args.reduce(
    (p, v) => {
      if (Array.isArray(v)) return [p[0] + v[0], p[1] || v[1]]
      else return [p[0] + v, p[1]]
    },
    [0, false],
  )

  return [fixRange8(value), overflow || value > 255]
}

export function uint8sub(...args) {
  const [value, overflow] = args.reduce((p, v) => {
    if (p === null) return Array.isArray(v) ? v : [v, false]
    else if (Array.isArray(v)) return [p[0] - v[0], p[1] || v[1]]
    else return [p[0] - v, p[1]]
  }, null)

  return [fixRange8(value), overflow || value < 0]
}

export function fixRange8(value) {
  if (value >= 0x100) {
    return value % 0x100
  } else if (value < 0) {
    return (0x100 + (value % 0x100)) & 0xff
  } else {
    return value
  }
}

export function fixRange16(value) {
  if (value >= 0x10000) {
    return value % 0x10000
  } else if (value < 0) {
    return (0x10000 + (value % 0x10000)) & 0xffff
  } else {
    return value
  }
}

export function inRange(num, min, max) {
  return num >= min && num <= max
}
