import Foundation

enum AppLanguage: String, CaseIterable, Codable, Identifiable {
    case system
    case zhHans
    case en

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: "跟随系统 / System"
        case .zhHans: "中文"
        case .en: "English"
        }
    }

    var resolvedCode: String {
        switch self {
        case .zhHans:
            "zh"
        case .en:
            "en"
        case .system:
            Locale.preferredLanguages.first?.hasPrefix("zh") == true ? "zh" : "en"
        }
    }
}

enum L10n {
    static func t(_ key: String, _ language: AppLanguage) -> String {
        let table = language.resolvedCode == "zh" ? zh : en
        return table[key] ?? en[key] ?? key
    }

    private static let zh: [String: String] = [
        "app.name": "2K HiDPI 助手",
        "menu.displays": "显示器",
        "menu.refresh": "刷新显示器",
        "nav.displays": "显示器",
        "empty.noDisplay": "没有显示器",
        "action.refresh": "刷新",
        "status.ready": "就绪",
        "status.localOnly": "显示模式未切换，已保持当前状态",
        "status.updated": "已切换",
        "display.builtin": "内建显示器",
        "display.external": "外接显示器",
        "display.fallbackName": "显示器",
        "display.vendor": "厂商",
        "display.model": "型号",
        "display.serial": "序列号",
        "display.product": "产品名",
        "display.physicalSize": "物理尺寸",
        "display.estimatedPPI": "估算像素密度",
        "display.modes": "可用模式",
        "display.identifiers": "显示器 ID",
        "display.manufactured": "制造时间",
        "display.modeUnavailable": "当前显示模式不可用",
        "display.native": "检测到的原生模式",
        "display.class": "屏幕类型",
        "display.class.2k": "2K / QHD 显示器",
        "display.class.2_5k": "2.5K 显示器",
        "display.class.4k": "4K 或更高分辨率显示器",
        "display.class.low": "低于 2K 的显示器",
        "display.class.unknown": "未识别类型",
        "hidpi.title": "HiDPI 缩放",
        "hidpi.current": "当前模式",
        "hidpi.diagnosis": "诊断",
        "hidpi.available": "可用 HiDPI 模式",
        "hidpi.recommended": "推荐模式",
        "hidpi.best": "首选",
        "hidpi.noRecommendations": "没有可推荐的 HiDPI 模式",
        "hidpi.none": "当前系统没有暴露可切换的 HiDPI 模式",
        "hidpi.currentOn": "当前已经是 HiDPI",
        "hidpi.currentOff": "当前不是 HiDPI，字体可能偏糊或偏小",
        "hidpi.apply": "应用",
        "hidpi.confirm": "保留这个模式",
        "hidpi.rollback": "恢复之前模式",
        "hidpi.pending": "如果不确认，将自动恢复之前模式",
        "hidpi.confirmed": "已保留当前 HiDPI 模式",
        "hidpi.openSettings": "打开系统显示设置",
        "hidpi.note": "2K/2.5K 显示器是否能 HiDPI，取决于 macOS 是否暴露对应缩放模式。这里会列出系统当前允许切换的真实模式。",
        "settings.language": "语言",
        "settings.appLanguage": "应用语言",
        "error.modeUnavailable": "显示模式不再可用",
        "error.configBegin": "无法开始显示配置",
        "error.configMode": "无法配置显示模式",
        "error.configApply": "无法应用显示模式"
    ]

    private static let en: [String: String] = [
        "app.name": "2K HiDPI Assistant",
        "menu.displays": "Displays",
        "menu.refresh": "Refresh Displays",
        "nav.displays": "Displays",
        "empty.noDisplay": "No Display",
        "action.refresh": "Refresh",
        "status.ready": "Ready",
        "status.localOnly": "Display mode did not change; current state was preserved",
        "status.updated": "Switched",
        "display.builtin": "Built-in Display",
        "display.external": "External Display",
        "display.fallbackName": "Display",
        "display.vendor": "Vendor",
        "display.model": "Model",
        "display.serial": "Serial",
        "display.product": "Product",
        "display.physicalSize": "Physical size",
        "display.estimatedPPI": "Estimated density",
        "display.modes": "Available modes",
        "display.identifiers": "Display IDs",
        "display.manufactured": "Manufactured",
        "display.modeUnavailable": "Current mode unavailable",
        "display.native": "Detected native mode",
        "display.class": "Display class",
        "display.class.2k": "2K / QHD display",
        "display.class.2_5k": "2.5K display",
        "display.class.4k": "4K or higher display",
        "display.class.low": "Below 2K display",
        "display.class.unknown": "Unknown display class",
        "hidpi.title": "HiDPI Scaling",
        "hidpi.current": "Current mode",
        "hidpi.diagnosis": "Diagnosis",
        "hidpi.available": "Available HiDPI modes",
        "hidpi.recommended": "Recommended modes",
        "hidpi.best": "Best pick",
        "hidpi.noRecommendations": "No recommended HiDPI modes",
        "hidpi.none": "macOS is not exposing switchable HiDPI modes for this display",
        "hidpi.currentOn": "Current mode is already HiDPI",
        "hidpi.currentOff": "Current mode is not HiDPI; text may be blurry or too small",
        "hidpi.apply": "Apply",
        "hidpi.confirm": "Keep This Mode",
        "hidpi.rollback": "Revert",
        "hidpi.pending": "If you do not confirm, the previous mode will be restored automatically",
        "hidpi.confirmed": "Current HiDPI mode kept",
        "hidpi.openSettings": "Open Display Settings",
        "hidpi.note": "HiDPI on a 2K/2.5K display depends on whether macOS exposes matching scaled modes. This list only shows real modes the system currently allows.",
        "settings.language": "Language",
        "settings.appLanguage": "App language",
        "error.modeUnavailable": "Display mode is no longer available",
        "error.configBegin": "Could not begin display configuration",
        "error.configMode": "Could not configure display mode",
        "error.configApply": "Could not apply display mode"
    ]
}
