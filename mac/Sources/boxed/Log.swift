import Foundation

/// Lightweight file logger. Writes to the per-user temp dir (and NSLog) so
/// diagnostics are readable regardless of how the app was launched — `open`-launched
/// bundles send stderr to /dev/null, which is why a file is needed. The log records
/// window titles, so it lives in the user-owned 0700 temp dir and is created 0600,
/// not the world-readable /tmp.
enum Log {
  private static let path = Paths.temp("boxed.log")

  static func write(_ message: String) {
    NSLog("boxed: %@", message)
    let line = "\(Date()) \(message)\n"
    guard let data = line.data(using: .utf8) else { return }
    let fm = FileManager.default
    guard fm.fileExists(atPath: path) else {
      fm.createFile(atPath: path, contents: data, attributes: [.posixPermissions: 0o600])
      return
    }
    if let handle = FileHandle(forWritingAtPath: path) {
      handle.seekToEndOfFile()
      handle.write(data)
      try? handle.close()
    }
  }
}
