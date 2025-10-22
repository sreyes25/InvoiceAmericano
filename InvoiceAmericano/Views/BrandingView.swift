//
//  BrandingView.swift
//  InvoiceAmericano
//
//  Created by Sergio Reyes on 10/21/25.


import SwiftUI
import PhotosUI

struct BrandingView: View {
    @State private var businessName: String = ""
    @State private var tagline: String = ""
    @State private var accentColor: Color = .blue
    @State private var existingLogoURL: URL? = nil

    // Photo picker state
    @State private var pickerItem: PhotosPickerItem?
    @State private var pickedImageData: Data?
    @State private var pickedUIImage: UIImage?

    // UX
    @State private var isSaving = false
    @State private var errorText: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section(header: Text("Business")) {
                TextField("Business name", text: $businessName)
                    .textInputAutocapitalization(.words)
                TextField("Tagline (optional)", text: $tagline)
            }

            Section(header: Text("Logo")) {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(.secondarySystemBackground))
                            .frame(width: 72, height: 72)

                        if let img = pickedUIImage {
                            Image(uiImage: img).resizable().scaledToFill()
                                .frame(width: 72, height: 72).clipShape(RoundedRectangle(cornerRadius: 12))
                        } else if let url = existingLogoURL {
                            // Lightweight async image (iOS 15+)
                            AsyncImage(url: url) { phase in
                                switch phase {
                                case .empty:
                                    ProgressView()
                                case .success(let image):
                                    image.resizable().scaledToFill()
                                case .failure:
                                    Image(systemName: "photo").font(.title2)
                                @unknown default:
                                    EmptyView()
                                }
                            }
                            .frame(width: 72, height: 72)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        } else {
                            Image(systemName: "photo").font(.title2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    PhotosPicker(selection: $pickerItem, matching: .images, photoLibrary: .shared()) {
                        Label("Choose logo", systemImage: "photo")
                    }
                    .onChange(of: pickerItem) { _, newItem in
                        Task { await loadPickedImage(from: newItem) }
                    }

                    if pickedUIImage != nil {
                        Button(role: .destructive) {
                            pickedUIImage = nil
                            pickedImageData = nil
                        } label: { Label("Remove", systemImage: "trash") }
                    }
                }
            }

            Section(header: Text("Accent Color")) {
                ColorPicker("Brand color", selection: $accentColor, supportsOpacity: false)
            }

            if let errorText {
                Text(errorText)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .navigationTitle("Branding")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await save() }
                } label: {
                    if isSaving { ProgressView() } else { Text("Save").bold() }
                }
                .disabled(isSaving || businessName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .task { await load() }
    }

    // MARK: - Load/Save

    private func load() async {
        do {
            let s = try await BrandingService.loadBranding()
            await MainActor.run {
                businessName = s?.businessName ?? ""
                tagline = s?.tagline ?? ""
                accentColor = Color(hex: s?.accentHex ?? "#1E90FF") ?? .blue
                if let urlString = s?.logoPublicURL, let url = URL(string: urlString) {
                    existingLogoURL = url
                } else {
                    existingLogoURL = nil
                }
            }
        } catch {
            await MainActor.run { errorText = "Failed to load branding. \(error.localizedDescription)" }
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        var step = "start"

        do {
            var logoPublicURL: String? = nil

            // If user picked a new image, upload it
            if let ui = pickedUIImage {
                step = "uploadLogo"
                print("[Branding] step=\(step) – preparing image upload")
                let resized = ui.ia_resized(maxDimension: 512)
                guard let data = resized.pngData() else { throw SaveError.couldNotEncodePNG }
                logoPublicURL = try await SupabaseStorageService.uploadBrandingLogo(data: data)
                print("[Branding] step=\(step) – storage OK, url=", logoPublicURL ?? "nil")
            } else if let url = existingLogoURL {
                logoPublicURL = url.absoluteString
                print("[Branding] step=reuseLogo – reusing existing url=", logoPublicURL ?? "nil")
            }

            let accentHex = accentColor.ia_hexString()

            step = "upsertSettings"
            print("[Branding] step=\(step) – name=\(businessName), hasLogo=\(logoPublicURL != nil), accent=\(accentHex)")
            try await BrandingService.upsertBranding(
                businessName: businessName,
                tagline: tagline,
                accentHex: accentHex,
                logoPublicURL: logoPublicURL
            )
            print("[Branding] step=done – settings upsert OK")
            await MainActor.run { dismiss() }
        } catch {
            let message = "Save failed at \(step). \(error.localizedDescription)"
            print("[Branding] ERROR –", message)
            await MainActor.run { errorText = message }
        }
    }

    // MARK: - Image picker

    private func loadPickedImage(from item: PhotosPickerItem?) async {
        guard let item else { return }
        do {
            if let data = try await item.loadTransferable(type: Data.self),
               let ui = UIImage(data: data) {
                await MainActor.run {
                    pickedImageData = data
                    pickedUIImage = ui
                }
            }
        } catch {
            await MainActor.run { errorText = "Could not read selected image." }
        }
    }

    enum SaveError: Error { case couldNotEncodePNG }
}

// MARK: - Helpers

private extension UIImage {
    /// Keep aspect, fit within square of `maxDimension`
    func ia_resized(maxDimension: CGFloat) -> UIImage {
        let maxSide = max(size.width, size.height)
        guard maxSide > maxDimension else { return self }

        let scale = maxDimension / maxSide
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)

        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            self.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}

private extension Color {
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let rgb = Int(s, radix: 16) else { return nil }
        let r = Double((rgb >> 16) & 0xFF) / 255.0
        let g = Double((rgb >> 8) & 0xFF) / 255.0
        let b = Double(rgb & 0xFF) / 255.0
        self = Color(red: r, green: g, blue: b)
    }

    func ia_hexString() -> String {
        #if canImport(UIKit)
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        let R = Int(round(r * 255)), G = Int(round(g * 255)), B = Int(round(b * 255))
        return String(format: "#%02X%02X%02X", R, G, B)
        #else
        return "#1E90FF"
        #endif
    }
}
