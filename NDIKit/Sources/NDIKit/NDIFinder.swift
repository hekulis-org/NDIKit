import NDIKitC

/// Discovers NDI sources available on the network.
///
/// Use an `NDIFinder` to scan for NDI senders on the local network.
///
/// ```swift
/// guard let finder = NDIFinder() else { return }
/// finder.waitForSources(timeout: 5000)
/// let sources = finder.sources
/// ```
///
/// - Note: On iOS, NDI discovery requires Bonjour (`_ndi._tcp`)
///   and Local Network permission.
public final class NDIFinder: @unchecked Sendable {
    private let instance: NDIlib_find_instance_t

    /// Configuration options for creating an ``NDIFinder``.
    public struct Configuration: Sendable {
        /// A Boolean value that indicates whether sources running on the
        /// local machine should be included in the results.
        public var showLocalSources: Bool

        /// The NDI groups to search for sources in.
        ///
        /// Pass `nil` to search the default groups.
        public var groups: String?

        /// Additional IP addresses to query for sources, as a
        /// comma-separated string.
        public var extraIPs: String?

        /// Creates a finder configuration.
        ///
        /// - Parameters:
        ///   - showLocalSources: Whether to include local sources.
        ///     Defaults to `true`.
        ///   - groups: Groups to search. `nil` uses the default groups.
        ///   - extraIPs: Additional IP addresses to query, comma-separated.
        public init(
            showLocalSources: Bool = true,
            groups: String? = nil,
            extraIPs: String? = nil
        ) {
            self.showLocalSources = showLocalSources
            self.groups = groups
            self.extraIPs = extraIPs
        }
    }

    /// Creates a finder with the default configuration.
    ///
    /// - Returns: A new finder, or `nil` if the NDI library could not
    ///   create the finder instance.
    public convenience init?() {
        self.init(configuration: Configuration())
    }

    /// Creates a finder with the specified configuration.
    ///
    /// - Parameter configuration: The configuration to use.
    /// - Returns: A new finder, or `nil` if the NDI library could not
    ///   create the finder instance.
    public init?(configuration: Configuration) {
        let instance: NDIlib_find_instance_t? = configuration.groups.withOptionalCString { groupsPtr in
            configuration.extraIPs.withOptionalCString { extraIPsPtr in
                var settings = NDIlib_find_create_t()
                settings.show_local_sources = configuration.showLocalSources
                settings.p_groups = groupsPtr
                settings.p_extra_ips = extraIPsPtr
                return NDIlib_find_create_v2(&settings)
            }
        }

        guard let instance else { return nil }
        self.instance = instance
    }

    deinit {
        NDIlib_find_destroy(instance)
    }

    /// The current list of discovered NDI sources.
    public var sources: [NDISource] {
        var count: UInt32 = 0
        guard let sourcesPtr = NDIlib_find_get_current_sources(instance, &count) else {
            return []
        }
        return (0..<Int(count)).map { NDISource(sourcesPtr[$0]) }
    }

    /// Waits until the list of sources changes or the timeout expires.
    ///
    /// - Parameter timeout: The maximum time to wait, in milliseconds.
    /// - Returns: `true` if the source list changed, `false` if the call
    ///   timed out.
    @discardableResult
    public func waitForSources(timeout: UInt32) -> Bool {
        NDIlib_find_wait_for_sources(instance, timeout)
    }
}

// MARK: - Optional String Helper

extension Optional where Wrapped == String {
    func withOptionalCString<T>(_ body: (UnsafePointer<CChar>?) -> T) -> T {
        switch self {
        case .some(let string):
            return string.withCString { body($0) }
        case .none:
            return body(nil)
        }
    }
}
