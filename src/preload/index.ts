import { contextBridge, ipcRenderer } from 'electron'

/** The safe, minimal bridge the renderer is allowed to call. */
const boxed = {
  /** Hide the window (dismiss to tray). */
  hide: (): void => ipcRenderer.send('win:hide'),
  /** Toggle always-on-top. Resolves to the new pinned state. */
  togglePin: (): Promise<boolean> => ipcRenderer.invoke('win:togglePin'),
  /** Current always-on-top state. */
  isPinned: (): Promise<boolean> => ipcRenderer.invoke('win:isPinned'),
  platform: process.platform
}

contextBridge.exposeInMainWorld('boxed', boxed)

export type BoxedAPI = typeof boxed
