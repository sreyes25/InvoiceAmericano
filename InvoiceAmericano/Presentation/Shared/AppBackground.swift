//
//  AppBackground.swift
//  InvoiceAmericano
//
//  Created by Sergio Reyes on 1/12/26.
//

import SwiftUI

struct AppBackground<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .background {
                AnimatedNeutralBackground()
                    .ignoresSafeArea()          // ✅ only the background ignores safe area
                    .allowsHitTesting(false)    // ✅ never blocks taps/scroll
            }
    }
}

struct AnimatedNeutralBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var drift = false
    @State private var breathe = false

    var body: some View {
        ZStack {
            if colorScheme == .light {
                lightModeBackground
            } else {
                darkModeBackground
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 12).repeatForever(autoreverses: true)) {
                drift.toggle()
            }
            withAnimation(.easeInOut(duration: 8).repeatForever(autoreverses: true)) {
                breathe.toggle()
            }
        }
    }

    private var lightModeBackground: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(.systemGroupedBackground),
                    Color(.secondarySystemGroupedBackground).opacity(0.96)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(Color.red.opacity(0.10))
                .frame(width: 560, height: 560)
                .blur(radius: 70)
                .offset(x: drift ? 170 : -150, y: drift ? -210 : -120)

            Circle()
                .fill(Color.orange.opacity(0.11))
                .frame(width: 520, height: 520)
                .blur(radius: 65)
                .offset(x: drift ? -150 : 180, y: drift ? 250 : 170)

            Circle()
                .fill(Color.indigo.opacity(0.06))
                .frame(width: 620, height: 620)
                .blur(radius: 72)
                .offset(x: drift ? -90 : 110, y: drift ? -280 : -220)

            RoundedRectangle(cornerRadius: 180, style: .continuous)
                .stroke(Color.white.opacity(0.28), lineWidth: 1.0)
                .frame(width: 880, height: 880)
                .blur(radius: 1.5)
                .rotationEffect(.degrees(14))
                .scaleEffect(breathe ? 1.03 : 0.97)
                .offset(x: -190, y: -330)

            LinearGradient(
                colors: [
                    Color.white.opacity(0.35),
                    Color.white.opacity(0.0),
                    Color.white.opacity(0.16)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .blendMode(.plusLighter)
        }
    }

    private var darkModeBackground: some View {
        ZStack {
            Color(.systemGroupedBackground)

            Circle()
                .fill(Color.gray.opacity(0.06))
                .frame(width: 520, height: 520)
                .blur(radius: 55)
                .offset(x: drift ? 120 : -140, y: drift ? -80 : -160)

            Circle()
                .fill(Color.gray.opacity(0.10))
                .frame(width: 480, height: 480)
                .blur(radius: 55)
                .offset(x: drift ? -120 : 140, y: drift ? 220 : 160)

            Circle()
                .fill(Color.gray.opacity(0.08))
                .frame(width: 600, height: 600)
                .blur(radius: 60)
                .offset(x: drift ? -40 : 80, y: drift ? -260 : -220)
        }
    }
}
