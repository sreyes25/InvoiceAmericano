//
//  BrandingView.swift
//  InvoiceAmericano
//
//  Created by Sergio Reyes on 10/21/25.


import SwiftUI
import PhotosUI
import Supabase

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

    // MARK: - Load/Save

    private func load() async {
        do {
            // 1) Load branding settings (logo, color, optional tagline) from your app's settings table
            let s = try await BrandingService.loadBranding()
            await MainActor.run {
                businessName = s?.businessName ?? businessName
                tagline = s?.tagline ?? ""
                accentColor = Color(hex: s?.accentHex ?? "#1E90FF") ?? .blue
                if let urlString = s?.logoPublicURL, let url = URL(string: urlString) {
                    existingLogoURL = url
                } else {
                    existingLogoURL = nil
                }
            }

            // 2) Load the single source of truth for the display name (profiles.display_name)
            let client = SupabaseManager.shared.client
            let session = try await client.auth.session
            let uid = session.user.id

            struct ProfileRow: Decodable { let display_name: String? }

            let row: ProfileRow = try await client
                .from("profiles")
                .select("display_name")
                .eq("id", value: uid.uuidString)
                .single()
                .execute()
                .value

            if let dba = row.display_name, !dba.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                await MainActor.run { self.businessName = dba }
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
            print("[Branding] step=settings upsert OK")

            // 2) Update single source of truth: profiles.display_name
            let client = SupabaseManager.shared.client
            let session = try await client.auth.session
            let uid = session.user.id.uuidString

            struct UpdatePayload: Encodable { let display_name: String }
            _ = try await client
                .from("profiles")
                .update(UpdatePayload(display_name: businessName))
                .eq("id", value: uid)
                .execute()

            // 3) (Optional) Mirror to auth metadata (helps across devices)
            let attrs = UserAttributes(data: ["full_name": AnyJSON.string(businessName)])
            _ = try await client.auth.update(user: attrs)

            // 4) Notify parent & dismiss
            await MainActor.run {
                onBrandNameChanged?(businessName)
                dismiss()
            }
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
