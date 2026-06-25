import CoreGraphics
import Foundation

// List on-screen, normal app windows front→back with size and position
// (top-left coords). Mirrors how boxed sees "what's actually visible".
let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
var i = 0
for w in list {
  guard let layer = w[kCGWindowLayer as String] as? Int, layer == 0,
    let owner = w[kCGWindowOwnerName as String] as? String,
    let dict = w[kCGWindowBounds as String] as? NSDictionary,
    let f = CGRect(dictionaryRepresentation: dict as CFDictionary), f.width > 50, f.height > 50
  else { continue }
  print("  \(i) (front→back): \(owner)  \(Int(f.width))x\(Int(f.height)) @(\(Int(f.minX)),\(Int(f.minY)))")
  i += 1
}
if i == 0 { print("  (no normal windows on this Space)") }
