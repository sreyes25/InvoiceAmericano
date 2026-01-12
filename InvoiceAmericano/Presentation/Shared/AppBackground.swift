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
    @State private var drift = false

    var body: some View {
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
        .onAppear {
            withAnimation(.easeInOut(duration: 12).repeatForever(autoreverses: true)) {
                drift.toggle()
            }
        }
    }
}
