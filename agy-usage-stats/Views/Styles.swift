//
//  Styles.swift
//  agy-usage-stats
//
//  Created by Antigravity on 6/14/26.
//

import SwiftUI

// MARK: - Premium Card Styling
public struct PremiumCardModifier: ViewModifier {
    public var isHovered: Bool
    public var accentColor: Color?
    
    public init(isHovered: Bool = false, accentColor: Color? = nil) {
        self.isHovered = isHovered
        self.accentColor = accentColor
    }
    
    public func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(
                        LinearGradient(
                            colors: isHovered
                                ? [Color.white.opacity(0.05), Color.white.opacity(0.02)]
                                : [Color.white.opacity(0.03), Color.white.opacity(0.015)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(
                        LinearGradient(
                            colors: isHovered && accentColor != nil
                                ? [accentColor!.opacity(0.35), accentColor!.opacity(0.1)]
                                : [Color.white.opacity(0.06), Color.white.opacity(0.03)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
    }
}

extension View {
    public func premiumCardStyle(isHovered: Bool = false, accentColor: Color? = nil) -> some View {
        modifier(PremiumCardModifier(isHovered: isHovered, accentColor: accentColor))
    }
}
