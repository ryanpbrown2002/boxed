import type { BoxedAPI } from './index'

declare global {
  interface Window {
    boxed: BoxedAPI
  }
}

export {}
