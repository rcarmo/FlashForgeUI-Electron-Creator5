import Darwin
import Foundation

public final class SocketDiscoveryTransport: DiscoveryTransport {
    private let parser: DiscoveryResponseParser
    private let multicastAddress = "225.0.0.9"

    public init(parser: DiscoveryResponseParser = DiscoveryResponseParser()) {
        self.parser = parser
    }

    public func discover(options: NativePrinterDiscoveryOptions) async throws -> [DiscoveredPrinterResponse] {
        try await Task.detached(priority: .userInitiated) {
            try self.discoverSynchronously(options: options)
        }.value
    }

    private func discoverSynchronously(options: NativePrinterDiscoveryOptions) throws -> [DiscoveredPrinterResponse] {
        let socketDescriptor = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard socketDescriptor >= 0 else {
            throw POSIXError(.init(rawValue: errno) ?? .EIO)
        }
        defer { close(socketDescriptor) }

        var reuse: Int32 = 1
        setsockopt(socketDescriptor, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(socketDescriptor, SOL_SOCKET, SO_BROADCAST, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var localAddress = sockaddr_in()
        localAddress.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        localAddress.sin_family = sa_family_t(AF_INET)
        localAddress.sin_port = 0
        localAddress.sin_addr = in_addr(s_addr: INADDR_ANY.bigEndian)

        let bindResult = withUnsafePointer(to: &localAddress) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(socketDescriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            throw POSIXError(.init(rawValue: errno) ?? .EIO)
        }

        if options.useMulticast {
            joinMulticastGroup(socketDescriptor)
        }

        sendDiscoveryPackets(socketDescriptor: socketDescriptor, options: options)
        return receiveResponses(socketDescriptor: socketDescriptor, options: options)
    }

    private func joinMulticastGroup(_ socketDescriptor: Int32) {
        var membership = ip_mreq()
        membership.imr_multiaddr.s_addr = inet_addr(multicastAddress)
        membership.imr_interface.s_addr = INADDR_ANY.bigEndian
        setsockopt(socketDescriptor, IPPROTO_IP, IP_ADD_MEMBERSHIP, &membership, socklen_t(MemoryLayout<ip_mreq>.size))
    }

    private func sendDiscoveryPackets(socketDescriptor: Int32, options: NativePrinterDiscoveryOptions) {
        if options.useMulticast {
            for port in options.ports where port == 8899 || port == 19000 {
                sendEmptyPacket(socketDescriptor: socketDescriptor, address: multicastAddress, port: port)
            }
        }

        if options.useBroadcast {
            var addresses = broadcastAddresses()
            addresses.append("255.255.255.255")

            for address in Set(addresses) {
                for port in options.ports {
                    if port == 48899 || address == "255.255.255.255" {
                        sendEmptyPacket(socketDescriptor: socketDescriptor, address: address, port: port)
                    }
                }
            }
        }
    }

    private func sendEmptyPacket(socketDescriptor: Int32, address: String, port: UInt16) {
        var remoteAddress = sockaddr_in()
        remoteAddress.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        remoteAddress.sin_family = sa_family_t(AF_INET)
        remoteAddress.sin_port = port.bigEndian
        remoteAddress.sin_addr.s_addr = inet_addr(address)

        withUnsafePointer(to: &remoteAddress) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                _ = sendto(socketDescriptor, nil, 0, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
    }

    private func receiveResponses(
        socketDescriptor: Int32,
        options: NativePrinterDiscoveryOptions
    ) -> [DiscoveredPrinterResponse] {
        let deadline = Date().addingTimeInterval(options.timeout)
        var idleDeadline = Date().addingTimeInterval(options.idleTimeout)
        var discovered: [DiscoveredPrinterResponse] = []

        while Date() < deadline && Date() < idleDeadline {
            var readSet = fd_set()
            fdZero(&readSet)
            fdSet(socketDescriptor, set: &readSet)

            var timeout = timeval(tv_sec: 0, tv_usec: 100_000)
            let result = select(socketDescriptor + 1, &readSet, nil, nil, &timeout)
            if result <= 0 {
                continue
            }

            var buffer = [UInt8](repeating: 0, count: 512)
            var remoteAddress = sockaddr_in()
            var remoteLength = socklen_t(MemoryLayout<sockaddr_in>.size)
            let byteCount = withUnsafeMutablePointer(to: &remoteAddress) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    recvfrom(socketDescriptor, &buffer, buffer.count, 0, $0, &remoteLength)
                }
            }

            guard byteCount > 0 else {
                continue
            }

            let data = Data(buffer.prefix(Int(byteCount)))
            let remoteIP = String(cString: inet_ntoa(remoteAddress.sin_addr))
            if let printer = parser.parse(data: data, remoteInfo: DiscoveryRemoteInfo(address: remoteIP)) {
                discovered.append(printer)
                idleDeadline = Date().addingTimeInterval(options.idleTimeout)
            }
        }

        return discovered
    }

    private func broadcastAddresses() -> [String] {
        var addresses: [String] = []
        var interfacesPointer: UnsafeMutablePointer<ifaddrs>?

        guard getifaddrs(&interfacesPointer) == 0, let firstInterface = interfacesPointer else {
            return addresses
        }
        defer { freeifaddrs(interfacesPointer) }

        var current: UnsafeMutablePointer<ifaddrs>? = firstInterface
        while let interface = current {
            defer { current = interface.pointee.ifa_next }

            let flags = Int32(interface.pointee.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0 else {
                continue
            }

            guard
                let addressPointer = interface.pointee.ifa_addr,
                let netmaskPointer = interface.pointee.ifa_netmask,
                addressPointer.pointee.sa_family == UInt8(AF_INET)
            else {
                continue
            }

            let address = addressPointer.withSockaddrIn { $0.sin_addr.s_addr }
            let netmask = netmaskPointer.withSockaddrIn { $0.sin_addr.s_addr }
            let broadcast = address | ~netmask
            addresses.append(ipv4String(fromNetworkOrder: broadcast))
        }

        return addresses
    }

    private func ipv4String(fromNetworkOrder address: in_addr_t) -> String {
        let addr = in_addr(s_addr: address)
        return String(cString: inet_ntoa(addr))
    }
}

private func fdZero(_ set: inout fd_set) {
    set.fds_bits = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
}

private func fdSet(_ fd: Int32, set: inout fd_set) {
    let bitsPerMask = MemoryLayout<Int32>.size * 8
    let intOffset = Int(fd) / bitsPerMask
    let bitOffset = Int(fd) % bitsPerMask
    let mask = Int32(1 << bitOffset)
    withUnsafeMutablePointer(to: &set.fds_bits) {
        $0.withMemoryRebound(to: Int32.self, capacity: 32) {
            $0[intOffset] |= mask
        }
    }
}

private extension UnsafePointer<sockaddr> {
    func withSockaddrIn<T>(_ body: (sockaddr_in) -> T) -> T {
        withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
            body($0.pointee)
        }
    }
}

private extension UnsafeMutablePointer<sockaddr> {
    func withSockaddrIn<T>(_ body: (sockaddr_in) -> T) -> T {
        withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
            body($0.pointee)
        }
    }
}
