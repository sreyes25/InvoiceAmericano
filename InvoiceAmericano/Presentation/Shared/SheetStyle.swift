//
//  SheetStyle.swift
//  InvoiceAmericano
//
//  Created by Codex on 3/4/26.
//

import SwiftUI

enum IASheetBackgroundStyle {
    case clear
    case glass
    case system
}

extension View {
    @ViewBuilder
    func iaStandardSheetPresentation(
        detents: Set<PresentationDetent> = [.large],
        cornerRadius: CGFloat = 28,
        background: IASheetBackgroundStyle = .clear
    ) -> some View {
        let base = self
            .presentationDetents(detents)
            .presentationCornerRadius(cornerRadius)
            .presentationDragIndicator(.visible)
            .presentationContentInteraction(.scrolls)

        switch background {
        case .clear:
            base.presentationBackground(.clear)
        case .glass:
            base.presentationBackground(.ultraThinMaterial)
        case .system:
            base
        }
    }

    func iaSheetNavigationChrome() -> some View {
        self
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarBackgroundVisibility(.visible, for: .navigationBar)
    }
}
