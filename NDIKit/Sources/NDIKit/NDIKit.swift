import NDIKitC

/// Main entry point for NDI functionality.
/// Call `initialize()` before using any NDI features and `destroy()` when done.
public enum NDI {

    /// Initialize the NDI library. Call this before using any other NDI functionality.
    /// - Returns: `true` if initialization succeeded, `false` if the CPU is not supported.
    @discardableResult
    public static func initialize() -> Bool {
        NDIlib_initialize()
    }

    /// Destroy the NDI library and release resources.
    /// Call this when you're done using NDI.
    public static func destroy() {
        NDIlib_destroy()
    }

    /// Get the version string of the NDI library.
    public static var version: String {
        guard let cString = NDIlib_version() else { return "unknown" }
        return String(cString: cString)
    }

    /// Check if the current CPU supports NDI.
    public static var isCPUSupported: Bool {
        NDIlib_is_supported_CPU()
    }
}
