import Foundation

public protocol PrinterBootstrapClient {
    func fetchPrinterInfo(host: String, port: UInt16) async throws -> PrinterInfo
}
