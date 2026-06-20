//
//  AppTheme.swift
//  agy-usage-stats
//
//  Created on 2026-06-20.
//

import SwiftUI

// MARK: - AppTheme

enum AppTheme: String, Codable, CaseIterable, Identifiable {
    case midnight
    case sandstone
    case arctic
    case dusk

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .midnight: return "Midnight"
        case .sandstone: return "Sandstone"
        case .arctic: return "Arctic"
        case .dusk: return "Dusk"
        }
    }

    var iconName: String {
        switch self {
        case .midnight: return "moon.stars.fill"
        case .sandstone: return "sun.dust.fill"
        case .arctic: return "snowflake"
        case .dusk: return "sunset.fill"
        }
    }
}

// MARK: - ThemeColors

struct ThemeColors {
    let cardFill: Color
    let cardStroke: Color
    let cardFillHovered: Color
    let cardStrokeHovered: Color

    let surfacePrimary: Color
    let surfaceSecondary: Color

    let textPrimary: Color
    let textSecondary: Color
    let textTertiary: Color

    let divider: Color
    let searchBackground: Color
    let searchBorderFocused: Color

    let badgeBackground: Color
    let progressTrack: Color

    let geminiAccent: Color
    let claudeAccent: Color
    let costGreen: Color
    let dangerRed: Color
    let linkBlue: Color

    // MARK: - Factory

    static func colors(for theme: AppTheme, colorScheme: ColorScheme) -> ThemeColors {
        switch theme {
        case .midnight:
            return midnightColors()
        case .sandstone:
            return sandstoneColors()
        case .arctic:
            return arcticColors()
        case .dusk:
            return duskColors()
        }
    }

    // MARK: - Midnight (Dark)

    private static func midnightColors() -> ThemeColors {
        ThemeColors(
            cardFill: Color.white.opacity(0.035),
            cardStroke: Color.white.opacity(0.06),
            cardFillHovered: Color.white.opacity(0.07),
            cardStrokeHovered: Color.white.opacity(0.12),
            surfacePrimary: Color.white.opacity(0.01),
            surfaceSecondary: Color.white.opacity(0.015),
            textPrimary: Color.white.opacity(0.9),
            textSecondary: Color.white.opacity(0.55),
            textTertiary: Color.white.opacity(0.3),
            divider: Color.white.opacity(0.05),
            searchBackground: Color.white.opacity(0.025),
            searchBorderFocused: Color.blue.opacity(0.35),
            badgeBackground: Color.white.opacity(0.06),
            progressTrack: Color.white.opacity(0.04),
            geminiAccent: Color(red: 0.75, green: 0.6, blue: 1.0),
            claudeAccent: Color(red: 1.0, green: 0.65, blue: 0.35),
            costGreen: Color(red: 0.25, green: 0.85, blue: 0.45),
            dangerRed: Color(red: 1.0, green: 0.35, blue: 0.35),
            linkBlue: Color(red: 0.35, green: 0.6, blue: 1.0)
        )
    }

    // MARK: - Sandstone (Light)

    private static func sandstoneColors() -> ThemeColors {
        ThemeColors(
            cardFill: Color(red: 0.965, green: 0.945, blue: 0.915),
            cardStroke: Color(red: 0.88, green: 0.855, blue: 0.81),
            cardFillHovered: Color(red: 0.95, green: 0.925, blue: 0.89),
            cardStrokeHovered: Color(red: 0.82, green: 0.79, blue: 0.74),
            surfacePrimary: Color(red: 0.98, green: 0.965, blue: 0.94),
            surfaceSecondary: Color(red: 0.97, green: 0.95, blue: 0.92),
            textPrimary: Color(red: 0.16, green: 0.12, blue: 0.08),
            textSecondary: Color(red: 0.42, green: 0.37, blue: 0.30),
            textTertiary: Color(red: 0.58, green: 0.53, blue: 0.46),
            divider: Color(red: 0.87, green: 0.84, blue: 0.80),
            searchBackground: Color(red: 0.96, green: 0.94, blue: 0.91),
            searchBorderFocused: Color(red: 0.50, green: 0.35, blue: 0.70),
            badgeBackground: Color(red: 0.92, green: 0.89, blue: 0.85),
            progressTrack: Color(red: 0.92, green: 0.895, blue: 0.86),
            geminiAccent: Color(red: 0.40, green: 0.22, blue: 0.75),
            claudeAccent: Color(red: 0.80, green: 0.32, blue: 0.10),
            costGreen: Color(red: 0.10, green: 0.50, blue: 0.24),
            dangerRed: Color(red: 0.78, green: 0.18, blue: 0.18),
            linkBlue: Color(red: 0.18, green: 0.38, blue: 0.72)
        )
    }

    // MARK: - Arctic (Light)

    private static func arcticColors() -> ThemeColors {
        ThemeColors(
            cardFill: Color(red: 0.935, green: 0.955, blue: 0.98),
            cardStroke: Color(red: 0.84, green: 0.87, blue: 0.92),
            cardFillHovered: Color(red: 0.91, green: 0.935, blue: 0.965),
            cardStrokeHovered: Color(red: 0.76, green: 0.80, blue: 0.86),
            surfacePrimary: Color(red: 0.96, green: 0.97, blue: 0.99),
            surfaceSecondary: Color(red: 0.945, green: 0.96, blue: 0.98),
            textPrimary: Color(red: 0.10, green: 0.13, blue: 0.20),
            textSecondary: Color(red: 0.35, green: 0.40, blue: 0.50),
            textTertiary: Color(red: 0.52, green: 0.57, blue: 0.65),
            divider: Color(red: 0.84, green: 0.87, blue: 0.91),
            searchBackground: Color(red: 0.93, green: 0.95, blue: 0.975),
            searchBorderFocused: Color(red: 0.25, green: 0.50, blue: 0.90),
            badgeBackground: Color(red: 0.89, green: 0.92, blue: 0.96),
            progressTrack: Color(red: 0.89, green: 0.915, blue: 0.95),
            geminiAccent: Color(red: 0.35, green: 0.18, blue: 0.78),
            claudeAccent: Color(red: 0.82, green: 0.28, blue: 0.05),
            costGreen: Color(red: 0.05, green: 0.48, blue: 0.28),
            dangerRed: Color(red: 0.82, green: 0.15, blue: 0.22),
            linkBlue: Color(red: 0.15, green: 0.42, blue: 0.85)
        )
    }

    // MARK: - Dusk (Dark)

    private static func duskColors() -> ThemeColors {
        ThemeColors(
            cardFill: Color(red: 0.10, green: 0.09, blue: 0.18),
            cardStroke: Color(red: 0.18, green: 0.16, blue: 0.28),
            cardFillHovered: Color(red: 0.13, green: 0.12, blue: 0.22),
            cardStrokeHovered: Color(red: 0.24, green: 0.21, blue: 0.35),
            surfacePrimary: Color(red: 0.06, green: 0.05, blue: 0.12),
            surfaceSecondary: Color(red: 0.08, green: 0.07, blue: 0.15),
            textPrimary: Color(red: 0.92, green: 0.88, blue: 0.82),
            textSecondary: Color(red: 0.60, green: 0.55, blue: 0.48),
            textTertiary: Color(red: 0.40, green: 0.36, blue: 0.30),
            divider: Color(red: 0.16, green: 0.14, blue: 0.24),
            searchBackground: Color(red: 0.09, green: 0.08, blue: 0.16),
            searchBorderFocused: Color(red: 0.85, green: 0.60, blue: 0.20),
            badgeBackground: Color(red: 0.14, green: 0.12, blue: 0.22),
            progressTrack: Color(red: 0.12, green: 0.10, blue: 0.20),
            geminiAccent: Color(red: 0.70, green: 0.55, blue: 1.0),
            claudeAccent: Color(red: 0.95, green: 0.60, blue: 0.25),
            costGreen: Color(red: 0.30, green: 0.80, blue: 0.45),
            dangerRed: Color(red: 1.0, green: 0.40, blue: 0.35),
            linkBlue: Color(red: 0.45, green: 0.65, blue: 1.0)
        )
    }
}
