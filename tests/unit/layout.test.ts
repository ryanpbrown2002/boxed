import { describe, it, expect } from 'vitest'
import { trackTemplate, resizePair, cellLine, gutterLine } from '../../src/renderer/src/lib/layout'

describe('trackTemplate', () => {
  it('interleaves gutters between fr tracks', () => {
    expect(trackTemplate([1, 1], '7px')).toBe('1fr 7px 1fr')
    expect(trackTemplate([1], '7px')).toBe('1fr')
    expect(trackTemplate([1, 2, 1], 'var(--g)')).toBe('1fr var(--g) 2fr var(--g) 1fr')
  })
})

describe('resizePair', () => {
  it('keeps the pair sum constant', () => {
    const next = resizePair([1, 1], 0, 0.3)
    expect(next[0] + next[1]).toBeCloseTo(2)
    expect(next[0]).toBeCloseTo(1.3)
    expect(next[1]).toBeCloseTo(0.7)
  })

  it('clamps to the minimum ratio', () => {
    const next = resizePair([1, 1], 0, 5) // way past the edge
    expect(next[0]).toBeCloseTo(2 * 0.92)
    expect(next[1]).toBeCloseTo(2 * 0.08)
  })

  it('does not mutate the input', () => {
    const input = [1, 1]
    resizePair(input, 0, 0.5)
    expect(input).toEqual([1, 1])
  })
})

describe('grid line helpers', () => {
  it('maps cells and gutters onto interleaved tracks', () => {
    expect([cellLine(0), cellLine(1), cellLine(2)]).toEqual([1, 3, 5])
    expect([gutterLine(0), gutterLine(1)]).toEqual([2, 4])
  })
})
