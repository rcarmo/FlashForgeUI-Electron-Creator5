import SwiftUI

public struct CameraPreviewView: View {
    @Environment(\.openURL) private var openURL

    private let config: CameraStreamConfig
    private let onOpenStream: (URL) -> Void

    public init(config: CameraStreamConfig, onOpenStream: @escaping (URL) -> Void = { _ in }) {
        self.config = config
        self.onOpenStream = onOpenStream
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Camera", systemImage: "video")
                    .font(.title2.weight(.semibold))

                Spacer()

                Text(config.sourceLabel)
                    .foregroundStyle(.secondary)

                if let streamURL = config.streamURL, config.isAvailable {
                    Button {
                        open(streamURL)
                    } label: {
                        Label("Open", systemImage: "arrow.up.forward.app")
                    }
                    .help("Open camera stream")
                }
            }

            content
                .frame(maxWidth: .infinity)
                .frame(height: 260)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var content: some View {
        if let streamURL = config.streamURL, config.isAvailable {
            if config.canRenderInline {
                CameraStreamWebView(url: streamURL)
                    .overlay(alignment: .bottomLeading) {
                        streamBadge(streamURL: streamURL)
                    }
            } else {
                fallbackContent(
                    title: config.streamType == .rtsp ? "RTSP Stream" : "External Stream",
                    message: streamURL.absoluteString,
                    streamURL: streamURL
                )
            }
        } else {
            unavailableContent
        }
    }

    private var unavailableContent: some View {
        VStack(spacing: 10) {
            Image(systemName: "video.slash")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(config.unavailableReason ?? "Camera unavailable")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.quaternary.opacity(0.35))
    }

    private func fallbackContent(title: String, message: String, streamURL: URL) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "video")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(message)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Button {
                open(streamURL)
            } label: {
                Label("Open Stream", systemImage: "arrow.up.forward.app")
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.quaternary.opacity(0.35))
    }

    private func open(_ streamURL: URL) {
        openURL(streamURL)
        onOpenStream(streamURL)
    }

    private func streamBadge(streamURL: URL) -> some View {
        Text(streamURL.absoluteString)
            .font(.caption)
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(.regularMaterial, in: Capsule())
            .padding(10)
    }
}

private extension CameraStreamConfig {
    var canRenderInline: Bool {
        guard streamType == .mjpeg,
              let scheme = streamURL?.scheme?.lowercased() else {
            return false
        }
        return scheme == "http" || scheme == "https"
    }

    var sourceLabel: String {
        switch sourceType {
        case .custom:
            "Custom"
        case .oem:
            "OEM"
        case .intelligentFallback:
            "Fallback"
        case .none:
            "Unavailable"
        }
    }
}
