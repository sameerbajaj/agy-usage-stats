//
//  AppTheme.swift
//  agy-usage-stats
//

import SwiftUI

// MARK: - AppTheme

public enum AppTheme: String, Codable, CaseIterable, Identifiable {
    case midnight   // dark
    case sandstone  // light – warm cream
    case arctic     // light – cool slate-blue
    case dusk       // dark – deep indigo

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .midnight:  return "Midnight"
        case .sandstone: return "Sandstone"
        case .arctic:    return "Arctic"
        case .dusk:      return "Dusk"
        }
    }

    public var iconName: String {
        switch self {
        case .midnight:  return "moon.stars.fill"
        case .sandstone: return "sun.dust.fill"
        case .arctic:    return "snowflake"
        case .dusk:      return "sunset.fill"
        }
    }

    /// Whether this theme should force the system into dark appearance
    public var preferredColorScheme: ColorScheme {
        switch self {
        case .midnight, .dusk: return .dark
        case .sandstone, .arctic: return .light
        }
    }
}

// MARK: - ThemeColors

public struct ThemeColors {
    // Card surfaces
    public let cardFill: Color
    public let cardStroke: Color
    public let cardFillHovered: Color
    public let cardStrokeHovered: Color

    // App background
    public let surfacePrimary: Color
    public let surfaceSecondary: Color

    // Text
    public let textPrimary: Color
    public let textSecondary: Color
    public let textTertiary: Color

    // UI chrome
    public let divider: Color
    public let searchBackground: Color
    public let searchBorderFocused: Color
    public let badgeBackground: Color
    public let progressTrack: Color

    // Accent colors
    public let geminiAccent: Color
    public let claudeAccent: Color
    public let costGreen: Color
    public let dangerRed: Color
    public let linkBlue: Color

    // MARK: - Factory

    /// Returns a ThemeColors for the given AppTheme.
    /// colorScheme is kept for API compatibility but themes are self-contained.
    public static func colors(for theme: AppTheme, colorScheme: ColorScheme = .light) -> ThemeColors {
        switch theme {
        case .midnight:  return midnightColors()
        case .sandstone: return sandstoneColors()
        case .arctic:    return arcticColors()
        case .dusk:      return duskColors()
        }
    }

    // MARK: - Midnight (Dark — near-black navy)
    // Deep navy-black background with cool blue-tinted cards and vivid accents.

    private static func midnightColors() -> ThemeColors {
        ThemeColors(
            cardFill:            Color(red: 0.09, green: 0.10, blue: 0.15),
            cardStroke:          Color(red: 0.20, green: 0.22, blue: 0.32),
            cardFillHovered:     Color(red: 0.12, green: 0.13, blue: 0.20),
            cardStrokeHovered:   Color(red: 0.30, green: 0.33, blue: 0.48),
            surfacePrimary:      Color(red: 0.05, green: 0.06, blue: 0.10),
            surfaceSecondary:    Color(red: 0.07, green: 0.08, blue: 0.13),
            textPrimary:         Color(red: 0.92, green: 0.93, blue: 0.97),
            textSecondary:       Color(red: 0.55, green: 0.58, blue: 0.68),
            textTertiary:        Color(red: 0.35, green: 0.37, blue: 0.47),
            divider:             Color(red: 0.16, green: 0.18, blue: 0.26),
            searchBackground:    Color(red: 0.08, green: 0.09, blue: 0.14),
            searchBorderFocused: Color(red: 0.40, green: 0.55, blue: 1.00),
            badgeBackground:     Color(red: 0.14, green: 0.15, blue: 0.22),
            progressTrack:       Color(red: 0.12, green: 0.13, blue: 0.20),
            geminiAccent:        Color(red: 0.60, green: 0.55, blue: 1.00),
            claudeAccent:        Color(red: 1.00, green: 0.62, blue: 0.32),
            costGreen:           Color(red: 0.18, green: 0.90, blue: 0.50),
            dangerRed:           Color(red: 1.00, green: 0.35, blue: 0.40),
            linkBlue:            Color(red: 0.38, green: 0.62, blue: 1.00)
        )
    }

    // MARK: - Sandstone (Light — warm parchment)
    // Warm cream/parchment background. Rich contrast, earthy tones.
    // Readable without eye strain; like aged paper.

    private static func sandstoneColors() -> ThemeColors {
        ThemeColors(
            cardFill:            Color(red: 0.96, green: 0.93, blue: 0.88),
            cardStroke:          Color(red: 0.84, green: 0.79, blue: 0.72),
            cardFillHovered:     Color(red: 0.94, green: 0.90, blue: 0.84),
            cardStrokeHovered:   Color(red: 0.75, green: 0.69, blue: 0.60),
            surfacePrimary:      Color(red: 0.97, green: 0.95, blue: 0.91),
            surfaceSecondary:    Color(red: 0.93, green: 0.90, blue: 0.85),
            textPrimary:         Color(red: 0.15, green: 0.12, blue: 0.07),
            textSecondary:       Color(red: 0.40, green: 0.34, blue: 0.25),
            textTertiary:        Color(red: 0.58, green: 0.52, blue: 0.43),
            divider:             Color(red: 0.83, green: 0.78, blue: 0.70),
            searchBackground:    Color(red: 0.98, green: 0.96, blue: 0.92),
            searchBorderFocused: Color(red: 0.48, green: 0.30, blue: 0.72),
            badgeBackground:     Color(red: 0.88, green: 0.84, blue: 0.78),
            progressTrack:       Color(red: 0.88, green: 0.84, blue: 0.77),
            geminiAccent:        Color(red: 0.40, green: 0.20, blue: 0.76),
            claudeAccent:        Color(red: 0.80, green: 0.30, blue: 0.08),
            costGreen:           Color(red: 0.10, green: 0.48, blue: 0.22),
            dangerRed:           Color(red: 0.78, green: 0.16, blue: 0.16),
            linkBlue:            Color(red: 0.18, green: 0.36, blue: 0.70)
        )
    }

    // MARK: - Arctic (Light — cool crisp white-blue)
    // Icy, clean, Scandinavian. White with cool blue-gray undertones.
    // High contrast, airy feeling, very readable.

    private static func arcticColors() -> ThemeColors {
        ThemeColors(
            cardFill:            Color(red: 0.94, green: 0.96, blue: 0.99),
            cardStroke:          Color(red: 0.80, green: 0.85, blue: 0.92),
            cardFillHovered:     Color(red: 0.90, green: 0.93, blue: 0.97),
            cardStrokeHovered:   Color(red: 0.68, green: 0.75, blue: 0.86),
            surfacePrimary:      Color(red: 0.96, green: 0.97, blue: 0.99),
            surfaceSecondary:    Color(red: 0.91, green: 0.93, blue: 0.97),
            textPrimary:         Color(red: 0.09, green: 0.12, blue: 0.20),
            textSecondary:       Color(red: 0.34, green: 0.40, blue: 0.52),
            textTertiary:        Color(red: 0.52, green: 0.58, blue: 0.68),
            divider:             Color(red: 0.80, green: 0.84, blue: 0.90),
            searchBackground:    Color(red: 0.98, green: 0.98, blue: 1.00),
            searchBorderFocused: Color(red: 0.22, green: 0.48, blue: 0.90),
            badgeBackground:     Color(red: 0.87, green: 0.90, blue: 0.95),
            progressTrack:       Color(red: 0.87, green: 0.90, blue: 0.95),
            geminiAccent:        Color(red: 0.30, green: 0.15, blue: 0.82),
            claudeAccent:        Color(red: 0.82, green: 0.26, blue: 0.04),
            costGreen:           Color(red: 0.04, green: 0.46, blue: 0.28),
            dangerRed:           Color(red: 0.82, green: 0.12, blue: 0.20),
            linkBlue:            Color(red: 0.12, green: 0.40, blue: 0.86)
        )
    }

    // MARK: - Dusk (Dark — deep warm indigo-purple)
    // Rich purple-indigo dusk sky. Warm dark, amber accents, amber-gold highlights.
    // A dark theme that feels warm rather than cold.

    private static func duskColors() -> ThemeColors {
        ThemeColors(
            cardFill:            Color(red: 0.12, green: 0.10, blue: 0.20),
            cardStroke:          Color(red: 0.22, green: 0.18, blue: 0.34),
            cardFillHovered:     Color(red: 0.16, green: 0.13, blue: 0.26),
            cardStrokeHovered:   Color(red: 0.32, green: 0.26, blue: 0.46),
            surfacePrimary:      Color(red: 0.08, green: 0.06, blue: 0.14),
            surfaceSecondary:    Color(red: 0.10, green: 0.08, blue: 0.18),
            textPrimary:         Color(red: 0.94, green: 0.90, blue: 0.84),
            textSecondary:       Color(red: 0.62, green: 0.56, blue: 0.48),
            textTertiary:        Color(red: 0.42, green: 0.37, blue: 0.32),
            divider:             Color(red: 0.20, green: 0.16, blue: 0.28),
            searchBackground:    Color(red: 0.10, green: 0.08, blue: 0.17),
            searchBorderFocused: Color(red: 0.88, green: 0.60, blue: 0.22),
            badgeBackground:     Color(red: 0.18, green: 0.14, blue: 0.26),
            progressTrack:       Color(red: 0.15, green: 0.12, blue: 0.22),
            geminiAccent:        Color(red: 0.75, green: 0.58, blue: 1.00),
            claudeAccent:        Color(red: 0.98, green: 0.62, blue: 0.28),
            costGreen:           Color(red: 0.28, green: 0.85, blue: 0.50),
            dangerRed:           Color(red: 1.00, green: 0.38, blue: 0.38),
            linkBlue:            Color(red: 0.52, green: 0.68, blue: 1.00)
        )
    }
}
