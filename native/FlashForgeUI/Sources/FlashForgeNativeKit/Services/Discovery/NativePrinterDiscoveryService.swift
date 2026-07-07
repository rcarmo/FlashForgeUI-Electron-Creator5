import Foundation

public struct NativePrinterDiscoveryOptions: Sendable {
    public var timeout: TimeInterval
    public var idleTimeout: TimeInterval
    public var maxRetries: Int
    public var useMulticast: Bool
    public var useBroadcast: Bool
    public var ports: [UInt16]

    public init(
        timeout: TimeInterval = 5,
        idleTimeout: TimeInterval = 1.5,
        maxRetries: Int = 2,
        useMulticast: Bool = true,
        useBroadcast: Bool = true,
        ports: [UInt16] = [8899, 19000, 48899]
    ) {
        self.timeout = timeout
        self.idleTimeout = idleTimeout
        self.maxRetries = maxRetries
        self.useMulticast = useMulticast
        self.useBroadcast = useBroadcast
        self.ports = ports
    }
}

public protocol DiscoveryTransport {
    func discover(options: NativePrinterDiscoveryOptions) async throws -> [DiscoveredPrinterResponse]
}

public final class NativePrinterDiscoveryService: PrinterService {
    private let options: NativePrinterDiscoveryOptions
    private let transport: DiscoveryTransport

    public init(
        options: NativePrinterDiscoveryOptions = NativePrinterDiscoveryOptions(),
        transport: DiscoveryTransport = SocketDiscoveryTransport()
    ) {
        self.options = options
        self.transport = transport
    }

    public func discoverPrinters() async throws -> [PrinterSnapshot] {
        var discoveredByID: [String: DiscoveredPrinterResponse] = [:]

        for attempt in 0..<options.maxRetries {
            let responses = try await transport.discover(options: options)
            for response in responses {
                let existing = discoveredByID[response.id]
                if existing == nil || response.protocolFormat == .modern {
                    discoveredByID[response.id] = response
                }
            }

            if !discoveredByID.isEmpty || attempt == options.maxRetries - 1 {
                break
            }

            try await Task.sleep(nanoseconds: 1_000_000_000)
        }

        return discoveredByID.values
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            .map { $0.snapshot() }
    }
}
