/** Build a CSS grid track string with fixed-width gutters interleaved between fr tracks. */
export function trackTemplate(fr: number[], gutter: string): string {
  return fr.map((f) => `${f}fr`).reduce((acc, f, i) => (i ? `${acc} ${gutter} ${f}` : f), '')
}

/**
 * Resize two adjacent tracks by `deltaFr`, keeping their combined size constant
 * and clamping each to a minimum ratio of the pair. Returns a new array.
 */
export function resizePair(fr: number[], idx: number, deltaFr: number, minRatio = 0.08): number[] {
  const a0 = fr[idx]
  const b0 = fr[idx + 1]
  const sum = a0 + b0
  const min = sum * minRatio
  let a = a0 + deltaFr
  let b = b0 - deltaFr
  if (a < min) {
    a = min
    b = sum - min
  }
  if (b < min) {
    b = min
    a = sum - min
  }
  const next = fr.slice()
  next[idx] = a
  next[idx + 1] = b
  return next
}

/** The 1-based grid line where cell `i` starts, given gutters live on even tracks. */
export function cellLine(i: number): number {
  return 2 * i + 1
}

/** The 1-based grid line of the gutter that follows cell `i`. */
export function gutterLine(i: number): number {
  return 2 * i + 2
}
