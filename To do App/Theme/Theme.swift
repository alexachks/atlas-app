//
//  Theme.swift
//  To do App
//
//  Created by Oleksandr Pushkarov on 12/15/25.
//

import SwiftUI

enum Theme {
    // MARK: - Brand Colors
    static let primaryBlue = Color(red: 91/255, green: 134/255, blue: 229/255)
    static let primaryPurple = Color(red: 139/255, green: 92/255, blue: 246/255)

    static let accentOrange = Color(red: 255/255, green: 107/255, blue: 107/255)
    static let accentYellow = Color(red: 255/255, green: 217/255, blue: 61/255)

    static let successGreen = Color(red: 6/255, green: 214/255, blue: 160/255)
    static let successCyan = Color(red: 0/255, green: 180/255, blue: 216/255)

    // MARK: - Gradients
    static let primaryGradient = LinearGradient(
        colors: [primaryBlue, primaryPurple],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let accentGradient = LinearGradient(
        colors: [accentOrange, accentYellow],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let successGradient = LinearGradient(
        colors: [successGreen, successCyan],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let warmGradient = LinearGradient(
        colors: [
            Color(red: 251/255, green: 146/255, blue: 60/255),
            Color(red: 252/255, green: 211/255, blue: 77/255)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let coolGradient = LinearGradient(
        colors: [
            Color(red: 59/255, green: 130/255, blue: 246/255),
            Color(red: 147/255, green: 51/255, blue: 234/255)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // MARK: - Card Gradients (subtle for backgrounds)
    static let cardGradient1 = LinearGradient(
        colors: [
            Color(red: 99/255, green: 102/255, blue: 241/255, opacity: 0.1),
            Color(red: 168/255, green: 85/255, blue: 247/255, opacity: 0.05)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let cardGradient2 = LinearGradient(
        colors: [
            Color(red: 236/255, green: 72/255, blue: 153/255, opacity: 0.1),
            Color(red: 239/255, green: 68/255, blue: 68/255, opacity: 0.05)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let cardGradient3 = LinearGradient(
        colors: [
            Color(red: 34/255, green: 211/255, blue: 238/255, opacity: 0.1),
            Color(red: 6/255, green: 182/255, blue: 212/255, opacity: 0.05)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

// MARK: - View Modifiers
struct GradientCardModifier: ViewModifier {
    let gradient: LinearGradient

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(gradient)
                    .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 4)
            )
    }
}

struct GlassMorphismModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 4)
            )
    }
}

// MARK: - View Extensions
extension View {
    func gradientCard(_ gradient: LinearGradient) -> some View {
        modifier(GradientCardModifier(gradient: gradient))
    }

    func glassMorphism() -> some View {
        modifier(GlassMorphismModifier())
    }
}
