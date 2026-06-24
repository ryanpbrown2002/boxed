import { useCallback, useEffect, useRef, useState } from 'react'
import { normalizeUrl } from './lib/url'
import { trackTemplate, resizePair, cellLine, gutterLine } from './lib/layout'

const STORE_KEY = 'boxed.workspace.v1'

type Tabs = Record<string, string>

interface Workspace {
  cols: number[]
  rows: number[]
  tabs: Tabs
}

const DEFAULT: Workspace = { cols: [1, 1], rows: [1], tabs: {} }

function load(): Workspace {
  try {
    const raw = localStorage.getItem(STORE_KEY)
    if (raw) {
      const s = JSON.parse(raw) as Partial<Workspace>
      if (Array.isArray(s.cols) && Array.isArray(s.rows)) {
        return { cols: s.cols, rows: s.rows, tabs: s.tabs ?? {} }
      }
    }
  } catch {
    /* ignore */
  }
  return structuredClone(DEFAULT)
}

const PRESETS: { label: string; cols: number; rows: number; cells: number }[] = [
  { label: 'Single', cols: 1, rows: 1, cells: 1 },
  { label: 'Side by side', cols: 2, rows: 1, cells: 2 },
  { label: 'Stacked', cols: 1, rows: 2, cells: 2 },
  { label: 'Three across', cols: 3, rows: 1, cells: 3 },
  { label: 'Quad', cols: 2, rows: 2, cells: 4 }
]

export default function App(): JSX.Element {
  const initial = useRef(load())
  const [cols, setCols] = useState<number[]>(initial.current.cols)
  const [rows, setRows] = useState<number[]>(initial.current.rows)
  const [tabs, setTabs] = useState<Tabs>(initial.current.tabs)
  const [focus, setFocus] = useState<string | null>(null)
  const [pinned, setPinned] = useState(true)
  const [toast, setToast] = useState<string | null>(null)
  const canvasRef = useRef<HTMLDivElement>(null)
  const toastTimer = useRef<ReturnType<typeof setTimeout>>()

  useEffect(() => {
    window.boxed?.isPinned().then(setPinned)
  }, [])

  const flash = useCallback((msg: string) => {
    setToast(msg)
    clearTimeout(toastTimer.current)
    toastTimer.current = setTimeout(() => setToast(null), 1900)
  }, [])

  const applyPreset = (c: number, r: number): void => {
    setCols(Array(c).fill(1))
    setRows(Array(r).fill(1))
  }

  const setTab = (key: string, url: string): void => {
    setTabs((t) => {
      const next = { ...t }
      if (url) next[key] = url
      else delete next[key]
      return next
    })
  }

  const save = (): void => {
    localStorage.setItem(STORE_KEY, JSON.stringify({ cols, rows, tabs }))
    flash('workspace saved')
  }

  const evenOut = (): void => {
    setCols((c) => c.map(() => 1))
    setRows((r) => r.map(() => 1))
    flash('sizes evened out')
  }

  const togglePin = async (): Promise<void> => {
    const next = await window.boxed?.togglePin()
    setPinned(next ?? !pinned)
  }

  // ── gutter drag ────────────────────────────────────────────────────────
  const startResize = (
    e: React.PointerEvent,
    axis: 'col' | 'row',
    idx: number
  ): void => {
    e.preventDefault()
    const canvas = canvasRef.current
    if (!canvas) return
    const rect = canvas.getBoundingClientRect()
    const isCol = axis === 'col'
    const arr = isCol ? cols : rows
    const total = isCol ? rect.width : rect.height
    const start = isCol ? e.clientX : e.clientY
    const frSum = arr.reduce((s, v) => s + v, 0)
    const pxPerFr = total / frSum
    const base = arr.slice()

    document.body.classList.add('resizing', isCol ? 'cols' : 'rows')

    const move = (ev: PointerEvent): void => {
      const pos = isCol ? ev.clientX : ev.clientY
      const deltaFr = (pos - start) / pxPerFr
      const next = resizePair(base, idx, deltaFr)
      if (isCol) setCols(next)
      else setRows(next)
    }
    const up = (): void => {
      document.body.classList.remove('resizing', 'cols', 'rows')
      window.removeEventListener('pointermove', move)
      window.removeEventListener('pointerup', up)
    }
    window.addEventListener('pointermove', move)
    window.addEventListener('pointerup', up)
  }

  const C = cols.length
  const R = rows.length
  const isPreset = (c: number, r: number): boolean =>
    C === c && R === r && cols.every((f) => f === cols[0]) && rows.every((f) => f === rows[0])

  return (
    <div className="app">
      <header className="shelf">
        <div className="brand">
          <span className="mark" />
          <h1>boxed</h1>
        </div>

        <span className="divider" />

        <div className="group">
          <span className="lbl">layout</span>
          {PRESETS.map((p) => (
            <button
              key={p.label}
              className={`preset cells-${p.cells} ${isPreset(p.cols, p.rows) ? 'on' : ''}`}
              title={p.label}
              onClick={() => applyPreset(p.cols, p.rows)}
            >
              {Array.from({ length: p.cells }).map((_, i) => (
                <i key={i} />
              ))}
            </button>
          ))}
        </div>

        <span className="divider" />

        <div className="group">
          <span className="lbl">grid</span>
          <button className="btn" onClick={() => setCols((c) => [...c, 1])}>
            col +
          </button>
          <button className="btn" onClick={() => setRows((r) => [...r, 1])}>
            row +
          </button>
        </div>

        <span className="spacer" />
        <span className="hint">drag the green gutters to resize · ⌘⇧B to summon</span>
        <span className="divider" />

        <button className="btn" onClick={evenOut} title="Reset sizes">
          even
        </button>
        <button className="btn accent" onClick={save} title="Save workspace">
          save
        </button>

        <span className="divider" />

        <div className="winctl">
          <button
            className={`ico ${pinned ? 'pinned' : ''}`}
            onClick={togglePin}
            title={pinned ? 'Unpin (allow other windows on top)' : 'Pin always-on-top'}
          >
            ⇧
          </button>
          <button className="ico" onClick={() => window.boxed?.hide()} title="Dismiss to menubar">
            ✕
          </button>
        </div>
      </header>

      <main
        ref={canvasRef}
        className="canvas"
        style={{
          gridTemplateColumns: trackTemplate(cols, `var(--gutter)`),
          gridTemplateRows: trackTemplate(rows, `var(--gutter)`)
        }}
      >
        {rows.map((_, r) =>
          cols.map((__, c) => {
            const key = `${r}-${c}`
            return (
              <Box
                key={key}
                cellKey={key}
                col={c}
                row={r}
                url={tabs[key] ?? ''}
                focused={focus === key}
                onFocus={() => setFocus(key)}
                onSetUrl={(u) => setTab(key, u)}
              />
            )
          })
        )}

        {cols.slice(0, -1).map((_, c) => (
          <div
            key={`gc-${c}`}
            className="gutter col"
            style={{ gridColumn: gutterLine(c), gridRow: '1 / -1' }}
            onPointerDown={(e) => startResize(e, 'col', c)}
          >
            <span className="grip" />
          </div>
        ))}
        {rows.slice(0, -1).map((_, r) => (
          <div
            key={`gr-${r}`}
            className="gutter row"
            style={{ gridRow: gutterLine(r), gridColumn: '1 / -1' }}
            onPointerDown={(e) => startResize(e, 'row', r)}
          >
            <span className="grip" />
          </div>
        ))}
      </main>

      <div className={`toast ${toast ? 'show' : ''}`}>{toast}</div>
    </div>
  )
}

interface BoxProps {
  cellKey: string
  col: number
  row: number
  url: string
  focused: boolean
  onFocus: () => void
  onSetUrl: (url: string) => void
}

function Box({ col, row, url, focused, onFocus, onSetUrl }: BoxProps): JSX.Element {
  const [draft, setDraft] = useState(url)
  const viewRef = useRef<HTMLElement>(null)

  useEffect(() => setDraft(url), [url])

  const commit = (): void => onSetUrl(normalizeUrl(draft))
  const reload = (): void => {
    // @ts-expect-error webview runtime method
    viewRef.current?.reload?.()
  }
  const openExternal = (): void => {
    const u = normalizeUrl(draft)
    if (u) window.open(u, '_blank')
  }

  return (
    <section
      className={`box ${url ? '' : 'empty'} ${focused ? 'focus' : ''}`}
      style={{ gridColumn: cellLine(col), gridRow: cellLine(row) }}
      onPointerDownCapture={onFocus}
    >
      <div className="rail">
        <span className="dot" />
        <input
          className="url"
          spellCheck={false}
          placeholder="enter a url…  (youtube.com, a doc, anything)"
          value={draft}
          onChange={(e) => setDraft(e.target.value)}
          onFocus={onFocus}
          onKeyDown={(e) => {
            if (e.key === 'Enter') commit()
            if (e.key === 'Escape') (e.target as HTMLInputElement).blur()
          }}
        />
        <button className="rico" title="Reload" onClick={reload}>
          ⟳
        </button>
        <button className="rico" title="Open in real browser" onClick={openExternal}>
          ↗
        </button>
        <button className="rico danger" title="Clear box" onClick={() => onSetUrl('')}>
          ✕
        </button>
      </div>
      <div className="framewrap">
        {url ? (
          <webview ref={viewRef} src={url} partition="persist:boxed" allowpopups="true" />
        ) : (
          <div className="placeholder">
            <span className="glyph" />
            <p>empty box</p>
            <span className="sub">type a url in the rail above</span>
          </div>
        )}
      </div>
    </section>
  )
}
