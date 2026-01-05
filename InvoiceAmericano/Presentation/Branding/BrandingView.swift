//
//  BrandingView.swift
//  InvoiceAmericano
//
//  Created by Sergio Reyes on 10/21/25.
//

import SwiftUI
import PhotosUI
import Supabase
import Foundation

struct BrandingView: View {
    /// Notify parent (e.g., AccountView) when the DBA/business name changes
    var onBrandNameChanged: ((String) -> Void)? = nil

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
        ScrollView {
            VStack(spacing: 20) {
                businessInfoCard
                logoCard
                accentColorCard
                if let errorText { Text(errorText).foregroundStyle(.red).font(.footnote) }
                saveButton
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Branding")
        .task { await load() }
    }

    private var businessInfoCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Business Info", systemImage: "building.2.crop.circle")
                .font(.headline)
            TextField("Business name", text: $businessName)
                .textInputAutocapitalization(.words)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
            TextField("Tagline (optional)", text: $tagline)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.systemBackground)))
        .shadow(color: .black.opacity(0.05), radius: 6, y: 3)
    }

    private var logoCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Logo", systemImage: "photo")
                .font(.headline)
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.secondarySystemBackground))
                        .frame(width: 80, height: 80)
                    if let img = pickedUIImage {
                        Image(uiImage: img).resizable().scaledToFill()
                            .frame(width: 80, height: 80)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    } else if let url = existingLogoURL {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .empty: ProgressView()
                            case .success(let image): image.resizable().scaledToFill()
                            case .failure: Image(systemName: "photo")
                            @unknown default: EmptyView()
                            }
                        }
                        .frame(width: 80, height: 80)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    } else {
                        Image(systemName: "photo.on.rectangle")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    PhotosPicker(selection: $pickerItem, matching: .images, photoLibrary: .shared()) {
                        Label("Choose logo", systemImage: "plus.circle")
                    }
                    .onChange(of: pickerItem) { _, newItem in
                        Task { await loadPickedImage(from: newItem) }
                    }

                    if pickedUIImage != nil {
                        Button(role: .destructive) {
                            pickedUIImage = nil
                            pickedImageData = nil
                        } label: {
                            Label("Remove", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.systemBackground)))
        .shadow(color: .black.opacity(0.05), radius: 6, y: 3)
    }

    private var accentColorCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Accent Color", systemImage: "paintpalette.fill")
                .font(.headline)
            ColorPicker("Brand color", selection: $accentColor, supportsOpacity: false)
                .padding(.horizontal)
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.systemBackground)))
        .shadow(color: .black.opacity(0.05), radius: 6, y: 3)
    }

    private var saveButton: some View {
        Button(action: { Task { await save() } }) {
            if isSaving {
                ProgressView()
            } else {
                Text("Save Branding")
                    .bold()
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(LinearGradient(colors: [.blue, .indigo], startPoint: .leading, endPoint: .trailing))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
        .padding(.horizontal)
        .disabled(isSaving || businessName.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    // MARK: - Load/Save (direct Supabase, no BrandingService dependency)

    private func load() async {
        do {
            let client = SupabaseManager.shared.client
            let uid = try SupabaseManager.shared.requireCurrentUserIDString()

            // 1) Try branding_settings (may not exist yet)
            struct BrandingRow: Decodable {
                let business_name: String?
                let tagline: String?
                let accent_hex: String?
                let logo_public_url: String?
            }

            var branding: BrandingRow? = nil
            do {
                branding = try await client
                    .from("branding_settings")
                    .select("business_name,tagline,accent_hex,logo_public_url")
                    .eq("user_id", value: uid)
                    .limit(1)
                    .single()
                    .execute()
                    .value
            } catch {
                // No row yet is fine; fall back to profiles
                branding = nil
            }

            // 2) Load the single source of truth for the display name (profiles.display_name)
            struct ProfileRow: Decodable { let display_name: String? }
            let profile: ProfileRow = try await client
                .from("profiles")
                .select("display_name")
                .eq("id", value: uid)
                .single()
                .execute()
                .value

            await MainActor.run {
                if let dba = profile.display_name, !dba.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    self.businessName = dba
                } else if let name = branding?.business_name {
                    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        self.businessName = trimmed
                    }
                }
                self.tagline = branding?.tagline ?? ""
                if let hex = branding?.accent_hex, let c = Color(hex: hex) { self.accentColor = c }
                if let urlStr = branding?.logo_public_url, let u = URL(string: urlStr) { self.existingLogoURL = u }
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
            let client = SupabaseManager.shared.client
            let uid = try SupabaseManager.shared.requireCurrentUserIDString()

            var logoPublicURL: String? = nil

            // If user picked a new image, upload it
            if let ui = pickedUIImage {
                step = "uploadLogo"
                let resized = ui.ia_resized(maxDimension: 512)
                guard let data = resized.pngData() else { throw SaveError.couldNotEncodePNG }
                logoPublicURL = try await SupabaseStorageService.uploadBrandingLogo(data: data)
            } else if let url = existingLogoURL {
                logoPublicURL = url.absoluteString
            }

            let accentHex = accentColor.ia_hexString()

            // 1) Upsert into branding_settings
            step = "upsertSettings"
            struct UpsertPayload: Encodable {
                let user_id: String
                let business_name: String
                let tagline: String?
                let accent_hex: String?
                let logo_public_url: String?
            }
            let payload = UpsertPayload(
                user_id: uid,
                business_name: businessName,
                tagline: (tagline.trimmingCharacters(in: .whitespaces).isEmpty ? nil : tagline),
                accent_hex: accentHex,
                logo_public_url: ((logoPublicURL?.isEmpty ?? true) ? nil : logoPublicURL)
            )
            _ = try await client
                .from("branding_settings")
                .upsert(payload, onConflict: "user_id")
                .execute()

            // 2) Update single source of truth: profiles.display_name
            struct UpdatePayload: Encodable { let display_name: String }
            _ = try await client
                .from("profiles")
                .update(UpdatePayload(display_name: businessName))
                .eq("id", value: uid)
                .execute()

            // 3) (Optional) Mirror to auth metadata (helps across devices)
            let attrs = UserAttributes(data: ["full_name": AnyJSON.string(businessName)])
            _ = try await client.auth.update(user: attrs)

            // 4) Announce & dismiss
            await MainActor.run {
                NotificationCenter.default.post(name: .brandingDidChange, object: nil)
                onBrandNameChanged?(businessName)
                dismiss()
            }
        } catch {
            let message = "Save failed at \(step). \(error.localizedDescription)"
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


// MARK: - Notification.Name extension

extension Notification.Name {
    static let brandingDidChange = Notification.Name("BrandingDidChange")
}
