//
//  AuthView.swift
//  InvoiceAmericano
//
//  Created by Sergio Reyes on 9/17/25.
//

import SwiftUI

struct AuthView: View {
    @StateObject var vm = AuthViewModel()
    var onAuth: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            TextField("Email", text: $vm.email)
                .textInputAutocapitalization(.never).keyboardType(.emailAddress)
                .textFieldStyle(.roundedBorder)
            SecureField("Password", text: $vm.password)
                .textFieldStyle(.roundedBorder)
            Button("Sign In") { Task { await vm.signIn(); if vm.isAuthenticated { onAuth() } } }
                .buttonStyle(.borderedProminent)
            Button("Create Account") { Task { await vm.signUp(); if vm.isAuthenticated { onAuth() } } }
                .buttonStyle(.bordered)

            if let e = vm.error { Text(e).foregroundColor(.red).font(.footnote) }
        }
        .padding()
    }
}
