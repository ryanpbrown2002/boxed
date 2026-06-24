import Foundation

/// Lightweight file logger. Writes to /tmp/boxed.log (and NSLog) so diagnostics
/// are readable regardless of how the app was launched — `open`-launched bundles
/// send stderr to /dev/null, which is why a file is needed.
enum Log {
  private static let path = "/tmp/boxed.log"

  static func write(_ message: String) {
    NSLog("boxed: %@", message)
    let line = "\(Date()) \(message)\n"
    guard let data = line.data(using: .utf8) else { return }
    if FileManager.default.fileExists(atPath: path), let handle = FileHandle(forWritingAtPath: path) {
      handle.seekToEndOfFile()
      handle.write(data)
      try? handle.close()
    } else {
      try? data.write(to: URL(fileURLWithPath: path))
    }
  }
}
