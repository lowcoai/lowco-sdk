import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Detects this device without UIKit (so it is safe off the main thread).
enum DeviceInfoDetector {
    static func detect(processInfo: ProcessInfo = .processInfo) -> DeviceInfo {
        let v = processInfo.operatingSystemVersion
        let version = v.patchVersion == 0
            ? "\(v.majorVersion).\(v.minorVersion)"
            : "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
        let osName: String
        let type: String
        let model: String?
        #if targetEnvironment(macCatalyst)
        osName = "Mac OS"
        type = "desktop"
        model = sysctlString("hw.model")
        #elseif os(iOS)
        model = processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? sysctlString("hw.machine")
        if processInfo.isiOSAppOnMac {
            osName = "Mac OS"
            type = "desktop"
        } else {
            osName = "iOS"
            type = (model?.hasPrefix("iPad") ?? false) ? "tablet" : "mobile"
        }
        #elseif os(macOS)
        osName = "Mac OS"
        type = "desktop"
        model = sysctlString("hw.model")
        #elseif os(tvOS)
        osName = "tvOS"
        type = "smarttv"
        model = sysctlString("hw.machine")
        #elseif os(watchOS)
        osName = "watchOS"
        type = "wearable"
        model = sysctlString("hw.machine")
        #else
        osName = "visionOS"
        type = "xr"
        model = sysctlString("hw.machine")
        #endif
        return DeviceInfo(
            os: .init(name: osName, version: version),
            device: .init(type: type, vendor: "Apple", model: model),
            cpu: .init(architecture: architecture),
            engine: .init(name: "LowcoEngage", version: LowcoEngage.sdkVersion),
            ua: "LowcoEngage (\(osName) \(version))"
        )
    }

    static var architecture: String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "amd64"
        #else
        return "unknown"
        #endif
    }

    static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        let value = buffer.withUnsafeBufferPointer { ptr -> String in
            guard let base = ptr.baseAddress else { return "" }
            return String(cString: base)
        }
        return value.isEmpty ? nil : value
    }

    /// The app's marketing version (`CFBundleShortVersionString`).
    static func appVersion(bundle: Bundle = .main) -> String? {
        guard let v = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              !v.isEmpty else { return nil }
        return v
    }
}
