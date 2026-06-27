import AppKit

// List the displays and their frames. Default output is Cocoa (bottom-left)
// coords — use to pick a point to warp the cursor to before organizing a display.
//
// With `--cg`, print each display's frame in CG global *top-left* coords (the
// same space `winz` and the cursor warp use), one machine-parseable line per
// display: `cg <index> <primary|secondary> <x> <y> <w> <h>`. The e2e suite uses
// this to tell which display a window landed on.
let primaryH = NSScreen.screens.first?.frame.height ?? 0

if CommandLine.arguments.contains("--cg") {
  for (i, s) in NSScreen.screens.enumerated() {
    let f = s.frame
    // Cocoa bottom-left → CG top-left: y flips about the primary display's height.
    let top = primaryH - (f.minY + f.height)
    let tag = i == 0 ? "primary" : "secondary"
    print("cg \(i) \(tag) \(Int(f.minX)) \(Int(top)) \(Int(f.width)) \(Int(f.height))")
  }
} else {
  for (i, s) in NSScreen.screens.enumerated() {
    let f = s.frame
    let v = s.visibleFrame
    print(
      "screen \(i): frame=(\(Int(f.minX)),\(Int(f.minY)) \(Int(f.width))x\(Int(f.height))) "
        + "visible=(\(Int(v.minX)),\(Int(v.minY)) \(Int(v.width))x\(Int(v.height)))")
  }
}
