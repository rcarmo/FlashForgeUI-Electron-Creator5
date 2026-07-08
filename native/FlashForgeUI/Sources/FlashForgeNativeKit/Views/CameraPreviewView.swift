import SwiftUI

public struct CameraPreviewView: View {
    @Environment(\.openURL) private var openURL

    private let config: CameraStreamConfig
    private let isCameraEnabled: Bool
    private let recoveryReadiness: (CameraRecoveryAction) -> String?
    private let onCameraEnabledChange: (Bool) -> Void
    private let onOpenStream: (URL) -> Void
    private let onRecover: (CameraRecoveryAction) -> Void

    public init(
        config: CameraStreamConfig,
        isCameraEnabled: Bool = true,
        recoveryReadiness: @escaping (CameraRecoveryAction) -> String? = { _ in nil },
        onCameraEnabledChange: @escaping (Bool) -> Void = { _ in },
        onOpenStream: @escaping (URL) -> Void = { _ in },
        onRecover: @escaping (CameraRecoveryAction) -> Void = { _ in }
    ) {
        self.config = config
        self.isCameraEnabled = isCameraEnabled
        self.recoveryReadiness = recoveryReadiness
        self.onCameraEnabledChange = onCameraEnabledChange
        self.onOpenStream = onOpenStream
        self.onRecover = onRecover
    }

    public var body: some View {
        ZStack(alignment: .topTrailing) {
            content
                .frame(maxWidth: .infinity)
                .frame(height: 340)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(alignment: .topLeading) {
                    sourceBadge
                }
                .overlay(alignment: .topTrailing) {
                    overlayControls
                }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var content: some View {
        if let streamURL = config.streamURL, config.isAvailable {
            if config.canRenderInline {
                CameraStreamWebView(url: streamURL)
            } else {
                fallbackContent(
                    title: config.streamType == .rtsp ? "RTSP Stream" : "External Stream"
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
            if let recoverySuggestion = config.recoverySuggestion {
                Text(recoverySuggestion)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            ForEach(config.recoveryActions, id: \.self) { recoveryAction in
                VStack(spacing: 6) {
                    Button {
                        onRecover(recoveryAction)
                    } label: {
                        Label(recoveryAction.label, systemImage: recoveryAction.systemImage)
                    }
                    .controlSize(.large)
                    .disabled(recoveryReadinessMessage(for: recoveryAction) != nil)

                    if let readinessMessage = recoveryReadinessMessage(for: recoveryAction) {
                        Label(readinessMessage, systemImage: "info.circle")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.quaternary.opacity(0.35))
    }

    private func fallbackContent(title: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "video")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text("Open this stream in an external app.")
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.quaternary.opacity(0.35))
    }

    private func open(_ streamURL: URL) {
        openURL(streamURL)
        onOpenStream(streamURL)
    }

    private var cameraToggleBinding: Binding<Bool> {
        Binding(
            get: { isCameraEnabled },
            set: { onCameraEnabledChange($0) }
        )
    }

    private var overlayControls: some View {
        HStack(spacing: 10) {
            Toggle("Camera", isOn: cameraToggleBinding)
                .toggleStyle(.switch)

            if let streamURL = config.streamURL, config.isAvailable {
                Button {
                    open(streamURL)
                } label: {
                    Label("Open", systemImage: "arrow.up.forward.app")
                }
                .help("Open camera stream")
            }
        }
        .controlSize(.regular)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .padding(10)
    }

    private var sourceBadge: some View {
        Label(config.sourceLabel, systemImage: config.isAvailable ? "video" : "video.slash")
            .font(.callout.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.regularMaterial, in: Capsule())
            .padding(10)
    }

    private func recoveryReadinessMessage(for recoveryAction: CameraRecoveryAction) -> String? {
        let message = recoveryReadiness(recoveryAction)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return message.isEmpty ? nil : message
    }

}

private extension CameraRecoveryAction {
    var label: String {
        switch self {
        case .refreshStatus:
            "Refresh Status"
        case .openSettings:
            "Open Camera Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .refreshStatus:
            "arrow.clockwise"
        case .openSettings:
            "gearshape"
        }
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
