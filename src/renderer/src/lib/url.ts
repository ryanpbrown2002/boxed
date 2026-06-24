/**
 * Turn whatever the user typed into a loadable URL.
 * - full URLs pass through
 * - bare domains get https://
 * - anything else becomes a search query
 */
export function normalizeUrl(input: string): string {
  const v = input.trim()
  if (!v) return ''
  if (/^https?:\/\//i.test(v)) return v
  if (/^[\w-]+(\.[\w-]+)+/.test(v)) return `https://${v}`
  return `https://duckduckgo.com/?q=${encodeURIComponent(v)}`
}
