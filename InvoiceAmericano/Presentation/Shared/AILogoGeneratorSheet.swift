//
//  AILogoGeneratorSheet.swift
//  InvoiceAmericano
//
//  Created by Codex on 3/4/26.
//

import SwiftUI
import UIKit

struct AILogoGeneratorSheet: View {
    let businessName: String
    let tagline: String
    let accentHex: String?
    let defaultIndustry: String?
    let onSelect: (UIImage) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var prompt: String = ""
    @State private var generated: [UIImage] = []
    @State private var selectedIndex: Int?
    @State private var loading = false
    @State private var errorText: String?
    @State private var selectedStyle: String = "Clean"
    @State private var selectedTheme: String = "Professional"
    @State private var selectedIndustry: String = "General Business"

    private let styleOptions = ["Clean", "Bold", "Modern", "Classic", "Minimal", "Badge"]
    private let themeOptions = ["Professional", "Friendly", "Premium", "Playful", "Reliable"]
    private let industryOptions = [
        "General Business", "Technology", "Construction", "Healthcare", "Finance",
        "Legal", "Real Estate", "Retail", "Hospitality", "Automotive", "Beauty",
        "Education", "Fitness", "Logistics", "Creative"
    ]

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Describe your logo")
                        .font(.headline)

                    TextField("Example: Minimal red wrench + house icon, white background", text: $prompt, axis: .vertical)
                        .lineLimit(2...4)
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color(.secondarySystemBackground))
                        )

                    chipSection(title: "Style", options: styleOptions, selection: $selectedStyle)
                    chipSection(title: "Theme", options: themeOptions, selection: $selectedTheme)
                    pickerSection(title: "Industry", selection: $selectedIndustry, options: industryOptions)

                    Button {
                        Task { await generate() }
                    } label: {
                        HStack(spacing: 8) {
                            if loading { ProgressView() }
                            Text(loading ? "Generating..." : "Generate logo options")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(loading)

                    if let errorText {
                        Text(errorText)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }

                    if !generated.isEmpty {
                        Text("Select one")
                            .font(.headline)
                            .padding(.top, 4)

                        LazyVGrid(columns: columns, spacing: 10) {
                            ForEach(Array(generated.enumerated()), id: \.offset) { index, image in
                                Button {
                                    selectedIndex = index
                                } label: {
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(height: 140)
                                        .frame(maxWidth: .infinity)
                                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .strokeBorder(
                                                    selectedIndex == index ? Color.accentColor : Color.clear,
                                                    lineWidth: 3
                                                )
                                        }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(16)
            }
            .navigationTitle("AI Logo")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                let clean = (defaultIndustry ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if !clean.isEmpty {
                    selectedIndustry = clean
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Use selected") {
                        guard let index = selectedIndex, generated.indices.contains(index) else { return }
                        onSelect(generated[index])
                        dismiss()
                    }
                    .disabled(selectedIndex == nil)
                }
            }
            .iaSheetNavigationChrome()
        }
        .iaStandardSheetPresentation(detents: [.large], background: .glass)
    }

    private func chipSection(title: String, options: [String], selection: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], spacing: 8) {
                ForEach(options, id: \.self) { option in
                    let isOn = selection.wrappedValue == option
                    Button {
                        selection.wrappedValue = option
                    } label: {
                        Text(option)
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(isOn ? Color.accentColor.opacity(0.22) : Color(.secondarySystemBackground))
                            )
                            .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func pickerSection(title: String, selection: Binding<String>, options: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            Menu {
                ForEach(options, id: \.self) { option in
                    Button(option) { selection.wrappedValue = option }
                }
            } label: {
                HStack {
                    Text(selection.wrappedValue)
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(.secondarySystemBackground))
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func buildPrompt() -> String {
        let cleanBusiness = businessName.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanTagline = tagline.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanUserPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let colorHint = (accentHex?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false) ? (accentHex ?? "#0A84FF") : "#0A84FF"
        let styleHint = selectedStyle
        let themeHint = selectedTheme
        let industryHint = selectedIndustry

        var parts: [String] = []
        if cleanUserPrompt.isEmpty {
            if cleanBusiness.isEmpty {
                parts.append("Create a professional business logo.")
            } else {
                parts.append("Create a professional logo for '\(cleanBusiness)'.")
            }
        } else {
            parts.append(cleanUserPrompt)
        }

        parts.append("Style: \(styleHint).")
        parts.append("Theme: \(themeHint).")
        parts.append("Industry: \(industryHint).")
        if !cleanTagline.isEmpty {
            parts.append("Use this tagline as inspiration: '\(cleanTagline)'.")
        }
        parts.append("Primary brand color: \(colorHint).")
        parts.append("Deliver a transparent background PNG logo with no square background, no mockup scene, no watermark, and no extra text unless it is the business name.")
        return parts.joined(separator: " ")
    }

    private func generate() async {
        await MainActor.run {
            loading = true
            errorText = nil
            selectedIndex = nil
        }

        do {
            let result = try await OpenAILogoService.generateLogos(prompt: buildPrompt(), count: 2)
            await MainActor.run {
                generated = result
                selectedIndex = result.isEmpty ? nil : 0
                loading = false
            }
        } catch {
            await MainActor.run {
                errorText = error.localizedDescription
                generated = []
                selectedIndex = nil
                loading = false
            }
        }
    }
}
