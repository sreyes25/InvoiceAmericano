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

struct SafariView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController { .init(url: url) }
    func updateUIViewController(_ vc: SFSafariViewController, context: Context) {}
}

// MARK: - Coordinator

struct OnboardingFlow: View {
    @Environment(\.dismiss) private var dismiss

    @State private var step: Step = .welcome
    @State private var isSaving = false
    @State private var errorText: String?

    // Collected state across steps
    @State private var businessName: String = ""
    @State private var tagline: String = ""
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
            VStack {
                switch step {
                case .welcome:
                    WelcomeStep { step = .notifications }
                case .notifications:
                    NotificationsStep {
                        step = .branding
                    }
                case .branding:
                    BrandingStep(
                        businessName: $businessName,
                        tagline: $tagline,
                        onNext: { step = .invoiceDefaults }
                    )
                case .invoiceDefaults:
                    InvoiceDefaultsStep(
                        terms: $defaultTerms,
                        taxPct: $defaultTaxPct,
                        notes: $defaultNotes,
                        onNext: { step = .stripeConnect }
                    )
                case .stripeConnect:
                    StripeConnectStep(
                        stripeConnected: $stripeConnected,
                        onSkipOrConnected: { step = .done }
                    )
                case .done:
                    DoneStep {
                        Task { await persistAllAndClose() }
                    }
                }
            }
            .padding(.horizontal, 16)
            .navigationTitle(title(for: step))
            .navigationBarTitleDisplayMode(.large)
            .onOpenURL { url in
                // invoiceamericano://stripe/return or /refresh
                guard url.host == "stripe" else { return }
                // Minimal: mark connected and continue
                stripeConnected = true
                // Then advance if we are on the Stripe step
                if step == .stripeConnect { step = .done }
            }
        }
        .overlay(alignment: .bottom) {
            if let err = errorText {
                Text(err).foregroundStyle(.red).padding(.bottom, 12)
            }
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
            let session = try await client.auth.session
            let uid = session.user.id.uuidString

            // 1) Update profiles.display_name
            struct ProfileUpdate: Encodable { let display_name: String }
            _ = try await client
                .from("profiles")
                .update(ProfileUpdate(display_name: businessName))
                .eq("id", value: uid)
                .execute()

            // 2) Mirror to auth metadata (nice to have)
            let attrs = UserAttributes(data: ["full_name": AnyJSON.string(businessName)])
            _ = try await client.auth.update(user: attrs)

            // 3) Upsert invoice defaults
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
            NotificationCenter.default.post(name: .brandingDidChange, object: businessName)

            await MainActor.run {
                isSaving = false
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
}

// MARK: - Step 1: Welcome

private struct WelcomeStep: View {
    var onNext: () -> Void
    var body: some View {
        VStack(spacing: 24) {
            Text("Let’s set up your account")
                .font(.title2).bold()
                .frame(maxWidth: .infinity, alignment: .leading)

            Text("We’ll add your business name and defaults, connect payments, and enable notifications so you know when invoices are viewed and paid.")
                .foregroundStyle(.secondary)

            Spacer()

            Button(action: onNext) {
                Text("Get Started").bold().frame(maxWidth: .infinity).padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.top, 16)
    }
}

// MARK: - Step 2: Notifications

private struct NotificationsStep: View {
    var onGrantedOrSkip: () -> Void
    @State private var requesting = false
    @State private var error: String?

    init(onGranted: @escaping () -> Void) {
        self.onGrantedOrSkip = onGranted
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Stay in the loop").font(.title3).bold()
            Text("Enable notifications to get alerts when invoices are opened, paid, or overdue.")
                .foregroundStyle(.secondary)

            Spacer()

            if let error { Text(error).foregroundStyle(.red) }

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
        .padding(.top, 16)
    }

    private func request() async {
        await MainActor.run { requesting = true; error = nil }
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
            // You’ll still need to register for remote notifications in AppDelegate/Scene for APNs tokens.
            await MainActor.run {
                requesting = false
                if !granted {
                    // user declined; continue anyway
                }
                onGrantedOrSkip()
            }
        } catch {
            await MainActor.run { requesting = false; self.error = error.localizedDescription; onGrantedOrSkip() }
        }
    }
}

// MARK: - Step 3: Branding (DBA)

private struct BrandingStep: View {
    @Binding var businessName: String
    @Binding var tagline: String
    var onNext: () -> Void

    var body: some View {
        VStack(spacing: 14) {
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

            Spacer()

            Button(action: onNext) {
                Text("Continue").bold().frame(maxWidth: .infinity).padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .disabled(businessName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.top, 8)
    }

    private func labeled(_ title: String, @ViewBuilder field: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline).foregroundStyle(.secondary)
            field()
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
        VStack(spacing: 14) {
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

            Spacer()

            Button(action: onNext) {
                Text("Continue").bold().frame(maxWidth: .infinity).padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.top, 8)
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

// MARK: - Step 6: Done

private struct DoneStep: View {
    var onFinish: () -> Void
    var body: some View {
        VStack(spacing: 16) {
            Text("You're all set 🎉").font(.title3).bold()
            Text("You can change these settings anytime from Account.")
                .foregroundStyle(.secondary)
            Spacer()
            Button(action: onFinish) {
                Text("Finish").bold().frame(maxWidth: .infinity).padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.top, 8)
    }
}
