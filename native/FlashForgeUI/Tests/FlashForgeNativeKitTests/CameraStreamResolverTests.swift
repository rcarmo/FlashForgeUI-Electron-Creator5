import FlashForgeNativeKit
import Testing

@Test func cameraResolverPrefersValidCustomURL() throws {
    let config = CameraStreamResolver.resolve(
        userConfig: CameraUserConfig(
            customCameraEnabled: true,
            customCameraURL: "rtsp://camera.local/live"
        ),
        cameraFeatures: CameraFeatureConfig(
            oemStreamURL: "http://192.168.1.25:8080/?action=stream",
            fallbackStreamURL: CameraStreamResolver.flashForgeMJPEGURL(ipAddress: "192.168.1.25")
        )
    )

    #expect(config.sourceType == .custom)
    #expect(config.streamType == .rtsp)
    #expect(config.streamURL?.absoluteString == "rtsp://camera.local/live")
    #expect(config.isAvailable == true)
}

@Test func cameraResolverRejectsInvalidCustomURLBeforeOEMFallback() throws {
    let config = CameraStreamResolver.resolve(
        userConfig: CameraUserConfig(
            customCameraEnabled: true,
            customCameraURL: "ftp://camera.local/live"
        ),
        cameraFeatures: CameraFeatureConfig(
            oemStreamURL: "http://192.168.1.25:8080/?action=stream",
            fallbackStreamURL: ""
        )
    )

    #expect(config.sourceType == .custom)
    #expect(config.isAvailable == false)
    #expect(config.streamURL == nil)
    #expect(config.recoverySuggestion == "Update the custom camera URL in Settings.")
    #expect(config.recoveryAction == .openSettings)
}

@Test func cameraResolverUsesOEMBeforeFallback() throws {
    let config = CameraStreamResolver.resolve(
        userConfig: CameraUserConfig(),
        cameraFeatures: CameraFeatureConfig(
            oemStreamURL: "rtsp://192.168.1.25/live",
            fallbackStreamURL: CameraStreamResolver.flashForgeMJPEGURL(ipAddress: "192.168.1.25")
        )
    )

    #expect(config.sourceType == .oem)
    #expect(config.streamType == .rtsp)
    #expect(config.streamURL?.absoluteString == "rtsp://192.168.1.25/live")
}

@Test func cameraResolverUsesFlashForgeMJPEGFallback() throws {
    let fallbackURL = CameraStreamResolver.flashForgeMJPEGURL(ipAddress: "192.168.1.25")
    let config = CameraStreamResolver.resolve(
        userConfig: CameraUserConfig(),
        cameraFeatures: CameraFeatureConfig(
            oemStreamURL: "",
            fallbackStreamURL: fallbackURL
        )
    )

    #expect(fallbackURL == "http://192.168.1.25:8080/?action=stream")
    #expect(config.sourceType == .intelligentFallback)
    #expect(config.streamType == .mjpeg)
    #expect(config.streamURL?.absoluteString == fallbackURL)
}

@Test func cameraResolverReportsUnavailableWithoutAnyStream() throws {
    let config = CameraStreamResolver.resolve(
        userConfig: CameraUserConfig(),
        cameraFeatures: CameraFeatureConfig()
    )

    #expect(config.sourceType == .none)
    #expect(config.isAvailable == false)
    #expect(config.unavailableReason == "No camera stream is available for this printer.")
    #expect(config.recoverySuggestion == "Refresh status or set a custom camera URL in Settings.")
    #expect(config.recoveryAction == .refreshStatus)
}
