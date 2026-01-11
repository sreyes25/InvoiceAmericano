//
//  OnboardingFlow.swift
//  InvoiceAmericano
//
//  Created by Sergio Reyes on 10/28/25.
//

import SwiftUI
import UserNotifications
import Supabase
import SafariServices
import PhotosUI
import UIKit

struct SafariView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController { .init(url: url) }
    func updateUIViewController(_ vc: SFSafariViewController, context: Context) {}
}

// MARK: - Coordinator

struct OnboardingFlow: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false

    @State private var step: Step = .welcome
    @State private var isSaving = false
    @State private var errorText: String?

    // Collected state across steps
    @State private var businessName: String = ""
    @State private var tagline: String = ""

    // NEW: Branding personalization
    @State private var accentColor: Color = .accentColor
    @State private var logoPickerItem: PhotosPickerItem?
    @State private var logoUIImage: UIImage?

    @State private var defaultTerms: String = "Net 30"
    @State private var defaultTaxPct: String = "0"
    @State private var defaultNotes: String = ""

    @State private var stripeConnected: Bool = false

    enum Step: Hashable {
        case welcome
        case notifications
        case branding
        case invoiceDefaults
        case stripeConnect
        case done
    }

    var body: some View {
        NavigationStack {
            ZStack {
                OnboardingBackground(accent: accentColor)
                    .ignoresSafeArea()

                VStack(spacing: 14) {
                    OnboardingProgress(currentStep: stepIndex, totalSteps: totalStepCount, accent: accentColor)

                    OnboardingCard {
                        VStack(alignment: .leading, spacing: 14) {
                            Text(title(for: step))
                                .font(.title2.bold())

                            switch step {
                            case .welcome:
                                WelcomeStep { withAnimation(.snappy(duration: 0.25)) { step = .notifications } }

                            case .notifications:
                                NotificationsStep {
                                    withAnimation(.snappy(duration: 0.25)) { step = .branding }
                                }

                            case .branding:
                                BrandingStep(
                                    businessName: $businessName,
                                    tagline: $tagline,
                                    accentColor: $accentColor,
                                    logoPickerItem: $logoPickerItem,
                                    logoUIImage: $logoUIImage,
                                    onNext: { withAnimation(.snappy(duration: 0.25)) { step = .invoiceDefaults } }
                                )

                            case .invoiceDefaults:
                                InvoiceDefaultsStep(
                                    terms: $defaultTerms,
                                    taxPct: $defaultTaxPct,
                                    notes: $defaultNotes,
                                    onNext: { withAnimation(.snappy(duration: 0.25)) { step = .stripeConnect } }
                                )

                            case .stripeConnect:
                                StripeConnectStep(
                                    stripeConnected: $stripeConnected,
                                    onSkipOrConnected: { withAnimation(.snappy(duration: 0.25)) { step = .done } }
                                )

                            case .done:
                                DoneStep {
                                    Task { await persistAllAndClose() }
                                }
                            }
                        }
                    }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)

                if isSaving {
                    Color.black.opacity(0.12).ignoresSafeArea()
                    ProgressView("Saving…")
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .onOpenURL { url in
                // invoiceamericano://stripe/return or /refresh
                guard url.host == "stripe" else { return }
                stripeConnected = true
                if step == .stripeConnect { step = .done }
            }
        }
        .overlay(alignment: .bottom) {
            if let err = errorText {
                Text(err)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .background(Color.red.opacity(0.22), in: Capsule())
                    .padding(.bottom, 12)
            }
        }
    }

    private var totalStepCount: Int { 6 }

    private var stepIndex: Int {
        switch step {
        case .welcome: return 1
        case .notifications: return 2
        case .branding: return 3
        case .invoiceDefaults: return 4
        case .stripeConnect: return 5
        case .done: return 6
        }
    }

    private func title(for step: Step) -> String {
        switch step {
        case .welcome: return "Welcome"
        case .notifications: return "Notifications"
        case .branding: return "Branding"
        case .invoiceDefaults: return "Invoice Defaults"
        case .stripeConnect: return "Payments"
        case .done: return "All Set"
        }
    }

    // MARK: - Persist everything (DBA + defaults)
    private func persistAllAndClose() async {
        guard !isSaving else { return }
        await MainActor.run { isSaving = true; errorText = nil }
        let client = SupabaseManager.shared.client

        do {
            let uid = try SupabaseManager.shared.requireCurrentUserIDString()

            let cleanName = businessName.trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanTag  = tagline.trimmingCharacters(in: .whitespacesAndNewlines)

            // 1) Update profiles.display_name
            struct ProfileUpdate: Encodable { let display_name: String }
            _ = try await client
                .from("profiles")
                .update(ProfileUpdate(display_name: cleanName))
                .eq("id", value: uid)
                .execute()

            // Upload logo (optional)
            var logoPublicURL: String? = nil
            if let ui = logoUIImage {
                let resized = ui.ia_resized(maxDimension: 512)
                if let data = resized.pngData() {
                    logoPublicURL = try await SupabaseStorageService.uploadBrandingLogo(data: data)
                }
            }

            let accentHex = accentColor.ia_hexString()

            // 2) Upsert branding_settings (business name + tagline) so PDFs have it immediately
            struct BrandingPayload: Encodable {
                let user_id: String
                let business_name: String
                let tagline: String?
                let accent_hex: String?
                let logo_public_url: String?
            }

            _ = try await client
                .from("branding_settings")
                .upsert(
                    BrandingPayload(
                        user_id: uid,
                        business_name: cleanName,
                        tagline: cleanTag.isEmpty ? nil : cleanTag,
                        accent_hex: accentHex,
                        logo_public_url: logoPublicURL
                    ),
                    onConflict: "user_id"
                )
                .execute()

            // 3) Mirror to auth metadata (nice to have)
            let attrs = UserAttributes(data: ["full_name": AnyJSON.string(cleanName)])
            _ = try await client.auth.update(user: attrs)

            // 4) Upsert invoice defaults
            // Create this table if you don't have it:
            //   create table invoice_defaults (user_id uuid primary key references auth.users(id), terms text, tax_pct numeric, notes text);
            struct DefaultsPayload: Encodable {
                let user_id: String
                let terms: String
                let tax_pct: Double
                let notes: String?
            }
            let tax = Double(defaultTaxPct) ?? 0
            _ = try await client
                .from("invoice_defaults")
                .upsert(DefaultsPayload(user_id: uid, terms: defaultTerms, tax_pct: tax, notes: defaultNotes.isEmpty ? nil : defaultNotes))
                .execute()

            // Invalidate cached brand and notify listeners so first PDF uses the fresh name
            BrandingService.invalidateCache()
            NotificationCenter.default.post(name: .brandingDidChange, object: nil)

            await MainActor.run {
                // Mark onboarding as complete locally so we don't show it again offline
                hasCompletedOnboarding = true
                isSaving = false
                AnalyticsService.track(.onboardingCompleted, metadata: ["status": "success"])
                NotificationCenter.default.post(name: .onboardingDidFinish, object: nil)
                dismiss()  // close onboarding
            }
        } catch {
            await MainActor.run {
                isSaving = false
                errorText = error.localizedDescription
            }
        }
    }

    // MARK: - Logout from onboarding
    private func handleLogout() async {
        let client = SupabaseManager.shared.client
        do {
            try await client.auth.signOut()
        } catch {
            await MainActor.run {
                errorText = error.localizedDescription
            }
        }

        await MainActor.run {
            // Make sure onboarding is shown again next time after login
            hasCompletedOnboarding = false
            dismiss()
        }
    }
}

private struct WelcomeStep: View {
    var onNext: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                OnboardingIcon(systemImage: "sparkles")
                VStack(alignment: .leading, spacing: 2) {
                    Text("Let’s set up your account")
                        .font(.headline)
                    Text("A few quick steps.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Text("Add your business name and logo, set defaults, and connect payments. You can change everything later.")
                .foregroundStyle(.secondary)

            Spacer(minLength: 8)

            Button(action: onNext) {
                Text("Get Started")
                    .bold()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct NotificationsStep: View {
    var onGrantedOrSkip: () -> Void
    @State private var requesting = false
    @State private var error: String?

    init(onGranted: @escaping () -> Void) {
        self.onGrantedOrSkip = onGranted
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                OnboardingIcon(systemImage: "bell.badge")
                VStack(alignment: .leading, spacing: 2) {
                    Text("Stay in the loop")
                        .font(.headline)
                    Text("Invoice updates in real time.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Text("Enable notifications to get alerts when invoices are opened, paid, or overdue.")
                .foregroundStyle(.secondary)

            if let error { Text(error).foregroundStyle(.red) }

            Spacer(minLength: 8)

            HStack {
                Button("Not now") { onGrantedOrSkip() }
                Spacer()
                Button(requesting ? "Requesting…" : "Enable") {
                    Task { await request() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(requesting)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func request() async {
        await MainActor.run { requesting = true; error = nil }

        let granted = await NotificationService.requestAuthorization()
        if granted {
            await NotificationService.syncDeviceTokenIfNeeded(force: true)
        }

        await MainActor.run {
            requesting = false
            onGrantedOrSkip()
        }
    }
}

private struct BrandingStep: View {
    @Binding var businessName: String
    @Binding var tagline: String
    @Binding var accentColor: Color

    @Binding var logoPickerItem: PhotosPickerItem?
    @Binding var logoUIImage: UIImage?

    var onNext: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                LogoPreview(image: logoUIImage)

                VStack(alignment: .leading, spacing: 10) {
                    PhotosPicker(selection: $logoPickerItem, matching: .images, photoLibrary: .shared()) {
                        Label(logoUIImage == nil ? "Choose logo" : "Change logo", systemImage: "photo.badge.plus")
                            .font(.subheadline.weight(.semibold))
                    }
                    .onChange(of: logoPickerItem) { _, newItem in
                        Task { await loadPickedImage(from: newItem) }
                    }

                    if logoUIImage != nil {
                        Button(role: .destructive) {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                logoUIImage = nil
                                logoPickerItem = nil
                            }
                        } label: {
                            Label("Remove", systemImage: "trash")
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                }

                Spacer()
            }

            labeled("Business name") {
                TextField("Your business name", text: $businessName)
                    .textInputAutocapitalization(.words)
                    .disableAutocorrection(true)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
            }

            labeled("Tagline (optional)") {
                TextField("e.g. Handyman Services", text: $tagline)
                    .textInputAutocapitalization(.words)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
            }

            HStack {
                Label("Brand color", systemImage: "paintpalette.fill")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                ColorPicker("", selection: $accentColor, supportsOpacity: false)
                    .labelsHidden()
            }
            .padding(.top, 6)

            Spacer(minLength: 8)

            Button(action: onNext) {
                Text("Continue")
                    .bold()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(accentColor)
            .disabled(businessName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func labeled(_ title: String, @ViewBuilder field: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            field()
        }
    }

    private func loadPickedImage(from item: PhotosPickerItem?) async {
        guard let item else { return }
        do {
            if let data = try await item.loadTransferable(type: Data.self),
               let ui = UIImage(data: data) {
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        logoUIImage = ui
                    }
                }
            }
        } catch {
            // Keep onboarding simple: fail silently
        }
    }
}

// MARK: - Step 4: Invoice Defaults

private struct InvoiceDefaultsStep: View {
    @Binding var terms: String
    @Binding var taxPct: String
    @Binding var notes: String
    var onNext: () -> Void

    let termOptions = ["Due on receipt", "Net 7", "Net 15", "Net 30"]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            labeled("Payment terms") {
                Picker("", selection: $terms) {
                    ForEach(termOptions, id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            labeled("Tax (%)") {
                TextField("0", text: $taxPct)
                    .keyboardType(.decimalPad)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
            }
            labeled("Default note (optional)") {
                TextField("Thank you for your business!", text: $notes)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
            }

            Spacer(minLength: 8)

            Button(action: onNext) {
                Text("Continue")
                    .bold()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func labeled(_ title: String, @ViewBuilder field: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline).foregroundStyle(.secondary)
            field()
        }
    }
}

// MARK: - Step 5: Stripe Connect

private struct StripeConnectStep: View {
    @Binding var stripeConnected: Bool
    var onSkipOrConnected: () -> Void

    @State private var isLoading = false
    @State private var error: String?
    @State private var safariURL: URL?
    @State private var showSafari = false

    // 👉 Put your real invoke URL here
    private let functionURL = URL(string: "https://pbhlynmgmgrzhynnrmna.supabase.co/functions/v1/create_connect_link")!

    var body: some View {
        VStack(spacing: 16) {
            Text("Get paid with Stripe").font(.title3).bold()
            Text("Connect your Stripe account to accept payments from invoices.")
                .foregroundStyle(.secondary)

            Spacer()

            if let error { Text(error).foregroundStyle(.red) }

            Button {
                Task { await startOnboarding() }
            } label: {
                Text(isLoading ? "Loading…" : "Connect Stripe")
                    .bold().frame(maxWidth: .infinity).padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isLoading)

            Button("Do this later") { onSkipOrConnected() }
                .padding(.top, 8)
        }
        .padding(.top, 8)
        .sheet(isPresented: $showSafari) {
            if let url = safariURL { SafariView(url: url) }
        }
    }

    private func startOnboarding() async {
        await MainActor.run { isLoading = true; error = nil }
        defer { Task { await MainActor.run { isLoading = false } } }

        do {
            // Grab a fresh user token
            let client = SupabaseManager.shared.client
            let session = try await client.auth.session
            let token = session.accessToken

            var req = URLRequest(url: functionURL)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            let (data, resp) = try await URLSession.shared.data(for: req)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
                let body = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw NSError(domain: "StripeConnect", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: body])
            }

            struct ConnectResp: Decodable { let url: String }
            let decoded = try JSONDecoder().decode(ConnectResp.self, from: data)
            guard let url = URL(string: decoded.url) else { throw URLError(.badURL) }

            await MainActor.run { safariURL = url; showSafari = true }
        } catch {
            await MainActor.run { self.error = error.localizedDescription }
        }
    }
}

private struct DoneStep: View {
    var onFinish: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                OnboardingIcon(systemImage: "checkmark.seal.fill")
                VStack(alignment: .leading, spacing: 2) {
                    Text("You’re all set")
                        .font(.headline)
                    Text("Your branding is ready.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Text("You can change these settings anytime from Account.")
                .foregroundStyle(.secondary)

            Spacer(minLength: 8)

            Button(action: onFinish) {
                Text("Finish")
                    .bold()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Shared Onboarding UI

private struct OnboardingBackground: View {
    let accent: Color

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(.systemGroupedBackground), Color(.secondarySystemGroupedBackground)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(accent.opacity(0.18))
                .frame(width: 420, height: 420)
                .blur(radius: 30)
                .offset(x: -140, y: -260)

            Circle()
                .fill(accent.opacity(0.12))
                .frame(width: 320, height: 320)
                .blur(radius: 30)
                .offset(x: 170, y: 260)
        }
    }
}

private struct OnboardingCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.06))
            )
            .shadow(color: .black.opacity(0.06), radius: 10, y: 6)
    }
}

private struct OnboardingProgress: View {
    let currentStep: Int
    let totalSteps: Int
    let accent: Color

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Step \(currentStep) of \(totalSteps)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }

            GeometryReader { geo in
                let frac = totalSteps <= 1 ? 1 : CGFloat(currentStep - 1) / CGFloat(totalSteps - 1)
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08))
                    Capsule().fill(accent.opacity(0.65))
                        .frame(width: max(16, geo.size.width * frac))
                }
            }
            .frame(height: 10)
        }
    }
}

private struct OnboardingIcon: View {
    let systemImage: String

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.35))
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.primary)
        }
        .frame(width: 44, height: 44)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.35), lineWidth: 0.5)
        )
    }
}

private struct LogoPreview: View {
    let image: UIImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.35))
                .frame(width: 76, height: 76)

            if let ui = image {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 76, height: 76)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.35), lineWidth: 0.5)
        )
    }
}

// MARK: - Helpers

private extension UIImage {
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
    func ia_hexString() -> String {
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        let R = Int(round(r * 255))
        let G = Int(round(g * 255))
        let B = Int(round(b * 255))
        return String(format: "#%02X%02X%02X", R, G, B)
    }
}
