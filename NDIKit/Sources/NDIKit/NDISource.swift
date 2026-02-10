import NDIKitC

/// An NDI source discovered on the network.
///
/// Sources are typically obtained from ``NDIFinder/sources`` and then
/// passed to ``NDIReceiver/connect(to:)`` to begin receiving.
public struct NDISource: Sendable, Hashable, Identifiable {
    /// The name of the source, typically in the format
    /// `"MACHINE_NAME (SOURCE_NAME)"`.
    public let name: String

    /// The URL address used to connect to this source, or `nil` if unknown.
    public let urlAddress: String?

    /// The stable identity of this source, derived from its ``name``.
    public var id: String { name }

    /// Create a source from a C NDIlib_source_t structure.
    init(_ source: NDIlib_source_t) {
        self.name = source.p_ndi_name.map { String(cString: $0) } ?? ""
        self.urlAddress = source.p_url_address.map { String(cString: $0) }
    }

    /// Creates an NDI source with the given name and optional URL.
    ///
    /// - Parameters:
    ///   - name: The display name of the source.
    ///   - urlAddress: The URL address used to connect, or `nil` to
    ///     let the SDK resolve it automatically.
    public init(name: String, urlAddress: String? = nil) {
        self.name = name
        self.urlAddress = urlAddress
    }

    /// Convert back to a C structure for use with NDI APIs.
    /// The closure receives the C structure with valid pointers only for the duration of the call.
    func withCSource<T>(_ body: (NDIlib_source_t) -> T) -> T {
        name.withCString { namePtr in
            if let url = urlAddress {
                return url.withCString { urlPtr in
                    var source = NDIlib_source_t()
                    source.p_ndi_name = namePtr
                    source.p_url_address = urlPtr
                    return body(source)
                }
            } else {
                var source = NDIlib_source_t()
                source.p_ndi_name = namePtr
                source.p_url_address = nil
                return body(source)
            }
        }
    }
}
