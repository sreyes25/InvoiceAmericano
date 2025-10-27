//
//  AuthView.swift
//  InvoiceAmericano
//
//  Created by Sergio Reyes on 9/19/25.
//

// AuthView.swift
import SwiftUI

struct AuthView: View {
    @StateObject private var vm = AuthViewModel()
    @State private var showPassword = false

    var body: some View {
        NavigationStack {
            ZStack {
                // App-style background
                LinearGradient(
                    colors: [Color(.systemGroupedBackground), Color(.secondarySystemBackground)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {

                        // MARK: - Brand / Title
                        VStack(spacing: 8) {
                            Image(systemName: "doc.text.fill")
                                .font(.system(size: 42, weight: .semibold))
                                .foregroundStyle(.blue)
                                .padding(.bottom, 2)
                            Text("InvoiceAmericano")
                                .font(.title2.bold())
                            Text("Sign in to continue")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 24)

                        // MARK: - Card
                        VStack(alignment: .leading, spacing: 14) {
                            // Email
                            LabeledField(
                                label: "Email",
                                systemImage: "envelope",
                                content: {
                                    TextField("you@example.com", text: $vm.email)
                                        .textContentType(.emailAddress)
                                        .textInputAutocapitalization(.never)
                                        .autocorrectionDisabled()
                                        .keyboardType(.emailAddress)
                                }
                            )

                            // Password (with show/hide)
                            LabeledField(
                                label: "Password",
                                systemImage: "lock",
                                content: {
                                    HStack {
                                        Group {
                                            if showPassword {
                                                TextField("Enter your password", text: $vm.password)
                                            } else {
                                                SecureField("Enter your password", text: $vm.password)
                                            }
                                        }
                                        .textContentType(.password)

                                        Button {
                                            withAnimation(.easeInOut(duration: 0.15)) { showPassword.toggle() }
                                        } label: {
                                            Image(systemName: showPassword ? "eye.slash" : "eye")
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            )

                            // Error banner
                            if let err = vm.error {
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundStyle(.red)
                                    Text(err)
                                        .font(.footnote)
                                        .foregroundStyle(.red)
                                    Spacer()
                                }
                                .padding(10)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(Color.red.opacity(0.08))
                                )
                            }

                            // Actions
                            VStack(spacing: 12) {
                                Button {
                                    Task { await vm.signIn() }
                                } label: {
                                    HStack {
                                        Spacer()
                                        Text("Log In")
                                            .font(.headline)
                                            .padding(.vertical, 12)
                                        Spacer()
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.blue)
                                .disabled(vm.email.isEmpty || vm.password.isEmpty)

                                Button {
                                    Task { await vm.signUp() }
                                } label: {
                                    HStack {
                                        Spacer()
                                        Text("Sign Up")
                                            .font(.headline)
                                            .padding(.vertical, 12)
                                        Spacer()
                                    }
                                }
                                .buttonStyle(.bordered)

                                // Or separator
                                HStack {
                                    Rectangle().fill(.tertiary).frame(height: 1)
                                    Text("or").font(.caption).foregroundStyle(.secondary)
                                    Rectangle().fill(.tertiary).frame(height: 1)
                                }

                                // Continue with Apple (visual only; wire later)
                                Button {
                                    // TODO: integrate Sign in with Apple
                                } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: "apple.logo")
                                        Text("Continue with Apple")
                                            .font(.headline)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                }
                                .buttonStyle(.bordered)
                                .tint(.primary)
                            }
                            .padding(.top, 4)
                        }
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color(.secondarySystemBackground))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(Color.black.opacity(0.05))
                        )
                        .shadow(color: .black.opacity(0.06), radius: 8, y: 4)

                        // Already authed tools
                        if vm.isAuthed {
                            VStack(spacing: 8) {
                                Divider().padding(.vertical, 4)
                                Button {
                                    Task { await vm.signOut() }
                                } label: {
                                    Label("Log Out", systemImage: "rectangle.portrait.and.arrow.right")
                                        .font(.subheadline)
                                }
                                .buttonStyle(.bordered)
                            }
                        }

                        Spacer(minLength: 12)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                }

                // Loading overlay
                if vm.isLoading {
                    ZStack {
                        Color.black.opacity(0.05).ignoresSafeArea()
                        ProgressView().scaleEffect(1.1)
                    }
                    .transition(.opacity)
                }
            }
            .navigationTitle("Sign In")
            .toolbarTitleDisplayMode(.inline)
            .task { await vm.refreshSession() }
        }
    }
}

private struct LabeledField<Content: View>: View {
    let label: String
    let systemImage: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .foregroundStyle(.secondary)
                content()
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(.tertiarySystemBackground))
            )
        }
    }
}
