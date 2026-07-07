import Foundation

public struct JobFileSummary: Identifiable, Hashable, Sendable {
    public var id: URL { fileURL }
    public var fileURL: URL
    public var fileName: String
    public var menuTitle: String
    public var location: String?
    public var isSelected: Bool

    public init(fileURL: URL, isSelected: Bool = false) {
        self.fileURL = fileURL
        self.fileName = fileURL.lastPathComponent
        self.menuTitle = NativeFormatters.jobFileMenuTitle(fileURL)
        self.location = NativeFormatters.jobFileLocation(fileURL)
        self.isSelected = isSelected
    }
}
