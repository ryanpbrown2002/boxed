import { describe, it, expect } from 'vitest'
import { normalizeUrl } from '../../src/renderer/src/lib/url'

describe('normalizeUrl', () => {
  it('passes through full http(s) urls', () => {
    expect(normalizeUrl('https://youtube.com')).toBe('https://youtube.com')
    expect(normalizeUrl('http://example.com/x')).toBe('http://example.com/x')
  })

  it('adds https to bare domains', () => {
    expect(normalizeUrl('youtube.com')).toBe('https://youtube.com')
    expect(normalizeUrl('mail.google.com/inbox')).toBe('https://mail.google.com/inbox')
  })

  it('searches anything that is not a url', () => {
    expect(normalizeUrl('claude code')).toBe('https://duckduckgo.com/?q=claude%20code')
  })

  it('trims and treats empty as empty', () => {
    expect(normalizeUrl('   ')).toBe('')
    expect(normalizeUrl('')).toBe('')
  })
})
