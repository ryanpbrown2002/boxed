import CoreGraphics

// Move the cursor to a point in global (top-left) display coordinates, so the
// next `organize` targets that display. Usage: warp <x> <y>
let x = Double(CommandLine.arguments[1]) ?? 0
let y = Double(CommandLine.arguments[2]) ?? 0
CGWarpMouseCursorPosition(CGPoint(x: x, y: y))
CGAssociateMouseAndMouseCursorPosition(1)
