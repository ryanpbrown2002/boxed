import { join } from 'path'
import { app, BrowserWindow, Tray, Menu, globalShortcut, nativeImage, ipcMain } from 'electron'

let win: BrowserWindow | null = null
let tray: Tray | null = null

const isDev = !app.isPackaged

/** The floating workspace window — small, frameless, always-on-top, blurred. */
function createWindow(): void {
  win = new BrowserWindow({
    width: 760,
    height: 480,
    minWidth: 360,
    minHeight: 240,
    show: false,
    frame: false,
    transparent: process.platform === 'darwin',
    vibrancy: 'under-window',
    visualEffectState: 'active',
    roundedCorners: true,
    alwaysOnTop: true,
    fullscreenable: false,
    skipTaskbar: true,
    titleBarStyle: 'hidden',
    webPreferences: {
      preload: join(__dirname, '../preload/index.js'),
      sandbox: false,
      contextIsolation: true,
      nodeIntegration: false,
      webviewTag: true // each tab is a real, isolated browser process
    }
  })

  // Float above other apps on every space, including over fullscreen apps.
  win.setAlwaysOnTop(true, 'floating')
  win.setVisibleOnAllWorkspaces(true, { visibleOnFullScreen: true })

  win.once('ready-to-show', () => win?.show())
  win.on('closed', () => {
    win = null
  })

  if (isDev && process.env['ELECTRON_RENDERER_URL']) {
    win.loadURL(process.env['ELECTRON_RENDERER_URL'])
  } else {
    win.loadFile(join(__dirname, '../renderer/index.html'))
  }
}

function toggleWindow(): void {
  if (!win) {
    createWindow()
    return
  }
  if (win.isVisible()) {
    win.hide()
  } else {
    win.show()
    win.focus()
  }
}

/** A menubar-only presence: no dock icon, summon/dismiss from the tray or hotkey. */
function createTray(): void {
  // A text-only menubar item — no icon asset needed for v0.
  tray = new Tray(nativeImage.createEmpty())
  tray.setTitle('▣')
  tray.setToolTip('boxed')

  const menu = Menu.buildFromTemplate([
    { label: 'Show / Hide boxed', accelerator: 'CmdOrCtrl+Shift+B', click: toggleWindow },
    { type: 'separator' },
    { label: 'Quit boxed', role: 'quit' }
  ])
  tray.setContextMenu(menu)
  tray.on('click', toggleWindow)
}

app.whenReady().then(() => {
  // Menubar app: hide the dock icon on macOS.
  if (process.platform === 'darwin') app.dock?.hide()

  createWindow()
  createTray()

  globalShortcut.register('CommandOrControl+Shift+B', toggleWindow)

  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) createWindow()
  })
})

// Stay alive in the tray when the window is closed.
app.on('window-all-closed', () => {
  /* keep running */
})

app.on('will-quit', () => globalShortcut.unregisterAll())

// ── window controls exposed to the renderer ─────────────────────────────
ipcMain.on('win:hide', () => win?.hide())

ipcMain.handle('win:togglePin', () => {
  if (!win) return true
  const next = !win.isAlwaysOnTop()
  win.setAlwaysOnTop(next, 'floating')
  return next
})

ipcMain.handle('win:isPinned', () => win?.isAlwaysOnTop() ?? true)
