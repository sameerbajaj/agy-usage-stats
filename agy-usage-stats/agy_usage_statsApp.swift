//
//  agy_usage_statsApp.swift
//  agy-usage-stats
//
//  Created by Sameer Bajaj on 6/14/26.
//

import SwiftUI
import AppKit
import Combine

@main
struct agy_usage_statsApp: App {
    @State private var viewModel = AgyStatsViewModel()

    private var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil ||
        ProcessInfo.processInfo.environment["XCTestBundlePath"] != nil ||
        NSClassFromString("XCTestCase") != nil ||
        ProcessInfo.processInfo.arguments.contains("-NSTreatUnknownArgumentsAsOpen")
    }

    public init() {
        // 1. If running under Xcode unit tests, skip single-instance check and do not render MenuBarExtra
        if isRunningTests {
            return
        }

        // 2. Strict single-instance invariant: exit immediately if another instance is already running
        let currentPid = ProcessInfo.processInfo.processIdentifier
        let bundleId = Bundle.main.bundleIdentifier ?? "com.sameerbajaj.agy-usage-stats"
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
        if running.contains(where: { $0.processIdentifier != currentPid && !$0.isTerminated }) {
            exit(0)
        }
    }

    var body: some Scene {
        MenuBarExtra(isInserted: .constant(!isRunningTests)) {
            MenuBarPopover(viewModel: viewModel)
        } label: {
            MenuBarLabel(viewModel: viewModel)
        }
        .menuBarExtraStyle(.window)
    }
}

// MARK: - Menu Bar Label

struct MenuBarLabel: View {
    let viewModel: AgyStatsViewModel
    @State private var refreshTrigger = false

    private var statusColor: Color {
        var fractions: [Double] = []
        if let gf = viewModel.geminiUsageFraction {
            fractions.append(gf)
        }
        if let af = viewModel.argonUsageFraction {
            fractions.append(af)
        }
        if let cf = viewModel.claudeUsageFraction {
            fractions.append(cf)
        }

        if let minFraction = fractions.min() {
            if minFraction > 0.5 {
                return Color(red: 0.15, green: 0.85, blue: 0.55) // Premium emerald green
            } else if minFraction > 0.2 {
                return Color(red: 1.0, green: 0.60, blue: 0.15) // Premium warm orange
            } else {
                return Color(red: 1.0, green: 0.35, blue: 0.35) // Premium ruby red
            }
        }

        if viewModel.stats.queriesToday > 0 {
            return Color(red: 0.65, green: 0.45, blue: 1.0) // Vibrant purple
        } else {
            return .primary.opacity(0.65) // Dim grey
        }
    }

    var body: some View {
        Image(nsImage: viewModel.makeMenuBarImage(litColor: statusColor))
            .help(menuBarTooltip)
            .id(refreshTrigger)
            .onAppear {
                // Trigger stats loading on label launch
                viewModel.setup()
            }
            .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { _ in
                refreshTrigger.toggle()
                Task {
                    await viewModel.refreshQuotaOnly()
                }
            }
    }

    private var menuBarTooltip: String {
        var lines: [String] = ["Antigravity CLI Stats"]
        lines.append("Active: \(viewModel.activeModelDisplayName)")
        if let g = viewModel.geminiUsageFraction {
            lines.append(String(format: "Gemini: %.0f%%", g * 100))
        }
        if let a = viewModel.argonUsageFraction {
            lines.append(String(format: "Argon: %.0f%%", a * 100))
        }
        if let c = viewModel.claudeUsageFraction {
            lines.append(String(format: "Claude: %.0f%%", c * 100))
        }
        if viewModel.stats.gcpTodayCost > 0 || viewModel.stats.gcpTotalCost > 0 {
            lines.append(String(format: "GCP Cloud Spend: $%.2f today ($%.2f total)", viewModel.stats.gcpTodayCost, viewModel.stats.gcpTotalCost))
        }
        lines.append("Queries Today: \(viewModel.stats.queriesToday)")
        return lines.joined(separator: "\n")
    }
}

// MARK: - Presentation Resolver

public struct IconPresentationState: Equatable {
    public enum GaugeStyle: Equatable {
        case none
        case single(fraction: Double, strokeColor: NSColor)
        case both(geminiFraction: Double, claudeFraction: Double)
        case three(geminiFraction: Double, argonFraction: Double, claudeFraction: Double)
    }

    public struct SpendBadge: Equatable {
        public enum IconType: Equatable {
            case cloud
            case dollar
        }
        public let icon: IconType
        public let iconColor: NSColor
        public let text: String
        public let textColor: NSColor

        public init(icon: IconType, iconColor: NSColor, text: String, textColor: NSColor) {
            self.icon = icon
            self.iconColor = iconColor
            self.text = text
            self.textColor = textColor
        }
    }

    public let text: String
    public let textColor: NSColor
    public let gaugeStyle: GaugeStyle
    public let spendBadge: SpendBadge?

    public var hasText: Bool { !text.isEmpty }

    public init(text: String, textColor: NSColor, gaugeStyle: GaugeStyle, spendBadge: SpendBadge? = nil) {
        self.text = text
        self.textColor = textColor
        self.gaugeStyle = gaugeStyle
        self.spendBadge = spendBadge
    }
}

public enum MenuBarPresentationResolver {
    public static let geminiColor = NSColor(red: 0.65, green: 0.45, blue: 1.0, alpha: 1.0)
    public static let argonColor = NSColor(red: 0.0, green: 0.82, blue: 0.95, alpha: 1.0)
    public static let claudeColor = NSColor(red: 1.0, green: 0.5, blue: 0.2, alpha: 1.0)
    public static let gcpBlueColor = NSColor(red: 0.26, green: 0.52, blue: 0.96, alpha: 1.0)
    public static let apiGreenColor = NSColor(red: 0.15, green: 0.85, blue: 0.55, alpha: 1.0)

    public static let healthyGreenColor = NSColor(red: 0.15, green: 0.85, blue: 0.55, alpha: 1.0)
    public static let warningAmberColor = NSColor(red: 1.0, green: 0.60, blue: 0.15, alpha: 1.0)
    public static let lowRedColor = NSColor(red: 1.0, green: 0.35, blue: 0.35, alpha: 1.0)

    public static func healthColor(for fraction: Double) -> NSColor {
        if fraction > 0.50 {
            return healthyGreenColor
        } else if fraction > 0.20 {
            return warningAmberColor
        } else {
            return lowRedColor
        }
    }

    public static let menuBarFont: NSFont = {
        let baseDesc = NSFont.systemFont(ofSize: 11.0, weight: .bold).fontDescriptor.withDesign(.rounded)
        if let baseDesc {
            let monoDesc = baseDesc.addingAttributes([
                .featureSettings: [
                    [
                        NSFontDescriptor.FeatureKey.typeIdentifier: kNumberSpacingType,
                        NSFontDescriptor.FeatureKey.selectorIdentifier: kMonospacedNumbersSelector
                    ]
                ]
            ])
            return NSFont(descriptor: monoDesc, size: 11.0) ?? NSFont.monospacedDigitSystemFont(ofSize: 11.0, weight: .bold)
        }
        return NSFont.monospacedDigitSystemFont(ofSize: 11.0, weight: .bold)
    }()

    public static func resolveQuotaText(
        geminiFraction: Double?,
        argonFraction: Double? = nil,
        claudeFraction: Double?,
        gcpTodayCost: Double? = nil
    ) -> String {
        var parts: [String] = []
        if let gf = geminiFraction {
            parts.append(String(format: "G:%.0f%%", gf * 100))
        }
        if let af = argonFraction {
            parts.append(String(format: "A:%.0f%%", af * 100))
        }
        if let cf = claudeFraction {
            parts.append(String(format: "C:%.0f%%", cf * 100))
        }
        if let gcp = gcpTodayCost, gcp > 0 {
            parts.append(String(format: "☁️$%.2f", gcp))
        }
        if parts.isEmpty {
            return "no subscription session"
        }
        return parts.joined(separator: " ")
    }

    public static func resolveIconPresentation(
        showUsage: Bool,
        selectedModel: IconModelSelection,
        queriesToday: Int,
        litColor: NSColor,
        activeUsageFraction: Double?,
        activeFillFraction: Double?,
        geminiUsageFraction: Double?,
        geminiFillFraction: Double?,
        argonUsageFraction: Double? = nil,
        argonFillFraction: Double? = nil,
        claudeUsageFraction: Double?,
        claudeFillFraction: Double?,
        gcpTodayCost: Double? = nil,
        showSpend: Bool = false,
        spendSource: MenuBarSpendSource = .gcpToday,
        spendAmount: Double = 0.0,
        gcpTotalCost: Double? = nil,
        todayCost: Double? = nil
    ) -> IconPresentationState {
        let badge: IconPresentationState.SpendBadge?
        if showSpend {
            let iconType: IconPresentationState.SpendBadge.IconType
            let iconColor: NSColor
            let amount: Double
            switch spendSource {
            case .gcpToday:
                iconType = .cloud
                iconColor = gcpBlueColor
                amount = gcpTodayCost ?? spendAmount
            case .gcpTotal:
                iconType = .cloud
                iconColor = gcpBlueColor
                amount = gcpTotalCost ?? spendAmount
            case .apiToday:
                iconType = .dollar
                iconColor = apiGreenColor
                amount = todayCost ?? spendAmount
            }
            let formattedText = String(format: "$%.2f", amount)
            badge = IconPresentationState.SpendBadge(
                icon: iconType,
                iconColor: iconColor,
                text: formattedText,
                textColor: NSColor.labelColor
            )
        } else {
            badge = nil
        }

        guard showUsage else {
            return IconPresentationState(text: "", textColor: litColor, gaugeStyle: .none, spendBadge: badge)
        }

        switch selectedModel {
        case .active:
            if let fraction = activeUsageFraction {
                let pctText = String(format: "%.0f%%", fraction * 100)
                let fill = activeFillFraction ?? fraction
                let textColor = healthColor(for: fraction)
                let strokeColor = healthColor(for: fill)
                return IconPresentationState(text: pctText, textColor: textColor, gaugeStyle: .single(fraction: fill, strokeColor: strokeColor), spendBadge: badge)
            } else if queriesToday > 0 {
                let pctText = "\(queriesToday)q"
                return IconPresentationState(text: pctText, textColor: litColor, gaugeStyle: .single(fraction: 1.0, strokeColor: litColor), spendBadge: badge)
            } else {
                return IconPresentationState(text: "", textColor: litColor, gaugeStyle: .none, spendBadge: badge)
            }

        case .mostDepleted:
            var candidates: [(fraction: Double, fill: Double)] = []
            if let gf = geminiUsageFraction {
                candidates.append((fraction: gf, fill: geminiFillFraction ?? gf))
            }
            if let af = argonUsageFraction {
                candidates.append((fraction: af, fill: argonFillFraction ?? af))
            }
            if let cf = claudeUsageFraction {
                candidates.append((fraction: cf, fill: claudeFillFraction ?? cf))
            }

            let minCandidate = candidates.min(by: { $0.fraction < $1.fraction })
            let depletedFraction = minCandidate?.fraction ?? activeUsageFraction
            let depletedFill = minCandidate?.fill ?? activeFillFraction ?? depletedFraction

            if let fraction = depletedFraction {
                let pctText = String(format: "%.0f%%", fraction * 100)
                let fill = depletedFill ?? fraction
                let textColor = healthColor(for: fraction)
                let strokeColor = healthColor(for: fill)
                return IconPresentationState(text: pctText, textColor: textColor, gaugeStyle: .single(fraction: fill, strokeColor: strokeColor), spendBadge: badge)
            } else if queriesToday > 0 {
                let pctText = "\(queriesToday)q"
                return IconPresentationState(text: pctText, textColor: litColor, gaugeStyle: .single(fraction: 1.0, strokeColor: litColor), spendBadge: badge)
            } else {
                return IconPresentationState(text: "", textColor: litColor, gaugeStyle: .none, spendBadge: badge)
            }

        case .gemini:
            if let fraction = geminiUsageFraction {
                let pctText = String(format: "%.0f%%", fraction * 100)
                let fill = geminiFillFraction ?? fraction
                let textColor = healthColor(for: fraction)
                let strokeColor = healthColor(for: fill)
                return IconPresentationState(text: pctText, textColor: textColor, gaugeStyle: .single(fraction: fill, strokeColor: strokeColor), spendBadge: badge)
            } else {
                return IconPresentationState(text: "", textColor: litColor, gaugeStyle: .none, spendBadge: badge)
            }

        case .argon:
            if let fraction = argonUsageFraction {
                let pctText = String(format: "%.0f%%", fraction * 100)
                let fill = argonFillFraction ?? fraction
                let textColor = healthColor(for: fraction)
                let strokeColor = healthColor(for: fill)
                return IconPresentationState(text: pctText, textColor: textColor, gaugeStyle: .single(fraction: fill, strokeColor: strokeColor), spendBadge: badge)
            } else {
                return IconPresentationState(text: "", textColor: litColor, gaugeStyle: .none, spendBadge: badge)
            }

        case .claude:
            if let fraction = claudeUsageFraction {
                let pctText = String(format: "%.0f%%", fraction * 100)
                let fill = claudeFillFraction ?? fraction
                let textColor = healthColor(for: fraction)
                let strokeColor = healthColor(for: fill)
                return IconPresentationState(text: pctText, textColor: textColor, gaugeStyle: .single(fraction: fill, strokeColor: strokeColor), spendBadge: badge)
            } else {
                return IconPresentationState(text: "", textColor: litColor, gaugeStyle: .none, spendBadge: badge)
            }

        case .gcp:
            if let cost = gcpTodayCost, cost > 0 {
                let costText = String(format: "$%.2f", cost)
                let fill = activeFillFraction ?? activeUsageFraction ?? 1.0
                return IconPresentationState(text: costText, textColor: gcpBlueColor, gaugeStyle: .single(fraction: fill, strokeColor: gcpBlueColor), spendBadge: badge)
            } else if let fraction = activeUsageFraction {
                let pctText = String(format: "%.0f%%", fraction * 100)
                let fill = activeFillFraction ?? fraction
                return IconPresentationState(text: pctText, textColor: gcpBlueColor, gaugeStyle: .single(fraction: fill, strokeColor: gcpBlueColor), spendBadge: badge)
            } else if queriesToday > 0 {
                let pctText = "\(queriesToday)q"
                return IconPresentationState(text: pctText, textColor: gcpBlueColor, gaugeStyle: .single(fraction: 1.0, strokeColor: gcpBlueColor), spendBadge: badge)
            } else {
                return IconPresentationState(text: "", textColor: litColor, gaugeStyle: .none, spendBadge: badge)
            }

        case .both:
            if let gf = geminiUsageFraction, let cf = claudeUsageFraction {
                let pctText = String(format: "G:%.0f%% C:%.0f%%", gf * 100, cf * 100)
                let gFill = geminiFillFraction ?? gf
                let cFill = claudeFillFraction ?? cf
                return IconPresentationState(text: pctText, textColor: NSColor.textColor, gaugeStyle: .both(geminiFraction: gFill, claudeFraction: cFill), spendBadge: badge)
            } else if let gf = geminiUsageFraction {
                let pctText = String(format: "%.0f%%", gf * 100)
                let gFill = geminiFillFraction ?? gf
                let textColor = healthColor(for: gf)
                let strokeColor = healthColor(for: gFill)
                return IconPresentationState(text: pctText, textColor: textColor, gaugeStyle: .single(fraction: gFill, strokeColor: strokeColor), spendBadge: badge)
            } else if let cf = claudeUsageFraction {
                let pctText = String(format: "%.0f%%", cf * 100)
                let cFill = claudeFillFraction ?? cf
                let textColor = healthColor(for: cf)
                let strokeColor = healthColor(for: cFill)
                return IconPresentationState(text: pctText, textColor: textColor, gaugeStyle: .single(fraction: cFill, strokeColor: strokeColor), spendBadge: badge)
            } else {
                return IconPresentationState(text: "", textColor: litColor, gaugeStyle: .none, spendBadge: badge)
            }

        case .allThree:
            var parts: [String] = []
            if let gf = geminiUsageFraction { parts.append(String(format: "G:%.0f%%", gf * 100)) }
            if let af = argonUsageFraction { parts.append(String(format: "A:%.0f%%", af * 100)) }
            if let cf = claudeUsageFraction { parts.append(String(format: "C:%.0f%%", cf * 100)) }

            guard !parts.isEmpty else {
                return IconPresentationState(text: "", textColor: litColor, gaugeStyle: .none, spendBadge: badge)
            }

            let pctText = parts.joined(separator: " ")
            let gFill = geminiFillFraction ?? geminiUsageFraction
            let aFill = argonFillFraction ?? argonUsageFraction
            let cFill = claudeFillFraction ?? claudeUsageFraction

            let gauge: IconPresentationState.GaugeStyle
            if let gf = gFill, let af = aFill, let cf = cFill {
                gauge = .three(geminiFraction: gf, argonFraction: af, claudeFraction: cf)
            } else if let gf = gFill, let cf = cFill {
                gauge = .both(geminiFraction: gf, claudeFraction: cf)
            } else if let gf = gFill {
                gauge = .single(fraction: gf, strokeColor: healthColor(for: gf))
            } else if let af = aFill {
                gauge = .single(fraction: af, strokeColor: healthColor(for: af))
            } else if let cf = cFill {
                gauge = .single(fraction: cf, strokeColor: healthColor(for: cf))
            } else {
                gauge = .none
            }

            return IconPresentationState(
                text: pctText,
                textColor: NSColor.textColor,
                gaugeStyle: gauge,
                spendBadge: badge
            )
        }
    }
}

// MARK: - Menu Bar Drawing

public enum AgyMenuBarRenderer {
    private static var cachedAntigravityIcon: (key: String, image: NSImage)? = nil

    public static func makeAntigravityImage(
        queriesToday: Int,
        litColor: Color,
        showUsage: Bool = false,
        selectedModelForIcon: IconModelSelection = .active,
        activeUsageFraction: Double? = nil,
        geminiUsageFraction: Double? = nil,
        argonUsageFraction: Double? = nil,
        claudeUsageFraction: Double? = nil,
        activeFillFraction: Double? = nil,
        geminiFillFraction: Double? = nil,
        argonFillFraction: Double? = nil,
        claudeFillFraction: Double? = nil,
        showMenuBarSpend: Bool = false,
        menuBarSpendSource: MenuBarSpendSource = .gcpToday,
        spendAmount: Double = 0.0,
        gcpTodayCost: Double? = nil,
        gcpTotalCost: Double? = nil,
        todayCost: Double? = nil
    ) -> NSImage {
        let litNS = NSColor(litColor)
        let presentation = MenuBarPresentationResolver.resolveIconPresentation(
            showUsage: showUsage,
            selectedModel: selectedModelForIcon,
            queriesToday: queriesToday,
            litColor: litNS,
            activeUsageFraction: activeUsageFraction,
            activeFillFraction: activeFillFraction,
            geminiUsageFraction: geminiUsageFraction,
            geminiFillFraction: geminiFillFraction,
            argonUsageFraction: argonUsageFraction,
            argonFillFraction: argonFillFraction,
            claudeUsageFraction: claudeUsageFraction,
            claudeFillFraction: claudeFillFraction,
            gcpTodayCost: gcpTodayCost,
            showSpend: showMenuBarSpend,
            spendSource: menuBarSpendSource,
            spendAmount: spendAmount,
            gcpTotalCost: gcpTotalCost,
            todayCost: todayCost
        )

        let cacheKey = "\(queriesToday)_\(litColor.description)_\(presentation.text)_\(presentation.textColor.description)_\(presentation.gaugeStyle)_\(presentation.spendBadge?.icon.hashValue ?? 0)_\(presentation.spendBadge?.text ?? "")_\(presentation.spendBadge?.iconColor.description ?? "")"
        if let cached = cachedAntigravityIcon, cached.key == cacheKey {
            return cached.image
        }

        let h: CGFloat = 16.0
        let font = MenuBarPresentationResolver.menuBarFont
        let textY: CGFloat = 1.0

        let pctText = presentation.text
        var pctTextAttributes: [NSAttributedString.Key: Any] = [:]
        var pctTextSize = NSSize.zero

        if presentation.hasText {
            pctTextAttributes = [.font: font, .foregroundColor: presentation.textColor]
            pctTextSize = (pctText as NSString).size(withAttributes: pctTextAttributes)
        }

        let isThreeGauges: Bool
        let isBothGauges: Bool
        if case .three = presentation.gaugeStyle {
            isThreeGauges = true
            isBothGauges = false
        } else if case .both = presentation.gaugeStyle {
            isThreeGauges = false
            isBothGauges = true
        } else {
            isThreeGauges = false
            isBothGauges = false
        }

        let gaugeSlotWidth: CGFloat
        if isThreeGauges {
            gaugeSlotWidth = 32.0
        } else if isBothGauges {
            gaugeSlotWidth = 24.0
        } else {
            gaugeSlotWidth = 16.0
        }

        // Measure spend badge
        var cloudSymbolImg: NSImage? = nil
        var dollarSymbolImg: NSImage? = nil
        var spendAmountStr: String = ""
        var spendAttributes: [NSAttributedString.Key: Any] = [:]
        var spendTextSize = NSSize.zero

        if let spend = presentation.spendBadge {
            spendAttributes = [.font: font, .foregroundColor: spend.textColor]
            if spend.icon == .cloud {
                let config = NSImage.SymbolConfiguration(pointSize: 9.0, weight: .semibold)
                    .applying(.init(paletteColors: [spend.iconColor]))
                cloudSymbolImg = NSImage(systemSymbolName: "cloud.fill", accessibilityDescription: nil)?.withSymbolConfiguration(config)
                spendAmountStr = spend.text
                spendTextSize = (spendAmountStr as NSString).size(withAttributes: spendAttributes)
            } else {
                let config = NSImage.SymbolConfiguration(pointSize: 9.0, weight: .bold)
                    .applying(.init(paletteColors: [spend.iconColor]))
                dollarSymbolImg = NSImage(systemSymbolName: "dollarsign", accessibilityDescription: nil)?.withSymbolConfiguration(config)
                spendAmountStr = spend.text.replacingOccurrences(of: "$", with: "")
                spendTextSize = (spendAmountStr as NSString).size(withAttributes: spendAttributes)
            }
        }

        // Calculate total image width
        var totalW: CGFloat = gaugeSlotWidth
        if presentation.hasText {
            totalW += 3.5 + pctTextSize.width
        }
        if let _ = presentation.spendBadge {
            totalW += 3.5 + 1.0 + 3.5 // Divider line
            if let cloud = cloudSymbolImg {
                totalW += cloud.size.width + 2.5
            } else if let dollar = dollarSymbolImg {
                totalW += dollar.size.width + 1.5
            }
            totalW += spendTextSize.width + 2.0
        } else {
            if presentation.hasText {
                totalW += 2.0
            }
        }

        let img = NSImage(size: NSSize(width: max(16.0, totalW), height: h), flipped: false) { _ in
            let isLit = queriesToday > 0

            // 1. Draw Gauges or Antigravity A-icon
            switch presentation.gaugeStyle {
            case .single(let fraction, let strokeColor):
                drawGauge(center: NSPoint(x: 8.0, y: 8.0), radius: 5.5, fraction: fraction, strokeColor: strokeColor)
            case .both(let geminiFraction, let claudeFraction):
                drawGauge(center: NSPoint(x: 6.0, y: 8.0), radius: 4.2, fraction: geminiFraction, strokeColor: MenuBarPresentationResolver.healthColor(for: geminiFraction), chevronSize: 2.0)
                drawGauge(center: NSPoint(x: 16.0, y: 8.0), radius: 4.2, fraction: claudeFraction, strokeColor: MenuBarPresentationResolver.healthColor(for: claudeFraction), chevronSize: 2.0)
            case .three(let geminiFraction, let argonFraction, let claudeFraction):
                drawGauge(center: NSPoint(x: 5.0, y: 8.0), radius: 3.8, fraction: geminiFraction, strokeColor: MenuBarPresentationResolver.healthColor(for: geminiFraction), chevronSize: 1.8)
                drawGauge(center: NSPoint(x: 14.0, y: 8.0), radius: 3.8, fraction: argonFraction, strokeColor: MenuBarPresentationResolver.healthColor(for: argonFraction), chevronSize: 1.8)
                drawGauge(center: NSPoint(x: 23.0, y: 8.0), radius: 3.8, fraction: claudeFraction, strokeColor: MenuBarPresentationResolver.healthColor(for: claudeFraction), chevronSize: 1.8)
            case .none:
                let maxFloat: CGFloat = 4.5
                let floatOffset: CGFloat
                if queriesToday == 0 {
                    floatOffset = 0
                } else if queriesToday < 5 {
                    floatOffset = 1.5
                } else if queriesToday < 15 {
                    floatOffset = 3.0
                } else {
                    floatOffset = maxFloat
                }

                // Draw ground line
                let groundRect = NSRect(x: 2.0, y: 2.0, width: 12.0, height: 1.2)
                let groundPath = NSBezierPath(roundedRect: groundRect, xRadius: 0.6, yRadius: 0.6)
                NSColor.labelColor.withAlphaComponent(isLit ? 0.15 : 0.3).setFill()
                groundPath.fill()

                // Draw energy waves
                if isLit {
                    let energyPath = NSBezierPath()
                    if queriesToday >= 15 {
                        energyPath.move(to: NSPoint(x: 5.5, y: 4.5))
                        energyPath.line(to: NSPoint(x: 10.5, y: 4.5))
                        energyPath.move(to: NSPoint(x: 6.5, y: 3.2))
                        energyPath.line(to: NSPoint(x: 9.5, y: 3.2))
                    } else if queriesToday >= 5 {
                        energyPath.move(to: NSPoint(x: 6.0, y: 3.8))
                        energyPath.line(to: NSPoint(x: 10.0, y: 3.8))
                    } else {
                        energyPath.move(to: NSPoint(x: 7.5, y: 3.2))
                        energyPath.line(to: NSPoint(x: 8.5, y: 3.2))
                    }
                    energyPath.lineWidth = 0.8
                    energyPath.lineCapStyle = .round
                    litNS.withAlphaComponent(0.5).setStroke()
                    energyPath.stroke()
                }

                // Outer Chevron
                let outerChevron = NSBezierPath()
                let apexY = 8.0 + floatOffset
                let wingY = 4.5 + floatOffset

                outerChevron.move(to: NSPoint(x: 3.5, y: wingY))
                outerChevron.line(to: NSPoint(x: 8.0, y: apexY))
                outerChevron.line(to: NSPoint(x: 12.5, y: wingY))
                outerChevron.lineWidth = 1.6
                outerChevron.lineCapStyle = .round
                outerChevron.lineJoinStyle = .round
                litNS.setStroke()
                outerChevron.stroke()

                // Inner Chevron
                if isLit {
                    let innerChevron = NSBezierPath()
                    let innerApexY = apexY - 2.2
                    let innerWingY = wingY - 0.2
                    innerChevron.move(to: NSPoint(x: 5.5, y: innerWingY))
                    innerChevron.line(to: NSPoint(x: 8.0, y: innerApexY))
                    innerChevron.line(to: NSPoint(x: 10.5, y: innerWingY))
                    innerChevron.lineWidth = 1.0
                    innerChevron.lineCapStyle = .round
                    innerChevron.lineJoinStyle = .round
                    let alpha = queriesToday >= 15 ? 1.0 : 0.65
                    litNS.withAlphaComponent(alpha).setStroke()
                    innerChevron.stroke()
                }
            }

            // 2. Draw Percentage Text
            var currentX: CGFloat = gaugeSlotWidth
            if presentation.hasText {
                currentX += 3.5
                pctText.draw(at: NSPoint(x: currentX, y: textY), withAttributes: pctTextAttributes)
                currentX += pctTextSize.width
            }

            // 3. Draw Spend Badge (Divider + Icon + Formatted Amount)
            if let _ = presentation.spendBadge {
                let sepX = currentX + 3.5
                let sepRect = NSRect(x: sepX, y: (h - 7.0) / 2.0, width: 1.0, height: 7.0)
                let sepPath = NSBezierPath(roundedRect: sepRect, xRadius: 0.5, yRadius: 0.5)
                NSColor.labelColor.withAlphaComponent(0.22).setFill()
                sepPath.fill()
                currentX = sepX + 1.0 + 3.5

                if let cloud = cloudSymbolImg {
                    let iconY = (h - cloud.size.height) / 2.0
                    cloud.draw(in: NSRect(x: currentX, y: iconY, width: cloud.size.width, height: cloud.size.height))
                    currentX += cloud.size.width + 2.5
                } else if let dollar = dollarSymbolImg {
                    let iconY = (h - dollar.size.height) / 2.0
                    dollar.draw(in: NSRect(x: currentX, y: iconY, width: dollar.size.width, height: dollar.size.height))
                    currentX += dollar.size.width + 1.5
                }

                spendAmountStr.draw(at: NSPoint(x: currentX, y: textY), withAttributes: spendAttributes)
                currentX += spendTextSize.width
            }

            return true
        }
        img.isTemplate = false
        cachedAntigravityIcon = (cacheKey, img)
        return img
    }

    public static func drawGauge(center: NSPoint, radius: CGFloat, fraction: Double, strokeColor: NSColor, chevronSize: CGFloat = 2.5) {
        // Draw Background Track
        let trackPath = NSBezierPath()
        trackPath.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
        trackPath.lineWidth = 1.2
        NSColor.labelColor.withAlphaComponent(0.15).setStroke()
        trackPath.stroke()

        // Draw Progress Arc
        let progressPath = NSBezierPath()
        let startAngle: CGFloat = 90.0
        let endAngle: CGFloat = 90.0 - CGFloat(fraction * 360.0)
        progressPath.appendArc(withCenter: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: true)
        progressPath.lineWidth = 1.6
        progressPath.lineCapStyle = .round
        strokeColor.setStroke()
        progressPath.stroke()

        // Draw Tiny Chevron inside center
        let chevronPath = NSBezierPath()
        let halfSize = chevronSize
        let apexY = center.y + (halfSize * 0.7)
        let wingY = center.y - (halfSize * 0.6)
        chevronPath.move(to: NSPoint(x: center.x - halfSize, y: wingY))
        chevronPath.line(to: NSPoint(x: center.x, y: apexY))
        chevronPath.line(to: NSPoint(x: center.x + halfSize, y: wingY))
        chevronPath.lineWidth = chevronSize > 2.0 ? 1.2 : 1.0
        chevronPath.lineCapStyle = .round
        chevronPath.lineJoinStyle = .round
        strokeColor.setStroke()
        chevronPath.stroke()
    }
}

public func makeAntigravityImage(
    queriesToday: Int,
    litColor: Color,
    showUsage: Bool = false,
    selectedModelForIcon: IconModelSelection = .active,
    activeUsageFraction: Double? = nil,
    geminiUsageFraction: Double? = nil,
    argonUsageFraction: Double? = nil,
    claudeUsageFraction: Double? = nil,
    activeFillFraction: Double? = nil,
    geminiFillFraction: Double? = nil,
    argonFillFraction: Double? = nil,
    claudeFillFraction: Double? = nil,
    showMenuBarSpend: Bool = false,
    menuBarSpendSource: MenuBarSpendSource = .gcpToday,
    spendAmount: Double = 0.0,
    gcpTodayCost: Double? = nil,
    gcpTotalCost: Double? = nil,
    todayCost: Double? = nil
) -> NSImage {
    AgyMenuBarRenderer.makeAntigravityImage(
        queriesToday: queriesToday,
        litColor: litColor,
        showUsage: showUsage,
        selectedModelForIcon: selectedModelForIcon,
        activeUsageFraction: activeUsageFraction,
        geminiUsageFraction: geminiUsageFraction,
        argonUsageFraction: argonUsageFraction,
        claudeUsageFraction: claudeUsageFraction,
        activeFillFraction: activeFillFraction,
        geminiFillFraction: geminiFillFraction,
        argonFillFraction: argonFillFraction,
        claudeFillFraction: claudeFillFraction,
        showMenuBarSpend: showMenuBarSpend,
        menuBarSpendSource: menuBarSpendSource,
        spendAmount: spendAmount,
        gcpTodayCost: gcpTodayCost,
        gcpTotalCost: gcpTotalCost,
        todayCost: todayCost
    )
}


