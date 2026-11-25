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
    var viewModel: AgyStatsViewModel

    private var statusColor: Color {
        var fractions: [Double] = []
        if let gf = viewModel.geminiUsageFraction {
            fractions.append(gf)
        }
        if let carb = viewModel.carbonUsageFraction {
            fractions.append(carb)
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
            .onAppear {
                // Trigger stats loading and adaptive quota polling on label launch
                viewModel.setup()
            }
    }

    private var menuBarTooltip: String {
        var lines: [String] = ["Antigravity CLI Stats"]
        let subEmail = viewModel.stats.quotaInfo?.email ?? viewModel.activeConsumerEmail
        if let subEmail, !subEmail.isEmpty {
            if let plan = viewModel.stats.quotaInfo?.plan, !plan.isEmpty {
                lines.append("Account: \(subEmail) (\(plan))")
            } else {
                lines.append("Account: \(subEmail)")
            }
        } else if let plan = viewModel.stats.quotaInfo?.plan, !plan.isEmpty {
            lines.append("Account: \(plan)")
        }
        lines.append("Active: \(viewModel.activeModelDisplayName)")
        if let g = viewModel.geminiUsageFraction {
            let paceSuffix = viewModel.geminiNumberPacing.map { " (\($0.deltaLabel) · \($0.budgetLabel))" } ?? ""
            lines.append("Gemini: \(QuotaPacing.formatSmartPercent(g * 100))\(paceSuffix)")
        }
        if let carb = viewModel.carbonUsageFraction {
            lines.append("Carbon: \(QuotaPacing.formatSmartPercent(carb * 100))")
        }
        if let a = viewModel.argonUsageFraction {
            lines.append("Argon: \(QuotaPacing.formatSmartPercent(a * 100))")
        }
        if let c = viewModel.claudeUsageFraction {
            let paceSuffix = viewModel.claudeNumberPacing.map { " (\($0.deltaLabel) · \($0.budgetLabel))" } ?? ""
            lines.append("Claude: \(QuotaPacing.formatSmartPercent(c * 100))\(paceSuffix)")
        }
        if viewModel.showMuseTracking, let muse = viewModel.museQuota?.normalizedForCurrentTime() {
            let resetPart = muse.compactCountdown().map { " · resets in \($0)" } ?? ""
            let pacePart = muse.pacing().map { " · \($0.deltaLabel), \($0.budgetLabel)" } ?? ""
            lines.append("Muse (\(muse.planName)): \(QuotaPacing.formatSmartPercent(muse.remainingPercent)) left (\(QuotaPacing.formatSmartPercent(muse.percentUsed)) used)\(resetPart)\(pacePart)")
            if let topupText = muse.topupTokensLeftText {
                lines.append("Muse Additional Tokens: \(topupText)")
            }
        }
        if viewModel.showGcpTab && (viewModel.stats.gcpTodayCost > 0 || viewModel.stats.gcpTotalCost > 0) {
            lines.append(String(format: "GCP Cloud Spend: $%.2f today ($%.2f total)", viewModel.stats.gcpTodayCost, viewModel.stats.gcpTotalCost))
        }
        lines.append("Queries Today: \(viewModel.stats.queriesToday)")
        return lines.joined(separator: "\n")
    }
}

// MARK: - Presentation Resolver

public struct CompactMenuBarSlotData: Equatable {
    public enum Kind: Equatable {
        case antigravity
        case muse
    }

    public let kind: Kind
    public let remainingFraction: Double
    public let displayPercent: Double
    public let paceMarkerFraction: Double?
    public let pacing: QuotaPacing?
    public let resetShortText: String?
    public let accentColor: NSColor
    public let isIdle: Bool

    public init(
        kind: Kind = .antigravity,
        remainingFraction: Double,
        displayPercent: Double,
        paceMarkerFraction: Double? = nil,
        pacing: QuotaPacing? = nil,
        resetShortText: String? = nil,
        accentColor: NSColor = MenuBarPresentationResolver.healthyGreenColor,
        isIdle: Bool = false
    ) {
        self.kind = kind
        self.remainingFraction = max(0.0, min(1.0, remainingFraction))
        self.displayPercent = displayPercent
        self.paceMarkerFraction = paceMarkerFraction
        self.pacing = pacing
        self.resetShortText = resetShortText
        self.accentColor = accentColor
        self.isIdle = isIdle
    }
}

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

    public struct MuseBadge: Equatable {
        public let iconColor: NSColor
        public let ringFraction: Double
        public let ringColor: NSColor
        public let paceMarkerFraction: Double?
        public let text: String
        public let textColor: NSColor

        public init(
            iconColor: NSColor,
            ringFraction: Double = 1.0,
            ringColor: NSColor = MenuBarPresentationResolver.healthyGreenColor,
            paceMarkerFraction: Double? = nil,
            text: String,
            textColor: NSColor
        ) {
            self.iconColor = iconColor
            self.ringFraction = ringFraction
            self.ringColor = ringColor
            self.paceMarkerFraction = paceMarkerFraction
            self.text = text
            self.textColor = textColor
        }
    }

    public let text: String
    public let textColor: NSColor
    public let gaugeStyle: GaugeStyle
    public let paceMarkerFraction: Double?
    public let spendBadge: SpendBadge?
    public let museBadge: MuseBadge?

    public var hasText: Bool { !text.isEmpty }

    public init(
        text: String,
        textColor: NSColor,
        gaugeStyle: GaugeStyle,
        paceMarkerFraction: Double? = nil,
        spendBadge: SpendBadge? = nil,
        museBadge: MuseBadge? = nil
    ) {
        self.text = text
        self.textColor = textColor
        self.gaugeStyle = gaugeStyle
        self.paceMarkerFraction = paceMarkerFraction
        self.spendBadge = spendBadge
        self.museBadge = museBadge
    }
}

public enum MenuBarPresentationResolver {
    public static let geminiColor = NSColor(red: 0.65, green: 0.45, blue: 1.0, alpha: 1.0)
    public static let carbonColor = NSColor(red: 0.20, green: 0.85, blue: 0.70, alpha: 1.0)
    public static let argonColor = NSColor(red: 0.0, green: 0.82, blue: 0.95, alpha: 1.0)
    public static let claudeColor = NSColor(red: 1.0, green: 0.5, blue: 0.2, alpha: 1.0)
    public static let gcpBlueColor = NSColor(red: 0.26, green: 0.52, blue: 0.96, alpha: 1.0)
    public static let apiGreenColor = NSColor(red: 0.15, green: 0.85, blue: 0.55, alpha: 1.0)
    public static let museIndigoColor = NSColor(red: 0.45, green: 0.42, blue: 1.0, alpha: 1.0)

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

    public static func metricColor(for fraction: Double, pacing: QuotaPacing?, colorByPacing: Bool) -> NSColor {
        guard colorByPacing, let pacing else {
            return healthColor(for: fraction)
        }
        switch pacing.status {
        case .surplus, .onTrack:
            return healthyGreenColor
        case .behind:
            return pacing.deltaFraction <= -0.15 ? lowRedColor : warningAmberColor
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

    public static let compactMenuBarFont: NSFont = {
        let baseDesc = NSFont.systemFont(ofSize: 8.5, weight: .bold).fontDescriptor.withDesign(.rounded)
        if let baseDesc {
            let monoDesc = baseDesc.addingAttributes([
                .featureSettings: [
                    [
                        NSFontDescriptor.FeatureKey.typeIdentifier: kNumberSpacingType,
                        NSFontDescriptor.FeatureKey.selectorIdentifier: kMonospacedNumbersSelector
                    ]
                ]
            ])
            return NSFont(descriptor: monoDesc, size: 8.5) ?? NSFont.monospacedDigitSystemFont(ofSize: 8.5, weight: .bold)
        }
        return NSFont.monospacedDigitSystemFont(ofSize: 8.5, weight: .bold)
    }()

    public static let compactTimeFont: NSFont = {
        let baseDesc = NSFont.systemFont(ofSize: 8.5, weight: .bold).fontDescriptor.withDesign(.rounded)
        if let baseDesc {
            let monoDesc = baseDesc.addingAttributes([
                .featureSettings: [
                    [
                        NSFontDescriptor.FeatureKey.typeIdentifier: kNumberSpacingType,
                        NSFontDescriptor.FeatureKey.selectorIdentifier: kMonospacedNumbersSelector
                    ]
                ]
            ])
            return NSFont(descriptor: monoDesc, size: 8.5) ?? NSFont.monospacedDigitSystemFont(ofSize: 8.5, weight: .bold)
        }
        return NSFont.monospacedDigitSystemFont(ofSize: 8.5, weight: .bold)
    }()

    public static func resolveQuotaText(
        geminiFraction: Double?,
        carbonFraction: Double? = nil,
        argonFraction: Double? = nil,
        claudeFraction: Double?,
        gcpTodayCost: Double? = nil
    ) -> String {
        var parts: [String] = []
        if let gf = geminiFraction {
            parts.append(String(format: "G:%.0f%%", gf * 100))
        }
        if let carb = carbonFraction {
            parts.append(String(format: "Cb:%.0f%%", carb * 100))
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
        carbonUsageFraction: Double? = nil,
        carbonFillFraction: Double? = nil,
        argonUsageFraction: Double? = nil,
        argonFillFraction: Double? = nil,
        claudeUsageFraction: Double?,
        claudeFillFraction: Double?,
        gcpTodayCost: Double? = nil,
        showSpend: Bool = false,
        spendSource: MenuBarSpendSource = .gcpToday,
        spendAmount: Double = 0.0,
        gcpTotalCost: Double? = nil,
        todayCost: Double? = nil,
        showMuseBadge: Bool = false,
        museRemainingFraction: Double? = nil,
        musePercentUsed: Double? = nil,
        museResetShortText: String? = nil,
        museDisplayStyle: MuseMenuBarDisplayStyle = .remainingPercent,
        showPaceIndicator: Bool = true,
        colorByPacing: Bool = false,
        activePaceMarkerFraction: Double? = nil,
        activeNumberPacing: QuotaPacing? = nil,
        activeRingPacing: QuotaPacing? = nil,
        musePacing: QuotaPacing? = nil
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

        let museBadge: IconPresentationState.MuseBadge?
        if showMuseBadge, let remFrac = museRemainingFraction {
            let clampedRem = max(0.0, min(1.0, remFrac))
            let usedPct = musePercentUsed ?? ((1.0 - clampedRem) * 100.0)
            let museText: String
            switch museDisplayStyle {
            case .remainingPercent:
                museText = String(format: "%.0f%%", clampedRem * 100.0)
            case .usedPercent:
                museText = String(format: "%.0f%%", usedPct)
            case .remainingAndReset:
                let pctPart = String(format: "%.0f%%", clampedRem * 100.0)
                if let resetShort = museResetShortText, !resetShort.isEmpty {
                    museText = "\(pctPart) \(resetShort)"
                } else {
                    museText = pctPart
                }
            }
            let museColor = metricColor(for: clampedRem, pacing: musePacing, colorByPacing: colorByPacing)
            museBadge = IconPresentationState.MuseBadge(
                iconColor: museIndigoColor,
                ringFraction: clampedRem,
                ringColor: museColor,
                paceMarkerFraction: showPaceIndicator ? musePacing?.expectedRemainingFraction : nil,
                text: museText,
                textColor: museColor
            )
        } else {
            museBadge = nil
        }

        let agyPaceMarker: Double? = showPaceIndicator ? (activePaceMarkerFraction ?? activeRingPacing?.expectedRemainingFraction) : nil

        func finish(_ text: String, _ textColor: NSColor, _ gaugeStyle: IconPresentationState.GaugeStyle) -> IconPresentationState {
            let resolvedMarker: Double?
            if case .single = gaugeStyle {
                resolvedMarker = agyPaceMarker
            } else {
                resolvedMarker = nil
            }
            return IconPresentationState(
                text: text,
                textColor: textColor,
                gaugeStyle: gaugeStyle,
                paceMarkerFraction: resolvedMarker,
                spendBadge: badge,
                museBadge: museBadge
            )
        }

        guard showUsage else {
            return finish("", litColor, .none)
        }

        switch selectedModel {
        case .active:
            if let fraction = activeUsageFraction {
                let pctText = String(format: "%.0f%%", fraction * 100)
                let fill = activeFillFraction ?? fraction
                let textColor = metricColor(for: fraction, pacing: activeNumberPacing, colorByPacing: colorByPacing)
                let strokeColor = metricColor(for: fill, pacing: activeRingPacing, colorByPacing: colorByPacing)
                return finish(pctText, textColor, .single(fraction: fill, strokeColor: strokeColor))
            } else if queriesToday > 0 {
                let pctText = "\(queriesToday)q"
                return finish(pctText, litColor, .single(fraction: 1.0, strokeColor: litColor))
            } else {
                return finish("", litColor, .none)
            }

        case .mostDepleted:
            var candidates: [(fraction: Double, fill: Double)] = []
            if let gf = geminiUsageFraction {
                candidates.append((fraction: gf, fill: geminiFillFraction ?? gf))
            }
            if let carb = carbonUsageFraction {
                candidates.append((fraction: carb, fill: carbonFillFraction ?? carb))
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
                let textColor = metricColor(for: fraction, pacing: activeNumberPacing, colorByPacing: colorByPacing)
                let strokeColor = metricColor(for: fill, pacing: activeRingPacing, colorByPacing: colorByPacing)
                return finish(pctText, textColor, .single(fraction: fill, strokeColor: strokeColor))
            } else if queriesToday > 0 {
                let pctText = "\(queriesToday)q"
                return finish(pctText, litColor, .single(fraction: 1.0, strokeColor: litColor))
            } else {
                return finish("", litColor, .none)
            }

        case .gemini:
            if let fraction = geminiUsageFraction {
                let pctText = String(format: "%.0f%%", fraction * 100)
                let fill = geminiFillFraction ?? fraction
                let textColor = metricColor(for: fraction, pacing: activeNumberPacing, colorByPacing: colorByPacing)
                let strokeColor = metricColor(for: fill, pacing: activeRingPacing, colorByPacing: colorByPacing)
                return finish(pctText, textColor, .single(fraction: fill, strokeColor: strokeColor))
            } else {
                return finish("", litColor, .none)
            }

        case .carbon:
            if let fraction = carbonUsageFraction {
                let pctText = String(format: "%.0f%%", fraction * 100)
                let fill = carbonFillFraction ?? fraction
                let textColor = metricColor(for: fraction, pacing: activeNumberPacing, colorByPacing: colorByPacing)
                let strokeColor = metricColor(for: fill, pacing: activeRingPacing, colorByPacing: colorByPacing)
                return finish(pctText, textColor, .single(fraction: fill, strokeColor: strokeColor))
            } else {
                return finish("", litColor, .none)
            }

        case .argon:
            if let fraction = argonUsageFraction {
                let pctText = String(format: "%.0f%%", fraction * 100)
                let fill = argonFillFraction ?? fraction
                let textColor = metricColor(for: fraction, pacing: activeNumberPacing, colorByPacing: colorByPacing)
                let strokeColor = metricColor(for: fill, pacing: activeRingPacing, colorByPacing: colorByPacing)
                return finish(pctText, textColor, .single(fraction: fill, strokeColor: strokeColor))
            } else {
                return finish("", litColor, .none)
            }

        case .claude:
            if let fraction = claudeUsageFraction {
                let pctText = String(format: "%.0f%%", fraction * 100)
                let fill = claudeFillFraction ?? fraction
                let textColor = metricColor(for: fraction, pacing: activeNumberPacing, colorByPacing: colorByPacing)
                let strokeColor = metricColor(for: fill, pacing: activeRingPacing, colorByPacing: colorByPacing)
                return finish(pctText, textColor, .single(fraction: fill, strokeColor: strokeColor))
            } else {
                return finish("", litColor, .none)
            }

        case .gcp:
            if let cost = gcpTodayCost, cost > 0 {
                let costText = String(format: "$%.2f", cost)
                let fill = activeFillFraction ?? activeUsageFraction ?? 1.0
                return finish(costText, gcpBlueColor, .single(fraction: fill, strokeColor: gcpBlueColor))
            } else if let fraction = activeUsageFraction {
                let pctText = String(format: "%.0f%%", fraction * 100)
                let fill = activeFillFraction ?? fraction
                return finish(pctText, gcpBlueColor, .single(fraction: fill, strokeColor: gcpBlueColor))
            } else if queriesToday > 0 {
                let pctText = "\(queriesToday)q"
                return finish(pctText, gcpBlueColor, .single(fraction: 1.0, strokeColor: gcpBlueColor))
            } else {
                return finish("", litColor, .none)
            }

        case .both:
            if let gf = geminiUsageFraction, let cf = claudeUsageFraction {
                let pctText = String(format: "G:%.0f%% C:%.0f%%", gf * 100, cf * 100)
                let gFill = geminiFillFraction ?? gf
                let cFill = claudeFillFraction ?? cf
                return finish(pctText, NSColor.textColor, .both(geminiFraction: gFill, claudeFraction: cFill))
            } else if let gf = geminiUsageFraction {
                let pctText = String(format: "%.0f%%", gf * 100)
                let gFill = geminiFillFraction ?? gf
                let textColor = healthColor(for: gf)
                let strokeColor = healthColor(for: gFill)
                return finish(pctText, textColor, .single(fraction: gFill, strokeColor: strokeColor))
            } else if let cf = claudeUsageFraction {
                let pctText = String(format: "%.0f%%", cf * 100)
                let cFill = claudeFillFraction ?? cf
                let textColor = healthColor(for: cf)
                let strokeColor = healthColor(for: cFill)
                return finish(pctText, textColor, .single(fraction: cFill, strokeColor: strokeColor))
            } else {
                return finish("", litColor, .none)
            }

        case .allThree:
            var parts: [String] = []
            if let gf = geminiUsageFraction { parts.append(String(format: "G:%.0f%%", gf * 100)) }
            if let af = argonUsageFraction { parts.append(String(format: "A:%.0f%%", af * 100)) }
            if let cf = claudeUsageFraction { parts.append(String(format: "C:%.0f%%", cf * 100)) }

            guard !parts.isEmpty else {
                return finish("", litColor, .none)
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

            return finish(pctText, NSColor.textColor, gauge)
        }
    }
}

// MARK: - Menu Bar Drawing

public enum AgyMenuBarRenderer {
    private static var cachedAntigravityIcon: (key: String, image: NSImage)? = nil
    private static var cachedCompactIcon: (key: String, image: NSImage)? = nil

    public static func makeCompactStackedImage(
        slots: [CompactMenuBarSlotData],
        barsOnly: Bool = false,
        detail: CompactMenuBarDetail = .barAndPercent,
        showRowIcons: Bool = true,
        museIconStyle: MuseMenuBarIconStyle = .bear,
        colorByPacing: Bool = false,
        showMenuBarSpend: Bool = false,
        menuBarSpendSource: MenuBarSpendSource = .gcpToday,
        spendAmount: Double = 0.0,
        gcpTodayCost: Double? = nil,
        gcpTotalCost: Double? = nil,
        todayCost: Double? = nil
    ) -> NSImage {
        let activeSlots = Array(slots.prefix(2))
        let showBar = barsOnly || detail != .percentOnly
        let showPercent = !barsOnly
        let showTime = !barsOnly && detail == .barPercentAndTime
        let includeIcons = showRowIcons && !barsOnly

        // Resolve optional spend badge
        let spendBadge: IconPresentationState.SpendBadge?
        if showMenuBarSpend {
            let iconType: IconPresentationState.SpendBadge.IconType
            let iconColor: NSColor
            let amount: Double
            switch menuBarSpendSource {
            case .gcpToday:
                iconType = .cloud
                iconColor = MenuBarPresentationResolver.gcpBlueColor
                amount = gcpTodayCost ?? spendAmount
            case .gcpTotal:
                iconType = .cloud
                iconColor = MenuBarPresentationResolver.gcpBlueColor
                amount = gcpTotalCost ?? spendAmount
            case .apiToday:
                iconType = .dollar
                iconColor = MenuBarPresentationResolver.apiGreenColor
                amount = todayCost ?? spendAmount
            }
            spendBadge = IconPresentationState.SpendBadge(
                icon: iconType,
                iconColor: iconColor,
                text: String(format: "$%.2f", amount),
                textColor: NSColor.labelColor
            )
        } else {
            spendBadge = nil
        }

        // Build deterministic cache key
        let slotKeys = activeSlots.map { s in
            let rf = Int((s.remainingFraction * 100.0).rounded())
            let dp = Int((s.displayPercent * 10.0).rounded())
            let pm = s.paceMarkerFraction.map { Int(($0 * 100.0).rounded()) } ?? -1
            let k = (s.kind == .muse) ? "m" : "a"
            return "\(k)_\(rf)_\(dp)_\(pm)_\(s.resetShortText ?? "")_\(s.pacing?.status.hashValue ?? 0)"
        }.joined(separator: "|")
        let cacheKey = "compact_\(barsOnly)_\(detail.rawValue)_\(includeIcons)_\(museIconStyle.rawValue)_\(colorByPacing)_\(slotKeys)_\(spendBadge?.text ?? "")_\(spendBadge?.icon.hashValue ?? 0)"
        if let cached = cachedCompactIcon, cached.key == cacheKey {
            return cached.image
        }

        let h: CGFloat = 18.0
        let pctFont = MenuBarPresentationResolver.compactMenuBarFont
        let timeFont = MenuBarPresentationResolver.compactTimeFont
        let spendFont = MenuBarPresentationResolver.menuBarFont

        let iconColWidth: CGFloat = includeIcons ? 7.5 : 0.0
        let iconGap: CGFloat = includeIcons ? 3.0 : 0.0
        let barWidth: CGFloat = barsOnly ? 20.0 : 20.0
        let barHeight: CGFloat = barsOnly ? 4.8 : 4.2

        let pctStrings: [String] = activeSlots.map { String(format: "%.0f%%", $0.displayPercent.rounded()) }
        let timeStrings: [String] = activeSlots.map { $0.resetShortText ?? "" }

        var maxPctWidth: CGFloat = 0
        if showPercent {
            for s in pctStrings {
                let w = (s as NSString).size(withAttributes: [.font: pctFont]).width
                maxPctWidth = max(maxPctWidth, ceil(w))
            }
        }

        var maxTimeWidth: CGFloat = 0
        if showTime {
            for s in timeStrings where !s.isEmpty {
                let w = (s as NSString).size(withAttributes: [.font: timeFont]).width
                maxTimeWidth = max(maxTimeWidth, ceil(w))
            }
        }

        // Measure optional spend badge
        var cloudSymbolImg: NSImage? = nil
        var dollarSymbolImg: NSImage? = nil
        var spendAmountStr = ""
        var spendAttributes: [NSAttributedString.Key: Any] = [:]
        var spendTextSize = NSSize.zero
        if let spend = spendBadge {
            spendAttributes = [.font: spendFont, .foregroundColor: spend.textColor]
            if spend.icon == .cloud {
                let config = NSImage.SymbolConfiguration(pointSize: 9.0, weight: .semibold)
                    .applying(.init(paletteColors: [spend.iconColor]))
                cloudSymbolImg = NSImage(systemSymbolName: "cloud.fill", accessibilityDescription: nil)?.withSymbolConfiguration(config)
                spendAmountStr = spend.text
            } else {
                let config = NSImage.SymbolConfiguration(pointSize: 9.0, weight: .bold)
                    .applying(.init(paletteColors: [spend.iconColor]))
                dollarSymbolImg = NSImage(systemSymbolName: "dollarsign", accessibilityDescription: nil)?.withSymbolConfiguration(config)
                spendAmountStr = spend.text.replacingOccurrences(of: "$", with: "")
            }
            spendTextSize = (spendAmountStr as NSString).size(withAttributes: spendAttributes)
        }

        var totalW: CGFloat = 1.5
        if includeIcons {
            totalW += iconColWidth + iconGap
        }
        if showBar {
            totalW += barWidth
        }
        if showPercent {
            if showBar { totalW += 3.5 }
            totalW += maxPctWidth
        }
        if showTime && maxTimeWidth > 0 {
            totalW += 3.5 + maxTimeWidth
        }
        if spendBadge != nil {
            totalW += 3.5 + 1.0 + 3.5
            if let cloud = cloudSymbolImg {
                totalW += cloud.size.width + 2.5
            } else if let dollar = dollarSymbolImg {
                totalW += dollar.size.width + 1.5
            }
            totalW += spendTextSize.width
        }
        totalW += 1.5

        let rowCentersY: [CGFloat] = activeSlots.count == 2 ? [13.3, 4.7] : [9.0]

        let img = NSImage(size: NSSize(width: max(20.0, ceil(totalW)), height: h), flipped: false) { _ in
            let iconCenterX: CGFloat = 1.5 + (iconColWidth / 2.0)
            let barStartX: CGFloat = 1.5 + (includeIcons ? iconColWidth + iconGap : 0.0)
            let pctColX: CGFloat = barStartX + (showBar ? barWidth + 3.5 : 0.0)
            let timeColX: CGFloat = pctColX + maxPctWidth + 3.5

            for (idx, slot) in activeSlots.enumerated() {
                let cy = rowCentersY[idx]
                let rowColor = MenuBarPresentationResolver.metricColor(
                    for: slot.remainingFraction,
                    pacing: slot.pacing,
                    colorByPacing: colorByPacing
                )

                if includeIcons {
                    switch slot.kind {
                    case .antigravity:
                        drawMiniAgyChevron(center: NSPoint(x: iconCenterX, y: cy), color: NSColor.labelColor.withAlphaComponent(0.90))
                    case .muse:
                        switch museIconStyle {
                        case .bear:
                            drawCuteBearHead(center: NSPoint(x: iconCenterX, y: cy), scale: 1.0)
                        case .letterM:
                            drawMuseMonogram(center: NSPoint(x: iconCenterX, y: cy), color: MenuBarPresentationResolver.museIndigoColor, scale: 1.05)
                        }
                    }
                }

                if showBar {
                    let barY = cy - (barHeight / 2.0)
                    let trackRect = NSRect(x: barStartX, y: barY, width: barWidth, height: barHeight)
                    let trackPath = NSBezierPath(roundedRect: trackRect, xRadius: barHeight / 2.0, yRadius: barHeight / 2.0)
                    NSColor.labelColor.withAlphaComponent(0.20).setFill()
                    trackPath.fill()

                    let fillW = barWidth * CGFloat(slot.remainingFraction)
                    if fillW > 0.6 {
                        let clampedFillW = max(min(barWidth, fillW), min(barWidth, barHeight * 0.75))
                        let fillRect = NSRect(x: barStartX, y: barY, width: clampedFillW, height: barHeight)
                        let fillPath = NSBezierPath(roundedRect: fillRect, xRadius: barHeight / 2.0, yRadius: barHeight / 2.0)
                        rowColor.setFill()
                        fillPath.fill()
                    }

                    if let paceFrac = slot.paceMarkerFraction {
                        let rawTickX = barStartX + barWidth * CGFloat(max(0.0, min(1.0, paceFrac)))
                        let tickX = min(max(barStartX + 1.5, rawTickX), barStartX + barWidth - 1.5)
                        let tickH = barHeight + 2.2
                        let tickRect = NSRect(x: tickX - 0.65, y: cy - (tickH / 2.0), width: 1.3, height: tickH)
                        let tickPath = NSBezierPath(roundedRect: tickRect, xRadius: 0.65, yRadius: 0.65)
                        NSColor.labelColor.withAlphaComponent(0.95).setFill()
                        tickPath.fill()
                    }
                }

                if showPercent {
                    let str = pctStrings[idx]
                    let attrs: [NSAttributedString.Key: Any] = [.font: pctFont, .foregroundColor: rowColor]
                    let size = (str as NSString).size(withAttributes: attrs)
                    let drawX = pctColX + (maxPctWidth - size.width)
                    let drawY = cy - (size.height / 2.0) + 0.3
                    str.draw(at: NSPoint(x: drawX, y: drawY), withAttributes: attrs)
                }

                if showTime && maxTimeWidth > 0 {
                    let tStr = timeStrings[idx]
                    if !tStr.isEmpty {
                        // Crisp high-contrast adaptive color (bright soft white in dark mode, dark charcoal in light mode)
                        let tAttrs: [NSAttributedString.Key: Any] = [.font: timeFont, .foregroundColor: NSColor.labelColor.withAlphaComponent(0.88)]
                        let tSize = (tStr as NSString).size(withAttributes: tAttrs)
                        let drawX = timeColX + (maxTimeWidth - tSize.width)
                        let drawY = cy - (tSize.height / 2.0) + 0.3
                        tStr.draw(at: NSPoint(x: drawX, y: drawY), withAttributes: tAttrs)
                    }
                }
            }

            if spendBadge != nil {
                var currentX = pctColX + (showPercent ? maxPctWidth : 0.0) + (showTime && maxTimeWidth > 0 ? 3.5 + maxTimeWidth : 0.0)
                if !showPercent && showBar {
                    currentX = barStartX + barWidth
                }
                let sepX = currentX + 3.5
                let sepRect = NSRect(x: sepX, y: (h - 8.0) / 2.0, width: 1.0, height: 8.0)
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

                let spendY = (h - spendTextSize.height) / 2.0
                spendAmountStr.draw(at: NSPoint(x: currentX, y: spendY), withAttributes: spendAttributes)
            }

            return true
        }
        img.isTemplate = false
        cachedCompactIcon = (cacheKey, img)
        return img
    }

    public static func makeAntigravityImage(
        queriesToday: Int,
        litColor: Color,
        showUsage: Bool = false,
        selectedModelForIcon: IconModelSelection = .active,
        activeUsageFraction: Double? = nil,
        geminiUsageFraction: Double? = nil,
        carbonUsageFraction: Double? = nil,
        argonUsageFraction: Double? = nil,
        claudeUsageFraction: Double? = nil,
        activeFillFraction: Double? = nil,
        geminiFillFraction: Double? = nil,
        carbonFillFraction: Double? = nil,
        argonFillFraction: Double? = nil,
        claudeFillFraction: Double? = nil,
        showMenuBarSpend: Bool = false,
        menuBarSpendSource: MenuBarSpendSource = .gcpToday,
        spendAmount: Double = 0.0,
        gcpTodayCost: Double? = nil,
        gcpTotalCost: Double? = nil,
        todayCost: Double? = nil,
        showMuseBadge: Bool = false,
        museRemainingFraction: Double? = nil,
        musePercentUsed: Double? = nil,
        museResetShortText: String? = nil,
        museDisplayStyle: MuseMenuBarDisplayStyle = .remainingPercent,
        museIconStyle: MuseMenuBarIconStyle = .bear,
        showPaceIndicator: Bool = true,
        colorByPacing: Bool = false,
        activePaceMarkerFraction: Double? = nil,
        activeNumberPacing: QuotaPacing? = nil,
        activeRingPacing: QuotaPacing? = nil,
        musePacing: QuotaPacing? = nil
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
            carbonUsageFraction: carbonUsageFraction,
            carbonFillFraction: carbonFillFraction,
            argonUsageFraction: argonUsageFraction,
            argonFillFraction: argonFillFraction,
            claudeUsageFraction: claudeUsageFraction,
            claudeFillFraction: claudeFillFraction,
            gcpTodayCost: gcpTodayCost,
            showSpend: showMenuBarSpend,
            spendSource: menuBarSpendSource,
            spendAmount: spendAmount,
            gcpTotalCost: gcpTotalCost,
            todayCost: todayCost,
            showMuseBadge: showMuseBadge,
            museRemainingFraction: museRemainingFraction,
            musePercentUsed: musePercentUsed,
            museResetShortText: museResetShortText,
            museDisplayStyle: museDisplayStyle,
            showPaceIndicator: showPaceIndicator,
            colorByPacing: colorByPacing,
            activePaceMarkerFraction: activePaceMarkerFraction,
            activeNumberPacing: activeNumberPacing,
            activeRingPacing: activeRingPacing,
            musePacing: musePacing
        )

        let agyPaceBucket = presentation.paceMarkerFraction.map { Int(($0 * 100.0).rounded()) } ?? -1
        let musePaceBucket = presentation.museBadge?.paceMarkerFraction.map { Int(($0 * 100.0).rounded()) } ?? -1
        let museFillBucket = presentation.museBadge.map { Int(($0.ringFraction * 100.0).rounded()) } ?? -1
        let cacheKey = "\(queriesToday)_\(litColor.description)_\(presentation.text)_\(presentation.textColor.description)_\(presentation.gaugeStyle)_p\(agyPaceBucket)_\(presentation.spendBadge?.icon.hashValue ?? 0)_\(presentation.spendBadge?.text ?? "")_\(presentation.spendBadge?.iconColor.description ?? "")_\(presentation.museBadge?.text ?? "")_\(presentation.museBadge?.textColor.description ?? "")_mf\(museFillBucket)_mp\(musePaceBucket)_mi\(museIconStyle.rawValue)"
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

        // Measure Muse ring + badge
        let museRingSlotWidth: CGFloat = 16.0
        var museTextStr: String = ""
        var museAttributes: [NSAttributedString.Key: Any] = [:]
        var museTextSize = NSSize.zero

        if let muse = presentation.museBadge {
            museAttributes = [.font: font, .foregroundColor: muse.textColor]
            museTextStr = muse.text
            museTextSize = (museTextStr as NSString).size(withAttributes: museAttributes)
        }

        // Calculate total image width
        var totalW: CGFloat = gaugeSlotWidth
        if presentation.hasText {
            totalW += 3.5 + pctTextSize.width
        }
        if presentation.spendBadge != nil {
            totalW += 3.5 + 1.0 + 3.5 // Divider line
            if let cloud = cloudSymbolImg {
                totalW += cloud.size.width + 2.5
            } else if let dollar = dollarSymbolImg {
                totalW += dollar.size.width + 1.5
            }
            totalW += spendTextSize.width
        }
        if presentation.museBadge != nil {
            totalW += 3.5 + 1.0 + 3.5 // Divider line
            totalW += museRingSlotWidth + 3.5
            totalW += museTextSize.width
        }
        if presentation.hasText || presentation.spendBadge != nil || presentation.museBadge != nil {
            totalW += 2.0
        }

        let img = NSImage(size: NSSize(width: max(16.0, totalW), height: h), flipped: false) { _ in
            let isLit = queriesToday > 0

            // 1. Draw Gauges or Antigravity A-icon
            switch presentation.gaugeStyle {
            case .single(let fraction, let strokeColor):
                drawGauge(
                    center: NSPoint(x: 8.0, y: 8.0),
                    radius: 5.5,
                    fraction: fraction,
                    strokeColor: strokeColor,
                    paceMarkerFraction: presentation.paceMarkerFraction
                )
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

            // 4. Draw Muse Ring Gauge (Divider + Ring with Cursive 'm' & Pace Tick + %)
            if let muse = presentation.museBadge {
                let sepX = currentX + 3.5
                let sepRect = NSRect(x: sepX, y: (h - 7.0) / 2.0, width: 1.0, height: 7.0)
                let sepPath = NSBezierPath(roundedRect: sepRect, xRadius: 0.5, yRadius: 0.5)
                NSColor.labelColor.withAlphaComponent(0.22).setFill()
                sepPath.fill()
                currentX = sepX + 1.0 + 3.5

                drawMuseGauge(
                    center: NSPoint(x: currentX + 8.0, y: 8.0),
                    radius: 5.5,
                    fraction: muse.ringFraction,
                    strokeColor: muse.ringColor,
                    markColor: muse.iconColor,
                    iconStyle: museIconStyle,
                    paceMarkerFraction: muse.paceMarkerFraction
                )
                currentX += museRingSlotWidth + 3.5

                museTextStr.draw(at: NSPoint(x: currentX, y: textY), withAttributes: museAttributes)
                currentX += museTextSize.width
            }

            return true
        }
        img.isTemplate = false
        cachedAntigravityIcon = (cacheKey, img)
        return img
    }

    public static func drawGauge(
        center: NSPoint,
        radius: CGFloat,
        fraction: Double,
        strokeColor: NSColor,
        chevronSize: CGFloat = 2.5,
        paceMarkerFraction: Double? = nil
    ) {
        // Draw Background Track
        let trackPath = NSBezierPath()
        trackPath.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
        trackPath.lineWidth = 1.2
        NSColor.labelColor.withAlphaComponent(0.15).setStroke()
        trackPath.stroke()

        // Draw Progress Arc
        let clamped = max(0.0, min(1.0, fraction))
        if clamped > 0.002 {
            let progressPath = NSBezierPath()
            let startAngle: CGFloat = 90.0
            let endAngle: CGFloat = 90.0 - CGFloat(clamped * 360.0)
            progressPath.appendArc(withCenter: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: true)
            progressPath.lineWidth = 1.6
            progressPath.lineCapStyle = .round
            strokeColor.setStroke()
            progressPath.stroke()
        }

        // Draw Steady-Pace Radial Tick on Perimeter
        if let paceFrac = paceMarkerFraction {
            drawPaceTick(center: center, radius: radius, expectedFraction: paceFrac)
        }

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

    public static func drawMuseGauge(
        center: NSPoint,
        radius: CGFloat,
        fraction: Double,
        strokeColor: NSColor,
        markColor: NSColor,
        iconStyle: MuseMenuBarIconStyle = .bear,
        paceMarkerFraction: Double? = nil
    ) {
        // Draw Background Track
        let trackPath = NSBezierPath()
        trackPath.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
        trackPath.lineWidth = 1.2
        NSColor.labelColor.withAlphaComponent(0.15).setStroke()
        trackPath.stroke()

        // Draw Progress Arc
        let clamped = max(0.0, min(1.0, fraction))
        if clamped > 0.002 {
            let progressPath = NSBezierPath()
            let startAngle: CGFloat = 90.0
            let endAngle: CGFloat = 90.0 - CGFloat(clamped * 360.0)
            progressPath.appendArc(withCenter: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: true)
            progressPath.lineWidth = 1.6
            progressPath.lineCapStyle = .round
            strokeColor.setStroke()
            progressPath.stroke()
        }

        // Draw Steady-Pace Radial Tick on Perimeter
        if let paceFrac = paceMarkerFraction {
            drawPaceTick(center: center, radius: radius, expectedFraction: paceFrac)
        }

        // Draw Muse Avatar (Cute Bear or Crisp 2-Arch "m") inside center
        switch iconStyle {
        case .bear:
            drawCuteBearHead(center: center, scale: 0.92)
        case .letterM:
            drawMuseMonogram(center: center, color: markColor, scale: 1.0)
        }
    }

    private static func drawMiniAgyChevron(center: NSPoint, color: NSColor) {
        let chevron = NSBezierPath()
        chevron.move(to: NSPoint(x: center.x - 2.6, y: center.y - 1.5))
        chevron.line(to: NSPoint(x: center.x, y: center.y + 1.8))
        chevron.line(to: NSPoint(x: center.x + 2.6, y: center.y - 1.5))
        chevron.lineWidth = 1.35
        chevron.lineCapStyle = .round
        chevron.lineJoinStyle = .round
        color.setStroke()
        chevron.stroke()
    }

    private static func drawMuseMonogram(center: NSPoint, color: NSColor, scale: CGFloat) {
        let mPath = NSBezierPath()
        let cx = center.x
        let cy = center.y
        let w: CGFloat = 2.4 * scale
        let topY = cy + 1.45 * scale
        let botY = cy - 1.45 * scale
        mPath.move(to: NSPoint(x: cx - w, y: botY))
        mPath.line(to: NSPoint(x: cx - w, y: topY - 0.8 * scale))
        mPath.curve(
            to: NSPoint(x: cx, y: topY - 0.8 * scale),
            controlPoint1: NSPoint(x: cx - w, y: topY + 0.55 * scale),
            controlPoint2: NSPoint(x: cx, y: topY + 0.55 * scale)
        )
        mPath.line(to: NSPoint(x: cx, y: botY))
        mPath.move(to: NSPoint(x: cx, y: topY - 0.8 * scale))
        mPath.curve(
            to: NSPoint(x: cx + w, y: topY - 0.8 * scale),
            controlPoint1: NSPoint(x: cx, y: topY + 0.55 * scale),
            controlPoint2: NSPoint(x: cx + w, y: topY + 0.55 * scale)
        )
        mPath.line(to: NSPoint(x: cx + w, y: botY))
        mPath.lineWidth = 0.9
        mPath.lineCapStyle = .round
        mPath.lineJoinStyle = .round
        color.setStroke()
        mPath.stroke()
    }

    /// Crisp geometric cute bear head silhouette (warm honey-caramel ears + round head + cream snout + dark eyes/nose)
    /// designed specifically to read unmistakably at 7x7pt on Retina macOS menu bars in both Light and Dark modes.
    private static func drawCuteBearHead(center: NSPoint, scale: CGFloat) {
        let cx = center.x
        let cy = center.y
        let furColor = NSColor(red: 0.80, green: 0.56, blue: 0.35, alpha: 1.0)
        let innerEarColor = NSColor(red: 0.95, green: 0.82, blue: 0.68, alpha: 1.0)
        let snoutColor = NSColor(red: 0.96, green: 0.86, blue: 0.74, alpha: 1.0)
        let featureColor = NSColor(red: 0.22, green: 0.13, blue: 0.08, alpha: 1.0)

        let earR: CGFloat = 1.35 * scale
        let earOffsetX: CGFloat = 2.05 * scale
        let earOffsetY: CGFloat = 1.85 * scale

        // Outer ears
        furColor.setFill()
        NSBezierPath(ovalIn: NSRect(x: cx - earOffsetX - earR, y: cy + earOffsetY - earR, width: earR * 2, height: earR * 2)).fill()
        NSBezierPath(ovalIn: NSRect(x: cx + earOffsetX - earR, y: cy + earOffsetY - earR, width: earR * 2, height: earR * 2)).fill()

        // Inner ear highlights
        let innerR: CGFloat = 0.65 * scale
        innerEarColor.setFill()
        NSBezierPath(ovalIn: NSRect(x: cx - earOffsetX - innerR, y: cy + earOffsetY - innerR, width: innerR * 2, height: innerR * 2)).fill()
        NSBezierPath(ovalIn: NSRect(x: cx + earOffsetX - innerR, y: cy + earOffsetY - innerR, width: innerR * 2, height: innerR * 2)).fill()

        // Main round head
        let headRx: CGFloat = 2.75 * scale
        let headRy: CGFloat = 2.45 * scale
        let headCy = cy - 0.35 * scale
        furColor.setFill()
        NSBezierPath(ovalIn: NSRect(x: cx - headRx, y: headCy - headRy, width: headRx * 2, height: headRy * 2)).fill()

        // Cream snout
        let snoutW: CGFloat = 2.3 * scale
        let snoutH: CGFloat = 1.55 * scale
        snoutColor.setFill()
        NSBezierPath(ovalIn: NSRect(x: cx - snoutW / 2, y: headCy - snoutH * 0.88, width: snoutW, height: snoutH)).fill()

        // Eyes & tiny nose
        featureColor.setFill()
        let eyeR: CGFloat = 0.44 * scale
        let eyeX: CGFloat = 0.98 * scale
        let eyeY: CGFloat = headCy + 0.55 * scale
        NSBezierPath(ovalIn: NSRect(x: cx - eyeX - eyeR, y: eyeY - eyeR, width: eyeR * 2, height: eyeR * 2)).fill()
        NSBezierPath(ovalIn: NSRect(x: cx + eyeX - eyeR, y: eyeY - eyeR, width: eyeR * 2, height: eyeR * 2)).fill()

        let noseW: CGFloat = 0.95 * scale
        let noseH: CGFloat = 0.65 * scale
        NSBezierPath(ovalIn: NSRect(x: cx - noseW / 2, y: headCy - 0.52 * scale, width: noseW, height: noseH)).fill()
    }

    private static func drawPaceTick(center: NSPoint, radius: CGFloat, expectedFraction: Double) {
        let clamped = max(0.02, min(0.98, expectedFraction))
        let angleRad = (90.0 - CGFloat(clamped * 360.0)) * .pi / 180.0
        let dx = cos(angleRad)
        let dy = sin(angleRad)
        let rInner = radius - 1.4
        let rOuter = radius + 1.85

        let tickPath = NSBezierPath()
        tickPath.move(to: NSPoint(x: center.x + dx * rInner, y: center.y + dy * rInner))
        tickPath.line(to: NSPoint(x: center.x + dx * rOuter, y: center.y + dy * rOuter))
        tickPath.lineWidth = 1.4
        tickPath.lineCapStyle = .round
        NSColor.labelColor.withAlphaComponent(0.95).setStroke()
        tickPath.stroke()
    }
}

public func makeAntigravityImage(
    queriesToday: Int,
    litColor: Color,
    showUsage: Bool = false,
    selectedModelForIcon: IconModelSelection = .active,
    activeUsageFraction: Double? = nil,
    geminiUsageFraction: Double? = nil,
    carbonUsageFraction: Double? = nil,
    argonUsageFraction: Double? = nil,
    claudeUsageFraction: Double? = nil,
    activeFillFraction: Double? = nil,
    geminiFillFraction: Double? = nil,
    carbonFillFraction: Double? = nil,
    argonFillFraction: Double? = nil,
    claudeFillFraction: Double? = nil,
    showMenuBarSpend: Bool = false,
    menuBarSpendSource: MenuBarSpendSource = .gcpToday,
    spendAmount: Double = 0.0,
    gcpTodayCost: Double? = nil,
    gcpTotalCost: Double? = nil,
    todayCost: Double? = nil,
    showMuseBadge: Bool = false,
    museRemainingFraction: Double? = nil,
    musePercentUsed: Double? = nil,
    museResetShortText: String? = nil,
    museDisplayStyle: MuseMenuBarDisplayStyle = .remainingPercent,
    showPaceIndicator: Bool = true,
    colorByPacing: Bool = false,
    activePaceMarkerFraction: Double? = nil,
    activeNumberPacing: QuotaPacing? = nil,
    activeRingPacing: QuotaPacing? = nil,
    musePacing: QuotaPacing? = nil
) -> NSImage {
    AgyMenuBarRenderer.makeAntigravityImage(
        queriesToday: queriesToday,
        litColor: litColor,
        showUsage: showUsage,
        selectedModelForIcon: selectedModelForIcon,
        activeUsageFraction: activeUsageFraction,
        geminiUsageFraction: geminiUsageFraction,
        carbonUsageFraction: carbonUsageFraction,
        argonUsageFraction: argonUsageFraction,
        claudeUsageFraction: claudeUsageFraction,
        activeFillFraction: activeFillFraction,
        geminiFillFraction: geminiFillFraction,
        carbonFillFraction: carbonFillFraction,
        argonFillFraction: argonFillFraction,
        claudeFillFraction: claudeFillFraction,
        showMenuBarSpend: showMenuBarSpend,
        menuBarSpendSource: menuBarSpendSource,
        spendAmount: spendAmount,
        gcpTodayCost: gcpTodayCost,
        gcpTotalCost: gcpTotalCost,
        todayCost: todayCost,
        showMuseBadge: showMuseBadge,
        museRemainingFraction: museRemainingFraction,
        musePercentUsed: musePercentUsed,
        museResetShortText: museResetShortText,
        museDisplayStyle: museDisplayStyle,
        showPaceIndicator: showPaceIndicator,
        colorByPacing: colorByPacing,
        activePaceMarkerFraction: activePaceMarkerFraction,
        activeNumberPacing: activeNumberPacing,
        activeRingPacing: activeRingPacing,
        musePacing: musePacing
    )
}


