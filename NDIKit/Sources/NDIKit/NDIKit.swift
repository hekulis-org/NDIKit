import NDIKitC

/// Main entry point for the NDI library.
///
/// Call ``initialize()`` before using any NDI features and ``destroy()`` when
/// you are finished.
///
/// ```swift
/// NDI.initialize()
/// defer { NDI.destroy() }
/// // … use NDIFinder, NDISender, NDIReceiver, etc.
/// ```
public enum NDI {

    /// Initializes the NDI library.
    ///
    /// You must call this before using any other NDI functionality.
    ///
    /// - Returns: `true` if initialization succeeded, `false` if the CPU
    ///   is not supported.
    @discardableResult
    public static func initialize() -> Bool {
        NDIlib_initialize()
    }

    /// Destroys the NDI library and releases all associated resources.
    ///
    /// Call this when you are done using NDI.
    public static func destroy() {
        NDIlib_destroy()
    }

    /// The version string of the underlying NDI SDK.
    public static var version: String {
        guard let cString = NDIlib_version() else { return "unknown" }
        return String(cString: cString)
    }

    /// A Boolean value that indicates whether the current CPU supports NDI.
    public static var isCPUSupported: Bool {
        NDIlib_is_supported_CPU()
    }
}
