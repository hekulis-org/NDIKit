import NDIKitC

/// Discovers NDI sources available on the network.
public final class NDIFinder: @unchecked Sendable {
    private let instance: NDIlib_find_instance_t

    /// Configuration options for creating a finder.
    public struct Configuration: Sendable {
        /// Whether to include sources running on the local machine.
        public var showLocalSources: Bool

        /// Groups to search for sources in. Nil means default groups.
        public var groups: String?

        /// Additional IP addresses to query for sources (comma-separated).
        public var extraIPs: String?

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

    /// Create a new finder with default configuration.
    public convenience init?() {
        self.init(configuration: Configuration())
    }

    /// Create a new finder with the specified configuration.
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

    /// Get the current list of discovered sources.
    public var sources: [NDISource] {
        var count: UInt32 = 0
        guard let sourcesPtr = NDIlib_find_get_current_sources(instance, &count) else {
            return []
        }
        return (0..<Int(count)).map { NDISource(sourcesPtr[$0]) }
    }

    /// Wait until the list of sources changes.
    /// - Parameter timeout: Maximum time to wait in milliseconds.
    /// - Returns: `true` if sources changed, `false` if timed out.
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
