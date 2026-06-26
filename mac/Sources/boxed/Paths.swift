import Foundation

/// File locations for boxed's runtime files. These live in the **per-user** temp
/// directory (`NSTemporaryDirectory()` → `/var/folders/.../T/`, mode 0700 and owned
/// by the user) rather than the world-writable `/tmp`, so other local users can't
/// read the log or drive the (debug-only) command hook.
enum Paths {
  static func temp(_ name: String) -> String {
    (NSTemporaryDirectory() as NSString).appendingPathComponent(name)
  }
}
