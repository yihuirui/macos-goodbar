import Foundation
import SystemMonitoring

/// 菜单栏摘要宽度档位：auto 按屏幕逻辑宽度选档，其余为手动覆盖。
enum MenuBarWidthMode: String, CaseIterable, Sendable {
    case auto, compact, standard, full
}

enum GoodTouchBarRuntimeConfiguration {
    static let touchBarModeDefaultsKey = "touchBarMode"
    static let touchBarEnabledDefaultsKey = "touchBarEnabled"
    static let touchBarDefaultInfoKey = "GoodTouchBarTouchBarDefault"

    static func selectedMode(
        defaults: UserDefaults = .standard,
        infoValue: Any? = Bundle.main.object(forInfoDictionaryKey: touchBarDefaultInfoKey)
    ) -> GoodTouchBarMode {
        if defaults.object(forKey: touchBarModeDefaultsKey) != nil {
            if let raw = defaults.string(forKey: touchBarModeDefaultsKey),
               let mode = GoodTouchBarMode(rawValue: raw.lowercased()) {
                return mode
            }
            return .auto
        }

        // The 0.1 Bool was an explicit override. Keep honoring it when the new
        // mode setting is absent; the 0.2 bundle default is the string "auto".
        if let stored = defaults.object(forKey: touchBarEnabledDefaultsKey) as? Bool {
            return stored ? .on : .off
        }

        if let raw = infoValue as? String, let mode = GoodTouchBarMode(rawValue: raw.lowercased()) {
            return mode
        }
        if let oldBundleBool = infoValue as? NSNumber {
            return oldBundleBool.boolValue ? .on : .off
        }
        return .auto
    }

    static func resolution(
        capabilities: GoodTouchBarDeviceCapabilities = .current,
        defaults: UserDefaults = .standard,
        infoValue: Any? = Bundle.main.object(forInfoDictionaryKey: touchBarDefaultInfoKey)
    ) -> TouchBarModeResolution {
        capabilities.resolveTouchBarMode(selectedMode(defaults: defaults, infoValue: infoValue))
    }

    static var touchBarEnabled: Bool { resolution().enabled }

    static let menuBarWidthModeDefaultsKey = "menuBarWidthMode"
    /// Compact tier: icon plus one or two values and the overflow marker.
    static let menuBarCompactPreferredWidth: CGFloat = 220
    /// Standard tier: middle ground between compact and the full summary.
    static let menuBarStandardPreferredWidth: CGFloat = 340
    /// Screen-width tiers for the auto mode, in logical points.
    static let menuBarAutoStandardScreenWidth: CGFloat = 1600
    static let menuBarAutoFullScreenWidth: CGFloat = 2048

    /// Preferred summary width for the given menu-bar width mode. Returning
    /// nil keeps the legacy full layout (preferred 460pt, expanding to fit the
    /// required values, hard ceiling 520pt). Manual tiers take precedence over
    /// the auto screen heuristic; auto falls back to the full layout when no
    /// usable screen width is known.
    static func preferredSummaryWidth(
        forScreenWidth screenWidth: CGFloat?,
        mode: MenuBarWidthMode?
    ) -> CGFloat? {
        switch mode ?? .auto {
        case .compact: return menuBarCompactPreferredWidth
        case .standard: return menuBarStandardPreferredWidth
        case .full: return nil
        case .auto:
            guard let screenWidth, screenWidth.isFinite, screenWidth > 0 else { return nil }
            if screenWidth >= menuBarAutoFullScreenWidth { return nil }
            if screenWidth >= menuBarAutoStandardScreenWidth { return menuBarStandardPreferredWidth }
            return menuBarCompactPreferredWidth
        }
    }

    /// Stored menu-bar width mode; missing or invalid values fall back to auto.
    static func menuBarWidthMode(defaults: UserDefaults = .standard) -> MenuBarWidthMode {
        guard let raw = defaults.string(forKey: menuBarWidthModeDefaultsKey) else { return .auto }
        return MenuBarWidthMode(rawValue: raw.lowercased()) ?? .auto
    }
    static var deviceSummary: String {
        let device = GoodTouchBarDeviceCapabilities.current
        let mode = resolution(capabilities: device)
        return "机型：\(device.modelIdentifier ?? "unknown") · 架构：\(device.architectureDescription) · 模式：\(mode.requested.rawValue) → \(mode.enabled ? "Touch Bar" : "菜单栏") · \(mode.reason)"
    }
}
