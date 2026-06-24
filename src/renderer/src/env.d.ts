/// <reference types="vite/client" />
import type { DetailedHTMLProps, HTMLAttributes } from 'react'

// Electron's <webview> tag isn't in the standard JSX intrinsics — declare it.
declare module 'react' {
  namespace JSX {
    interface IntrinsicElements {
      webview: DetailedHTMLProps<HTMLAttributes<HTMLElement>, HTMLElement> & {
        src?: string
        partition?: string
        allowpopups?: string
        useragent?: string
      }
    }
  }
}
