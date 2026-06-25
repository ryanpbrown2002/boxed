import AppKit

// List the displays and their frames (Cocoa, bottom-left coords) — use to pick a
// point to warp the cursor to before organizing a specific display.
for (i, s) in NSScreen.screens.enumerated() {
  let f = s.frame
  let v = s.visibleFrame
  print(
    "screen \(i): frame=(\(Int(f.minX)),\(Int(f.minY)) \(Int(f.width))x\(Int(f.height))) "
      + "visible=(\(Int(v.minX)),\(Int(v.minY)) \(Int(v.width))x\(Int(v.height)))")
}
