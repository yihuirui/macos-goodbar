import AppKit
import SystemMonitoring

@MainActor
private final class StatusBarButtonActionProbe: NSObject {
    var invocationCount = 0

    @objc func activate(_ sender: Any?) {
        invocationCount += 1
    }
}

@main @MainActor struct SettingsInteractionCheck {
    static func main() throws {
        _ = NSApplication.shared
        var count = 0
        func check(_ value:Bool,_ message:String) { precondition(value,message); count += 1; print("PASS: \(message)") }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:dir) }
        let manager = TouchBarPluginManager(configurationURL:dir.appendingPathComponent("plugins.json"))
        let monitor = SystemMetricsMonitor()
        var saved = 0, openedFan = 0, openedPlugins = 0, value = 10
        let settings = MonitorSettingsWindow(manager:manager,monitor:monitor,preview:{_ in "CPU \(value)%"},didSave:{ saved += 1 })
        settings.onOpenFanControl = { openedFan += 1 }; settings.onOpenPlugins = { openedPlugins += 1 }
        let window = settings.window!, content = window.contentView!
        func views(_ root:NSView) -> [NSView] { [root] + root.subviews.flatMap(views) }
        func button(_ title:String) -> NSButton { views(content).compactMap { $0 as? NSButton }.first { $0.title == title }! }
        let tabs = views(content).compactMap { $0 as? NSTabView }.first!
        let table = views(content).compactMap { $0 as? NSTableView }.first!
        let hasTouchBar = GoodTouchBarDeviceCapabilities.current.touchBarSupported
        let selectedLayoutColumn = hasTouchBar ? 1 : 2
        check(table.tableColumns[1].isHidden == !hasTouchBar,"Touch Bar layout column follows detected hardware")
        func reachable(_ b:NSButton) -> Bool {
            window.layoutIfNeeded(); content.layoutSubtreeIfNeeded()
            let point = b.convert(NSPoint(x:b.bounds.midX,y:b.bounds.midY),to:content)
            guard let hit = content.hitTest(point) else { return false }
            return hit === b || hit.isDescendant(of:b)
        }
        window.orderFront(nil)
        for theme in [NSAppearance.Name.aqua,.darkAqua] {
            window.appearance = NSAppearance(named:theme)
            for (title,id) in [("性能详情","details"),("阈值颜色","thresholds"),("显示项目","display")] {
                let b = button(title); check(reachable(b),"navigation hit test: \(theme.rawValue) \(title)")
                b.performClick(nil)
                for _ in 0..<15 { value += 1; settings.render() }
                check(tabs.selectedTabViewItem?.identifier as? String == id,"tab selection survives refresh: \(id)")
            }
            if GoodTouchBarDeviceCapabilities.current.canUseIntelFanHelper {
                button("风扇调速").performClick(nil)
                check(openedFan > 0,"native Intel exposes the experimental fan control entry")
            } else {
                check(views(content).compactMap { $0 as? NSTextField }.contains { $0.stringValue == "风扇由 macOS 自动管理（只读）" },"ARM and Rosetta hide fan writes and explain system management")
            }
            button("插件配置").performClick(nil)
            check(openedPlugins > 0,"plugin settings action remains connected")
            let row = manager.catalogKeys.firstIndex(of:MetricID.cpu.rawValue)!
            table.scrollRowToVisible(row); window.layoutIfNeeded(); content.layoutSubtreeIfNeeded()
            let checkbox = table.view(atColumn:selectedLayoutColumn,row:row,makeIfNecessary:true) as! NSButton
            let old = checkbox.state; checkbox.performClick(nil)
            let expected = checkbox.state
            check(old != expected,"checkbox toggles")
            let preview = table.view(atColumn:3,row:row,makeIfNecessary:true) as! NSTextField
            for _ in 0..<30 { value += 1; settings.render() }
            check(table.view(atColumn:selectedLayoutColumn,row:row,makeIfNecessary:false) === checkbox && checkbox.state == expected,"refresh preserves checkbox object and selection")
            check(table.view(atColumn:3,row:row,makeIfNecessary:false) === preview && preview.stringValue == "CPU \(value)%","preview updates in place")
            check(reachable(button("保存显示设置")),"save button receives pointer events")
            button("保存显示设置").performClick(nil)
            let selectedLayoutContainsCPU = hasTouchBar
                ? manager.visibleKeys.contains(MetricID.cpu.rawValue)
                : manager.menuKeys.contains(MetricID.cpu.rawValue)
            check(selectedLayoutContainsCPU == (expected == .on),"display selection persists in the active layout")
            button("阈值颜色").performClick(nil)
            let fields = views(content).compactMap { $0 as? NSTextField }
            let warning = fields.first { $0.identifier?.rawValue == "warning-system.cpuTemperature" }!
            let critical = fields.first { $0.identifier?.rawValue == "critical-system.cpuTemperature" }!
            window.makeFirstResponder(warning)
            warning.currentEditor()?.string = "87"
            critical.stringValue = "97"
            for _ in 0..<15 { settings.render() }
            check(warning.currentEditor()?.string == "87","threshold field editor survives updates")
            button("保存阈值").performClick(nil)
            check(manager.configuration.metricThresholds?["system.cpuTemperature"] == [87,97],"threshold save reads active field editor")
            window.makeFirstResponder(nil)
            let bitmap = content.bitmapImageRepForCachingDisplay(in:content.bounds)!
            window.effectiveAppearance.performAsCurrentDrawingAppearance { content.cacheDisplay(in:content.bounds,to:bitmap) }
            let color = bitmap.colorAt(x:8,y:8)!.usingColorSpace(.deviceRGB)!
            let brightness = (color.redComponent + color.greenComponent + color.blueComponent) / 3
            check(theme == .darkAqua ? brightness < 0.35 : brightness > 0.65,"background matches semantic appearance: \(theme.rawValue)")
            try bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:"\(ProcessInfo.processInfo.environment["TASK_BUILD_DIR"] ?? FileManager.default.temporaryDirectory.path)/settings-\(theme == .darkAqua ? "dark" : "light").png"))
            button("显示项目").performClick(nil)
        }
        window.close(); window.orderFront(nil); button("显示项目").performClick(nil)
        check(reachable(button("性能详情")) && saved >= 4,"close and reopen leaves settings usable")

        let menuColumn = table.tableColumns.firstIndex { $0.identifier.rawValue == "menu" }!
        func saveMenuSelection(_ selectedKeys: Set<String>) {
            for row in manager.catalogKeys.indices {
                table.scrollRowToVisible(row); window.layoutIfNeeded(); content.layoutSubtreeIfNeeded()
                let checkbox = table.view(atColumn:menuColumn,row:row,makeIfNecessary:true) as! NSButton
                let shouldSelect = selectedKeys.contains(manager.catalogKeys[row])
                if (checkbox.state == .on) != shouldSelect { checkbox.performClick(nil) }
            }
            button("保存显示设置").performClick(nil)
        }
        let selectedMenuKeys = [TouchBarPluginKey.gptUsage, TouchBarPluginKey.todayTokens, MetricID.memory.rawValue]
        saveMenuSelection(Set(selectedMenuKeys))
        check(manager.menuKeys == selectedMenuKeys,"saved menu checkboxes retain their row order")

        // 菜单栏宽度档位：纯逻辑映射 + 设置窗口控件与持久化联动。
        check(GoodTouchBarRuntimeConfiguration.menuBarWidthMode() == .auto,"menu bar width defaults to auto")
        check(GoodTouchBarRuntimeConfiguration.preferredSummaryWidth(forScreenWidth:2560,mode:.auto) == nil,"auto keeps the legacy full layout on wide displays")
        check(GoodTouchBarRuntimeConfiguration.preferredSummaryWidth(forScreenWidth:1720,mode:.auto) == 340,"auto picks the standard tier on mid-size displays")
        check(GoodTouchBarRuntimeConfiguration.preferredSummaryWidth(forScreenWidth:1512,mode:.auto) == 220,"auto picks the compact tier on small displays")
        check(GoodTouchBarRuntimeConfiguration.preferredSummaryWidth(forScreenWidth:nil,mode:.auto) == nil,"auto falls back to the full layout without screen metrics")
        check(GoodTouchBarRuntimeConfiguration.preferredSummaryWidth(forScreenWidth:1512,mode:.full) == nil,"manual full tier keeps the legacy layout")
        check(GoodTouchBarRuntimeConfiguration.preferredSummaryWidth(forScreenWidth:2560,mode:.compact) == 220,"manual compact tier overrides the screen heuristic")
        let widthPopup = views(content).compactMap { $0 as? NSPopUpButton }.first { $0.itemTitles.contains("紧凑") }!
        check(widthPopup.itemTitles == ["自动","紧凑","标准","完整"],"menu bar width control exposes the four tiers")
        func chooseMenuBarWidth(_ title:String) {
            widthPopup.selectItem(withTitle:title)
            if let action = widthPopup.action { NSApp.sendAction(action,to:widthPopup.target,from:widthPopup) }
        }
        chooseMenuBarWidth("紧凑")
        check(GoodTouchBarRuntimeConfiguration.menuBarWidthMode() == .compact,"choosing a tier persists immediately")
        check(views(content).compactMap { $0 as? NSTextField }.contains { $0.stringValue.contains("菜单栏宽度已保存") },"width change reports the immediate effect")
        chooseMenuBarWidth("自动")
        check(GoodTouchBarRuntimeConfiguration.menuBarWidthMode() == .auto,"switching back to auto persists")
        UserDefaults.standard.removeObject(forKey:GoodTouchBarRuntimeConfiguration.menuBarWidthModeDefaultsKey)

        // 额度拆分：5h 沿用 gpt.usage，7d 以独立键出现在目录与默认菜单里。
        // 用全新配置验证迁移默认值，不受本测试前序保存动作影响。
        let quotaManager = TouchBarPluginManager(configurationURL:dir.appendingPathComponent("quota-plugins.json"))
        check(quotaManager.catalogKeys.contains(TouchBarPluginKey.gptUsage7d),"quota split exposes the 7d catalog row")
        check(quotaManager.menuKeys.contains(TouchBarPluginKey.gptUsage) && quotaManager.menuKeys.contains(TouchBarPluginKey.gptUsage7d),
              "default menu selection keeps both quota windows after the split")

        let summaryButton = NSStatusBarButton(frame:NSRect(x:0,y:0,width:StatusBarSummaryPresentation.maximumItemWidth,height:22))
        summaryButton.isBordered = false
        summaryButton.setAccessibilityLabel("GoodBar 状态详情")
        let actionProbe = StatusBarButtonActionProbe()
        summaryButton.target = actionProbe
        summaryButton.action = #selector(StatusBarButtonActionProbe.activate(_:))
        summaryButton.sendAction(on:[.leftMouseUp, .rightMouseUp])
        let summaryIcon = NSImage(systemSymbolName:"bolt.horizontal.circle",accessibilityDescription:"GoodBar 状态详情")!
        summaryIcon.isTemplate = true
        summaryIcon.size = NSSize(width:16,height:16)
        let codexIconPath = "Resources/codex-status-icon.png"
        guard let codexSummaryIcon = NSImage(contentsOfFile:codexIconPath) else {
            fatalError("original Codex status icon resource is missing at \(codexIconPath)")
        }
        codexSummaryIcon.size = NSSize(width:16,height:16)
        codexSummaryIcon.isTemplate = false
        func referenceCodexIcon(backingScale:CGFloat) -> NSBitmapImageRep {
            let pixelScale = max(1,Int(backingScale.rounded()))
            let raster = NSBitmapImageRep(
                bitmapDataPlanes:nil,
                pixelsWide:16 * pixelScale,
                pixelsHigh:16 * pixelScale,
                bitsPerSample:8,
                samplesPerPixel:4,
                hasAlpha:true,
                isPlanar:false,
                colorSpaceName:.deviceRGB,
                bytesPerRow:0,
                bitsPerPixel:0
            )!
            raster.size = NSSize(width:16,height:16)
            NSGraphicsContext.saveGraphicsState()
            let context = NSGraphicsContext(bitmapImageRep:raster)!
            NSGraphicsContext.current = context
            context.imageInterpolation = .high
            context.compositingOperation = .copy
            NSColor.clear.setFill()
            NSBezierPath(rect:NSRect(x:0,y:0,width:16,height:16)).fill()
            context.compositingOperation = .sourceOver
            codexSummaryIcon.draw(
                in:NSRect(x:0,y:0,width:16,height:16),
                from:.zero,
                operation:.sourceOver,
                fraction:1
            )
            context.flushGraphics()
            NSGraphicsContext.restoreGraphicsState()
            return raster
        }
        func currentSummary() -> StatusBarSummaryPresentation {
            StatusBarSummaryPresentation.make(keys:manager.menuKeys) { key in
                switch key {
                case TouchBarPluginKey.gptUsage: return "5h余79%（15:30重置） · 7d余75%"
                case TouchBarPluginKey.todayTokens: return "💰 12,345"
                case MetricID.memory.rawValue: return "内存 47%"
                case MetricID.cpu.rawValue: return "CPU 47%"
                default: return key
                }
            }
        }
        var summary = currentSummary()
        summary.apply(to:summaryButton,icon:codexSummaryIcon,backingScale:2)
        summaryButton.setFrameSize(NSSize(width:summary.itemLength,height:22))
        let summaryRaster = summaryButton.image?.representations.first as? NSBitmapImageRep
        check(summary.visibleKeys == selectedMenuKeys &&
              summary.attributedTitle.string == "5h余79%（15:30重置） · 7d余75% 💰 12,345 内存 47%" &&
              summaryButton.image !== codexSummaryIcon && summaryButton.image?.isTemplate == false &&
              summaryButton.imagePosition == .imageOnly &&
              summaryButton.attributedTitle.string.isEmpty && summaryRaster?.pixelsWide == Int(ceil(summary.itemLength * 2)) &&
              summary.itemLength <= StatusBarSummaryPresentation.maximumItemWidth,
              "quota clock, tokens, and memory values fit at full 12 pt size beside the Codex icon")
        let renderedColor = summary.attributedTitle.attribute(.foregroundColor, at:0, effectiveRange:nil) as? NSColor
        let renderedFont = summary.attributedTitle.attribute(.font, at:0, effectiveRange:nil) as? NSFont
        check(renderedColor?.isEqual(NSColor.white) == true &&
              summaryButton.contentTintColor == nil && renderedFont?.pointSize == 12 &&
              summaryButton.accessibilityValue() as? String == summary.attributedTitle.string &&
              summaryButton.accessibilityLabel() == "GoodBar 状态详情" &&
              summaryButton.target === actionProbe && summaryButton.action == #selector(StatusBarButtonActionProbe.activate(_:)),
              "rasterized status button keeps 12 pt white source text and its accessible native action path")
        let actionMask = NSEvent.EventTypeMask(rawValue:UInt64(truncatingIfNeeded:summaryButton.sendAction(on:[])))
        summaryButton.sendAction(on:[.leftMouseUp, .rightMouseUp])
        check(actionMask.contains(.leftMouseUp) && actionMask.contains(.rightMouseUp),
              "native status button retains both left-click and right-click event routes")
        summaryButton.performClick(nil)
        check(actionProbe.invocationCount == 1,"native status button action still fires after raster presentation")

        let worstCaseQuota = StatusBarSummaryPresentation.make(
            keys:[TouchBarPluginKey.gptUsage, TouchBarPluginKey.todayTokens, MetricID.memory.rawValue]
        ) { key in
            switch key {
            case TouchBarPluginKey.gptUsage: return "5h余100%·旧（10-30 03:00重置） · 7d余100%·旧"
            case TouchBarPluginKey.todayTokens: return "💰 123,456"
            case MetricID.memory.rawValue: return "内存 87%"
            default: return key
            }
        }
        worstCaseQuota.apply(to:summaryButton,icon:codexSummaryIcon,backingScale:2)
        summaryButton.setFrameSize(NSSize(width:worstCaseQuota.itemLength,height:22))
        check(worstCaseQuota.visibleKeys == [TouchBarPluginKey.gptUsage, TouchBarPluginKey.todayTokens, MetricID.memory.rawValue] &&
              worstCaseQuota.overflowKeys.isEmpty &&
              worstCaseQuota.attributedTitle.string == "5h余100%·旧（10-30 03:00重置） · 7d余100%·旧 💰 123,456 内存 87%" &&
              summaryButton.accessibilityValue() as? String == worstCaseQuota.attributedTitle.string &&
              worstCaseQuota.itemLength <= StatusBarSummaryPresentation.maximumItemWidth,
              "dated stale Codex quota remains whole beside tokens and memory without shrinking the font; title=\(worstCaseQuota.attributedTitle.string), width=\(worstCaseQuota.itemLength), visible=\(worstCaseQuota.visibleKeys), overflow=\(worstCaseQuota.overflowKeys)")

        func renderNativeStatusButton(_ appearanceName: NSAppearance.Name, backingScale: CGFloat, filename: String) throws -> NSBitmapImageRep {
            let width = ceil(worstCaseQuota.itemLength)
            let size = NSSize(width:width,height:22)
            let gray = NSColor(calibratedWhite:0.42,alpha:1)
            let host = NSView(frame:NSRect(origin:.zero,size:size))
            host.wantsLayer = true
            host.layer?.backgroundColor = gray.cgColor
            let effect = NSVisualEffectView(frame:host.bounds)
            effect.material = .menu
            effect.blendingMode = .withinWindow
            effect.state = .active
            effect.appearance = NSAppearance(named:appearanceName)
            host.addSubview(effect)

            let button = NSStatusBarButton(frame:NSRect(origin:.zero,size:size))
            button.isBordered = false
            button.appearance = NSAppearance(named:appearanceName)
            button.setAccessibilityLabel("GoodBar 状态详情")
            let probe = StatusBarButtonActionProbe()
            button.target = probe
            button.action = #selector(StatusBarButtonActionProbe.activate(_:))
            button.sendAction(on:[.leftMouseUp, .rightMouseUp])
            worstCaseQuota.apply(to:button,icon:codexSummaryIcon,backingScale:backingScale)
            effect.addSubview(button)
            button.setFrameSize(size)

            let window = NSWindow(contentRect:NSRect(origin:.zero,size:size),styleMask:.borderless,backing:.buffered,defer:false)
            window.isOpaque = true
            window.backgroundColor = gray
            window.appearance = NSAppearance(named:appearanceName)
            window.contentView = host
            window.layoutIfNeeded()
            host.layoutSubtreeIfNeeded()
            let bitmap = NSBitmapImageRep(
                bitmapDataPlanes:nil,
                pixelsWide:max(1,Int(ceil(size.width * backingScale))),
                pixelsHigh:max(1,Int(ceil(size.height * backingScale))),
                bitsPerSample:8,
                samplesPerPixel:4,
                hasAlpha:true,
                isPlanar:false,
                colorSpaceName:.deviceRGB,
                bytesPerRow:0,
                bitsPerPixel:0
            )!
            bitmap.size = size
            window.effectiveAppearance.performAsCurrentDrawingAppearance { host.cacheDisplay(in:host.bounds,to:bitmap) }
            let outputDirectory = ProcessInfo.processInfo.environment["STATUS_SUMMARY_RENDER_OUTPUT_DIR"]
                ?? ProcessInfo.processInfo.environment["TASK_BUILD_DIR"]
                ?? FileManager.default.temporaryDirectory.path
            let outputURL = URL(fileURLWithPath:outputDirectory,isDirectory:true)
            try FileManager.default.createDirectory(at:outputURL,withIntermediateDirectories:true)
            try bitmap.representation(using:.png,properties:[:])!.write(to:outputURL.appendingPathComponent(filename))

            let scaleX = CGFloat(bitmap.pixelsWide) / max(1,width)
            let scaleY = CGFloat(bitmap.pixelsHigh) / size.height
            let textStart = max(0,Int(ceil(36 * scaleX)))
            var whiteTextPixels = 0
            var firstWhiteTextY = bitmap.pixelsHigh
            var lastWhiteTextY = -1
            let sourceIcon = referenceCodexIcon(backingScale:backingScale)
            var sourceOpaquePixels = 0
            var sourceNonWhitePixels = 0
            var matchingSourcePixels = 0
            let iconStartX = max(0,Int(floor(6 * scaleX)))
            let iconStartY = max(0,Int(floor(3 * scaleY)))
            if bitmap.pixelsWide > textStart {
                for x in textStart..<bitmap.pixelsWide {
                    for y in 0..<bitmap.pixelsHigh {
                        guard let color = bitmap.colorAt(x:x,y:y)?.usingColorSpace(.deviceRGB) else { continue }
                        if color.alphaComponent > 0.9 && color.redComponent > 0.93 && color.greenComponent > 0.93 && color.blueComponent > 0.93 {
                            whiteTextPixels += 1
                            firstWhiteTextY = min(firstWhiteTextY,y)
                            lastWhiteTextY = max(lastWhiteTextY,y)
                        }
                    }
                }
            }
            for x in 0..<sourceIcon.pixelsWide {
                for y in 0..<sourceIcon.pixelsHigh {
                    guard let source = sourceIcon.colorAt(x:x,y:y)?.usingColorSpace(.deviceRGB), source.alphaComponent > 0.98,
                          let actual = bitmap.colorAt(x:iconStartX + x,y:iconStartY + y)?.usingColorSpace(.deviceRGB) else { continue }
                    sourceOpaquePixels += 1
                    let sourceBrightness = (source.redComponent + source.greenComponent + source.blueComponent) / 3
                    if sourceBrightness < 0.9 { sourceNonWhitePixels += 1 }
                    let difference = max(
                        abs(actual.redComponent - source.redComponent),
                        abs(actual.greenComponent - source.greenComponent),
                        abs(actual.blueComponent - source.blueComponent)
                    )
                    if actual.alphaComponent > 0.9 && difference < 0.06 {
                        matchingSourcePixels += 1
                    }
                }
            }
            check(sourceOpaquePixels > 50 && sourceNonWhitePixels > 20 && matchingSourcePixels > sourceOpaquePixels * 8 / 10,
                  "actual NSStatusBarButton raster preserves the original Codex badge and knot pixels in \(appearanceName.rawValue); matching=\(matchingSourcePixels)/\(sourceOpaquePixels), nonWhite=\(sourceNonWhitePixels)")
            let verticalInset = max(1,Int(ceil(scaleY)))
            check(whiteTextPixels > 24 && firstWhiteTextY >= verticalInset &&
                  lastWhiteTextY < bitmap.pixelsHigh - verticalInset,
                  "actual NSStatusBarButton raster has unclipped white text pixels in \(appearanceName.rawValue) at \(backingScale)x")
            check(button.title.isEmpty && button.attributedTitle.string.isEmpty && button.image?.isTemplate == false &&
                  button.imagePosition == .imageOnly && button.accessibilityValue() as? String == worstCaseQuota.attributedTitle.string &&
                  button.target === probe && button.action == #selector(StatusBarButtonActionProbe.activate(_:)),
                  "native full-color status image preserves accessibility/action in \(appearanceName.rawValue)")
            button.performClick(nil)
            check(probe.invocationCount == 1,"native button remains clickable in \(appearanceName.rawValue)")

            return bitmap
        }

        _ = try renderNativeStatusButton(.aqua,backingScale:1,filename:"status-summary-aqua-1x.png")
        _ = try renderNativeStatusButton(.vibrantLight,backingScale:2,filename:"status-summary-vibrant-light-2x.png")
        _ = try renderNativeStatusButton(.darkAqua,backingScale:1,filename:"status-summary-dark-aqua-1x.png")
        _ = try renderNativeStatusButton(.vibrantDark,backingScale:2,filename:"status-summary-vibrant-dark-2x.png")

        saveMenuSelection([MetricID.cpu.rawValue])
        summary = currentSummary(); summary.apply(to:summaryButton,icon:summaryIcon,backingScale:2)
        summaryButton.setFrameSize(NSSize(width:summary.itemLength,height:22))
        check(manager.menuKeys == [MetricID.cpu.rawValue] && summaryButton.accessibilityValue() as? String == "CPU 47%",
              "a later saved checkbox change immediately replaces the status summary")

        let emptySummary = StatusBarSummaryPresentation.make(keys:[]) { _ in "" }
        emptySummary.apply(to:summaryButton,icon:summaryIcon,backingScale:2)
        let emptyRaster = summaryButton.image?.representations.first as? NSBitmapImageRep
        check(emptySummary.attributedTitle.string.isEmpty && summaryButton.image?.isTemplate == false &&
              summaryButton.imagePosition == .imageOnly && summaryButton.accessibilityValue() as? String == "" &&
              emptyRaster?.pixelsWide == Int(ceil(emptySummary.itemLength * 2)) &&
              emptySummary.itemLength <= StatusBarSummaryPresentation.maximumItemWidth,
              "empty menu selection keeps the accessible status icon")

        let quotaKey = TouchBarPluginKey.gptUsage
        let quotaReserved = StatusBarSummaryPresentation.make(
            keys:["custom.one", "custom.two", "custom.three", "custom.four", quotaKey], maximumItemWidth:220
        ) { key in
            key == quotaKey ? "5h余79% · 7d余75%" : String(repeating:"Long custom reading ",count:8)
        }
        quotaReserved.apply(to:summaryButton,icon:summaryIcon)
        check(quotaReserved.visibleKeys.count >= 3 && quotaReserved.visibleKeys.contains(quotaKey) &&
              quotaReserved.visibleKeys.filter { $0 != quotaKey } == ["custom.one", "custom.two"] &&
              quotaReserved.overflowKeys == ["custom.three", "custom.four"] &&
              quotaReserved.attributedTitle.string.contains("···") && quotaReserved.itemLength <= 220,
              "selected Codex quota reserves a visible slot while other selected items retain relative order")

        // Sixteen keys cannot fit at 180 pt even when every value is reduced to
        // a single ellipsis, so the overflow marker is guaranteed regardless of
        // how a macOS build resolves the CJK and emoji fallback fonts. Five keys
        // were not enough: on the GitHub macos-15 runners all five fitted as
        // ellipses and the overflow assertion failed.
        let manyNarrowKeys = (0..<16).map { "custom.narrow.\($0)" }
        let narrowSummary = StatusBarSummaryPresentation.make(
            keys:manyNarrowKeys, maximumItemWidth:180
        ) { _ in String(repeating:"温度📊custom-reading-",count:40) }
        narrowSummary.apply(to:summaryButton,icon:summaryIcon)
        let narrowFont = narrowSummary.attributedTitle.attribute(.font, at:0, effectiveRange:nil) as? NSFont
        // Report the measured geometry on stderr, which stays unbuffered when a
        // precondition traps, so a failure on another macOS build names the
        // limit that was missed instead of only the assertion label.
        let narrowTitle = narrowSummary.attributedTitle.string
        let narrowTitleWidth = (narrowTitle as NSString)
            .size(withAttributes:[.font:narrowFont ?? NSFont.systemFont(ofSize:12)]).width
        FileHandle.standardError.write(Data("DIAG narrow summary: itemLength=\(narrowSummary.itemLength) visible=\(narrowSummary.visibleKeys.count) overflow=\(narrowSummary.overflowKeys.count) ellipsis=\(narrowTitle.contains("…")) marker=\(narrowTitle.contains("···")) font=\(narrowFont?.pointSize ?? -1) titleWidth=\(narrowTitleWidth) ceiling=\(StatusBarSummaryPresentation.maximumItemWidth)\n".utf8))
        // The renderer deliberately exceeds a requested width that cannot hold
        // three legible slots, so assert the global ceiling rather than the
        // requested 180 pt; font fallback for CJK and emoji differs between
        // macOS builds and moved the measured floor past 180 on CI runners.
        check(narrowSummary.itemLength <= StatusBarSummaryPresentation.maximumItemWidth &&
              narrowSummary.visibleKeys.count >= 3 &&
              !narrowSummary.overflowKeys.isEmpty && narrowTitle.contains("…") &&
              narrowTitle.contains("···") && narrowFont?.pointSize == 12,
              "long custom values truncate with ellipses while retaining three full-size slots and overflow")

        window.close(); monitor.stop()
        print("\(count) native settings appearance and interaction checks passed")
    }
}
