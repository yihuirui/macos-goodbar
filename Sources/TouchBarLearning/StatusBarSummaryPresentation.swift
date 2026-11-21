import AppKit
import SystemMonitoring

/// Builds the readable value string shown beside the menu-bar status icon.
/// The same renderer is used by the app and the native interaction fixtures.
@MainActor
struct StatusBarSummaryPresentation {
    static let maximumItemWidth: CGFloat = 520
    static let summaryFontSize: CGFloat = 12
    /// 拆分后的两个额度窗口项：空间分配时享受配额特判（占位保留、最后收窄）。
    static let quotaKeys: Set<String> = [TouchBarPluginKey.gptUsage, TouchBarPluginKey.gptUsage7d]

    private static let preferredItemWidth: CGFloat = 460
    private static let minimumItemWidth: CGFloat = 32
    private static let iconAndInsetsWidth: CGFloat = 36
    private static let maximumValueWidth: CGFloat = 132
    private static let separator = " "
    private static let overflowMarker = "···"
    private static let ellipsis = "…"
    private static let statusBarHeight: CGFloat = 22
    private static let iconSize: CGFloat = 16
    private static let iconOriginX: CGFloat = 6

    let visibleKeys: [String]
    let overflowKeys: [String]
    let attributedTitle: NSAttributedString
    let itemLength: CGFloat

    static func make(
        keys: [String],
        maximumItemWidth requestedMaximum: CGFloat? = nil,
        textForKey: (String) -> String
    ) -> StatusBarSummaryPresentation {
        let orderedKeys = DisplayLayout.unique(keys)
        let font = NSFont.monospacedDigitSystemFont(ofSize: summaryFontSize, weight: .medium)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white,
        ]
        let widthOf: (String) -> CGFloat = { value in
            (value as NSString).size(withAttributes: [.font: font]).width
        }
        let separatorWidth = widthOf(separator)
        let overflowWidth = widthOf(overflowMarker)
        let ellipsisWidth = widthOf(ellipsis)

        guard !orderedKeys.isEmpty else {
            return StatusBarSummaryPresentation(
                visibleKeys: [],
                overflowKeys: [],
                attributedTitle: NSAttributedString(string: "", attributes: attributes),
                itemLength: minimumItemWidth
            )
        }

        let requiredCount = min(3, orderedKeys.count)
        let hasInitialOverflow = orderedKeys.count > requiredCount
        let markerWidth = hasInitialOverflow ? separatorWidth + overflowWidth : 0
        let minimumTitleWidth = CGFloat(requiredCount) * ellipsisWidth
            + CGFloat(max(0, requiredCount - 1)) * separatorWidth
            + markerWidth
        let requestedWidth = min(
            maximumItemWidth,
            max(minimumItemWidth, requestedMaximum ?? preferredItemWidth)
        )
        // Even at a deliberately narrow test width, keep three distinct values
        // legible as ellipses instead of silently collapsing them to one item.
        var effectiveMaximum = max(requestedWidth, iconAndInsetsWidth + minimumTitleWidth)

        let rawValues = Dictionary(uniqueKeysWithValues: orderedKeys.map { key in
            let value = textForKey(key)
            return (key, value.isEmpty ? "—" : value)
        })
        var displayedValues = rawValues.mapValues { truncate($0, to: maximumValueWidth, font: font, widthOf: widthOf) }
        // Quota windows have a fixed compact format. Keep all of it when there
        // is room; the space allocator below only shortens them after the other
        // required values have reached their own ellipsis floor.
        for quotaKey in Self.quotaKeys where rawValues[quotaKey] != nil {
            displayedValues[quotaKey] = rawValues[quotaKey]
        }

        var requiredKeys = Array(orderedKeys.prefix(requiredCount))
        let quotaKeysBeyond = orderedKeys.enumerated().filter { !requiredKeys.contains($0.element) && Self.quotaKeys.contains($0.element) }.map(\.element)
        if orderedKeys.count > requiredCount, !quotaKeysBeyond.isEmpty {
            let reservedQuotaKeys = orderedKeys.filter { requiredKeys.contains($0) && Self.quotaKeys.contains($0) } + quotaKeysBeyond
            requiredKeys = Array(orderedKeys.filter { !Self.quotaKeys.contains($0) }.prefix(max(0, requiredCount - quotaKeysBeyond.count)))
                + reservedQuotaKeys
            requiredKeys.sort { orderedKeys.firstIndex(of: $0)! < orderedKeys.firstIndex(of: $1)! }
        }

        func composedTitle(_ selected: [String], includesOverflow: Bool) -> String {
            var title = selected.compactMap { displayedValues[$0] }.joined(separator: separator)
            if includesOverflow {
                if !title.isEmpty { title += separator }
                title += overflowMarker
            }
            return title
        }

        // Keep the selected Codex quota text intact when room allows, trimming
        // long custom values first. Every item stays at the same 12 pt font.
        let includesInitialOverflow = orderedKeys.count > requiredKeys.count
        if requestedMaximum == nil {
            // Use the familiar 460pt width when it fits. Only expand as far as
            // the required full values need, with a modest hard ceiling.
            let completeRequiredWidth = iconAndInsetsWidth
                + ceil(widthOf(composedTitle(requiredKeys, includesOverflow: includesInitialOverflow)))
            effectiveMaximum = min(maximumItemWidth, max(effectiveMaximum, completeRequiredWidth))
        }
        let titleBudget = effectiveMaximum - iconAndInsetsWidth
        while widthOf(composedTitle(requiredKeys, includesOverflow: includesInitialOverflow)) > titleBudget {
            let nonQuotaKeys = requiredKeys.filter { !Self.quotaKeys.contains($0) }
            let shrinkOrder = (nonQuotaKeys + requiredKeys.filter { Self.quotaKeys.contains($0) })
                .sorted { lhs, rhs in
                    let lhsIsQuota = Self.quotaKeys.contains(lhs)
                    let rhsIsQuota = Self.quotaKeys.contains(rhs)
                    if lhsIsQuota != rhsIsQuota { return !lhsIsQuota }
                    return widthOf(displayedValues[lhs] ?? "") > widthOf(displayedValues[rhs] ?? "")
                }
            guard let key = shrinkOrder.first(where: {
                widthOf(displayedValues[$0] ?? "") > ellipsisWidth
            }) else { break }
            let current = displayedValues[key] ?? ""
            let targetWidth = max(ellipsisWidth, widthOf(current) - max(1, font.pointSize * 0.65))
            let next = truncate(rawValues[key] ?? current, to: targetWidth, font: font, widthOf: widthOf)
            guard next != current else { break }
            displayedValues[key] = next
        }

        var visibleSet = Set(requiredKeys)
        for key in orderedKeys where !visibleSet.contains(key) {
            let candidateSet = visibleSet.union([key])
            let candidateKeys = orderedKeys.filter { candidateSet.contains($0) }
            let stillOverflows = candidateSet.count < orderedKeys.count
            let direct = truncate(rawValues[key] ?? key, to: maximumValueWidth, font: font, widthOf: widthOf)
            displayedValues[key] = direct
            if widthOf(composedTitle(candidateKeys, includesOverflow: stillOverflows)) <= titleBudget {
                visibleSet.insert(key)
                continue
            }

            let currentWidth = widthOf(composedTitle(orderedKeys.filter { visibleSet.contains($0) }, includesOverflow: false))
            let suffixWidth = stillOverflows ? separatorWidth + overflowWidth : 0
            let availableWidth = titleBudget - currentWidth - separatorWidth - suffixWidth
            guard availableWidth >= ellipsisWidth else { continue }
            let shortened = truncate(rawValues[key] ?? key, to: min(maximumValueWidth, availableWidth), font: font, widthOf: widthOf)
            displayedValues[key] = shortened
            if widthOf(composedTitle(candidateKeys, includesOverflow: stillOverflows)) <= titleBudget {
                visibleSet.insert(key)
            }
        }

        let visibleKeys = orderedKeys.filter { visibleSet.contains($0) }
        let overflowKeys = orderedKeys.filter { !visibleSet.contains($0) }
        let title = composedTitle(visibleKeys, includesOverflow: !overflowKeys.isEmpty)
        let renderedWidth = ceil(widthOf(title))
        let itemLength = min(effectiveMaximum, max(minimumItemWidth, iconAndInsetsWidth + renderedWidth))

        return StatusBarSummaryPresentation(
            visibleKeys: visibleKeys,
            overflowKeys: overflowKeys,
            attributedTitle: NSAttributedString(string: title, attributes: attributes),
            itemLength: itemLength
        )
    }

    func apply(to button: NSStatusBarButton, icon: NSImage, backingScale requestedScale: CGFloat? = nil) {
        button.title = ""
        // NSStatusBarButton applies menu-bar vibrancy to cell title text, which
        // can override NSAttributedString's foreground color. Use one fixed
        // full-color image so AppKit cannot reinterpret the white text.
        button.attributedTitle = NSAttributedString(string: "")
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleNone
        button.contentTintColor = nil
        let scale = requestedScale
            ?? button.window?.backingScaleFactor
            ?? NSScreen.main?.backingScaleFactor
            ?? 2
        button.image = rasterizedImage(with: icon, height: max(Self.statusBarHeight, button.bounds.height), backingScale: scale)
        button.setAccessibilityValue(attributedTitle.string as NSString)
        button.cell?.wraps = false
    }

    private func rasterizedImage(with icon: NSImage, height requestedHeight: CGFloat, backingScale: CGFloat) -> NSImage {
        let size = NSSize(width: itemLength, height: max(Self.statusBarHeight, requestedHeight))
        let scale = backingScale.isFinite ? max(1, backingScale) : 1
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: max(1, Int(ceil(size.width * scale))),
            pixelsHigh: max(1, Int(ceil(size.height * scale))),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        bitmap.size = size
        let image = NSImage(size: size)
        image.addRepresentation(bitmap)
        image.isTemplate = false

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        let context = NSGraphicsContext(bitmapImageRep: bitmap)!
        NSGraphicsContext.current = context
        context.imageInterpolation = .high

        let bounds = NSRect(origin: .zero, size: size)
        context.compositingOperation = .copy
        NSColor.clear.setFill()
        NSBezierPath(rect: bounds).fill()

        let iconRect = NSRect(
            x: Self.iconOriginX,
            y: (size.height - Self.iconSize) / 2,
            width: Self.iconSize,
            height: Self.iconSize
        )
        context.compositingOperation = .sourceOver
        icon.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 1)
        // Tint monochrome template glyphs only. Full-color resource icons (such
        // as the Codex badge) must retain their original colors and alpha.
        if icon.isTemplate {
            context.compositingOperation = .sourceIn
            NSColor.white.setFill()
            NSBezierPath(rect: iconRect).fill()
        }
        context.compositingOperation = .sourceOver

        if attributedTitle.length > 0 {
            let textRect = NSRect(
                x: Self.iconAndInsetsWidth,
                y: 0,
                width: max(0, size.width - Self.iconAndInsetsWidth),
                height: size.height
            )
            NSBezierPath(rect: textRect).addClip()
            let font = attributedTitle.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
                ?? NSFont.monospacedDigitSystemFont(ofSize: Self.summaryFontSize, weight: .medium)
            let lineHeight = font.ascender - font.descender + font.leading
            let baseline = (size.height - lineHeight) / 2 - font.descender
            attributedTitle.draw(at: NSPoint(x: Self.iconAndInsetsWidth, y: baseline))
        }
        context.flushGraphics()
        return image
    }

    private static func truncate(
        _ value: String,
        to width: CGFloat,
        font: NSFont,
        widthOf: (String) -> CGFloat
    ) -> String {
        guard widthOf(value) > width else { return value }
        let ellipsisWidth = widthOf(ellipsis)
        guard width >= ellipsisWidth else { return "" }
        let availableWidth = width - ellipsisWidth
        var prefix = ""
        for character in value {
            let candidate = prefix + String(character)
            guard widthOf(candidate) <= availableWidth else { break }
            prefix = candidate
        }
        return prefix + ellipsis
    }
}
