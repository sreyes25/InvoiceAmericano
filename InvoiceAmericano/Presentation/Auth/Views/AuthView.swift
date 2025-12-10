//
//  AuthView.swift
//  InvoiceAmericano
//
//  Created by Sergio Reyes on 9/19/25.
//

import SwiftUI
import SceneKit

struct AuthView: View {
    @StateObject private var vm = AuthViewModel()
    @State private var showPassword = false

    var body: some View {
        NavigationStack {
            ZStack {
                ZStack {
                    // Base neutral background
                    LinearGradient(
                        colors: [Color(.systemGroupedBackground), Color(.secondarySystemBackground)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                    .ignoresSafeArea()

                    // Brand red accent wash at the top
                    VStack(spacing: 0) {
                        LinearGradient(
                            colors: [
                                Color.red.opacity(0.18),
                                Color.red.opacity(0.08),
                                .clear
                            ],
                            startPoint: .top, endPoint: .bottom
                        )
                        .frame(height: 260)
                        .blur(radius: 36)
                        Spacer(minLength: 0)
                    }
                    .allowsHitTesting(false)
                }

                VStack(spacing: 18) {
                    // Brand
                    BrandHeader(mode: vm.mode)
                        .padding(.top, 28)

                    // Card container
                    ZStack {
                        switch vm.mode {
                        case .chooser:
                            chooserCard
                                .transition(.scale.combined(with: .opacity))
                        case .signUp:
                            signUpCard
                                .transition(.move(edge: .trailing).combined(with: .opacity))
                        case .signIn:
                            signInCard
                                .transition(.move(edge: .trailing).combined(with: .opacity))
                        }
                    }
                    .animation(.spring(response: 0.42, dampingFraction: 0.88), value: vm.mode)

                    Spacer(minLength: 12)
                }
                .padding(.horizontal, 20)
            }
            .navigationTitle(title)
            .toolbarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarBackgroundVisibility(.visible, for: .navigationBar)

            // Loading veil
            .overlay {
                if vm.isLoading {
                    LoadingOverlay().transition(.opacity)
                }
            }

            // Banner (success/info)
            .overlay(alignment: .top) {
                if let text = vm.banner, !text.isEmpty {
                    BannerToast(text: text)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .padding(.top, 8)
                        .zIndex(2)
                }
            }

            // Error alert
            .alert("Error", isPresented: Binding(
                get: { vm.error != nil },
                set: { newValue in if !newValue { vm.error = nil } }
            )) {
                Button("OK") { vm.error = nil }
            } message: {
                Text(vm.error ?? "Something went wrong.")
            }
            .task { await vm.refreshSession() }
            .onReceive(NotificationCenter.default.publisher(for: .authDidChange)) { _ in
                Task { await vm.refreshSession() }
            }
        }
    }

    // MARK: - Cards

    private var chooserCard: some View {
        VStack(spacing: 14) {
            // Apple FIRST + wired to VM
            Button {
                Task { await vm.signInWithApple() }
            } label: {
                HStack {
                    Image(systemName: "apple.logo")
                    Text("Continue with Apple")
                        .font(.headline)
                    Spacer()
                }
                .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(.black)

            Button {
                vm.goSignUp()
            } label: {
                HStack {
                    Image(systemName: "person.badge.plus")
                    Text("Create Account")
                        .font(.headline)
                    Spacer()
                }
                .padding(.vertical, 12)
            }
            .buttonStyle(.bordered)
            .tint(.red)

            Button {
                vm.goSignIn()
            } label: {
                HStack {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                    Text("Sign In")
                        .font(.headline)
                    Spacer()
                }
                .padding(.vertical, 12)
            }
            .buttonStyle(.bordered)
            .tint(.red)
        }
        .padding(16)
        .padding(.top, 6)
    }

    private var signUpCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            topBarBack("Create account")

            LabeledField(label: "Email", systemImage: "envelope") {
                TextField("you@example.com", text: $vm.email)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.emailAddress)
                    .onChange(of: vm.email) { _, _ in vm.validateFields(forSignUp: true) } // iOS 17+ API
            }
            if let hint = vm.emailHint {
                hintText(hint)
            }

            LabeledField(label: "Password", systemImage: "lock") {
                HStack {
                    Group {
                        if showPassword { TextField("Create a password", text: $vm.password) }
                        else { SecureField("Create a password", text: $vm.password) }
                    }
                    .textContentType(.newPassword)
                    .onChange(of: vm.password) { _, _ in vm.validateFields(forSignUp: true) } // iOS 17+ API

                    Button { withAnimation(.easeInOut(duration: 0.15)) { showPassword.toggle() } } label: {
                        Image(systemName: showPassword ? "eye.slash" : "eye")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if let ph = vm.passwordHint {
                hintText(ph)
            } else {
                // Subtle strength readout only while typing
                if !vm.password.isEmpty {
                    Text("Strength: \(vm.strength.rawValue.capitalized)")
                        .font(.caption)
                        .foregroundStyle(vm.strength == .weak ? .red : (vm.strength == .ok ? .orange : .green))
                }
            }

            Button {
                Task { await vm.signUp() }
            } label: {
                HStack { Spacer(); Text("Create Account").font(.headline); Spacer() }
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .shadow(color: .red.opacity(0.22), radius: 10, y: 4)
            .disabled(!vm.canSubmitSignUp)
        }
        .padding(16)
        .padding(.top, 16)
    }

    private var signInCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            topBarBack("Sign in")

            LabeledField(label: "Email", systemImage: "envelope") {
                TextField("you@example.com", text: $vm.email)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.emailAddress)
                    .onChange(of: vm.email) { _, _ in vm.validateFields(forSignUp: false) } // iOS 17+ API
            }
            if let hint = vm.emailHint {
                hintText(hint)
            }

            LabeledField(label: "Password", systemImage: "lock") {
                SecureField("Enter your password", text: $vm.password)
                    .textContentType(.password)
                    .onChange(of: vm.password) { _, _ in vm.validateFields(forSignUp: false) } // iOS 17+ API
            }
            if let ph = vm.passwordHint {
                hintText(ph)
            }

            Button {
                Task { await vm.signIn() }
            } label: {
                HStack { Spacer(); Text("Sign In").font(.headline); Spacer() }
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .shadow(color: .red.opacity(0.22), radius: 10, y: 4)
            .disabled(!vm.canSubmitSignIn)
        }
        .padding(16)
        .padding(.top, 16)
    }

    // MARK: - Small pieces

    private var title: String {
        switch vm.mode {
        case .chooser: return "Welcome"
        case .signIn:  return "Sign In"
        case .signUp:  return "Create Account"
        }
    }

    private func topBarBack(_ label: String) -> some View {
        HStack(spacing: 12) {
            // Left: high-contrast, thumb-friendly back button
            Button {
                withAnimation(.snappy(duration: 0.25)) { vm.goChooser() }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 36, height: 36)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .tint(.red)
            .accessibilityLabel("Back")

            // Center title
            Text(label)
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity, alignment: .center)

            // Right spacer to balance chevron button width
            Color.clear
                .frame(width: 36, height: 36)
        }
        .padding(.horizontal, 6)
        .padding(.top, 6)
        .padding(.bottom, 10)
        // Light separator under the bar to anchor the form visually
        .background(
            VStack(spacing: 0) {
                Color.clear
                Divider().opacity(0.08)
            }
        )
    }

    private func hintText(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(.red)
            .transition(.opacity)
    }
}

private struct BrandHeader: View {
    let mode: AuthViewModel.Mode
    @State private var appear = false

    var body: some View {
        VStack(spacing: 10) {
            AIMobius3DBadgeRed(size: 66)
                .scaleEffect(appear ? 1.0 : 0.96)
                .opacity(appear ? 1 : 0.0)
                .animation(.spring(duration: 0.7, bounce: 0.35), value: appear)

            Text("InvoiceAmericano")
                .font(.title2.bold())

            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .background(
            LinearGradient(
                colors: [
                    Color.red.opacity(0.18),
                    Color(red: 0.85, green: 0.05, blue: 0.10).opacity(0.12),
                    Color(red: 0.75, green: 0.00, blue: 0.05).opacity(0.10)
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .blur(radius: 6)
            .opacity(0.9)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        )
        .onAppear { appear = true }
        .animation(.snappy(duration: 0.45), value: mode)
    }

    private var subtitle: String {
        switch mode {
        case .chooser: return "Choose how you’d like to get started"
        case .signIn:  return "Sign in to continue"
        case .signUp:  return "Create your account"
        }
    }
}

// === 3D Möbius strip badge — Red palette ===
private struct AIMobius3DBadgeRed: View {
    var size: CGFloat = 60
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(LinearGradient(colors: [Color.white.opacity(0.10), Color.white.opacity(0.04)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .blur(radius: 2)

            MobiusSceneViewRed()
        }
        .frame(width: size * 1.2, height: size * 1.2)
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

private struct MobiusSceneViewRed: UIViewRepresentable {
    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.layer.masksToBounds = false
        view.preferredFramesPerSecond = 60
        view.rendersContinuously = true
        view.allowsCameraControl = false
        view.backgroundColor = .clear

        let scene = SCNScene()
        view.scene = scene
        view.isPlaying = true
        view.antialiasingMode = .multisampling4X

        let camNode = SCNNode()
        camNode.camera = SCNCamera()
        camNode.position = SCNVector3(0, 0.05, 3.4)
        if let cam = camNode.camera {
            cam.wantsHDR = true
            cam.bloomIntensity = 0.9
            cam.bloomThreshold = 0.55
            cam.bloomBlurRadius = 8.0
            cam.fieldOfView = 38
        }
        scene.rootNode.addChildNode(camNode)

        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .omni
        key.position = SCNVector3(3, 4, 5)
        key.light?.intensity = 1200
        scene.rootNode.addChildNode(key)

        let rim = SCNNode()
        rim.light = SCNLight()
        rim.light?.type = .directional
        rim.eulerAngles = SCNVector3(-Float.pi/3, Float.pi/6, 0)
        rim.light?.intensity = 900
        scene.rootNode.addChildNode(rim)

        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 380
        ambient.light?.color = UIColor(white: 1.0, alpha: 1.0)
        scene.rootNode.addChildNode(ambient)

        let mobius = SCNNode(geometry: makeMobiusGeometry(R: 1.0, width: 0.35, uCount: 180, vCount: 24))
        mobius.geometry?.firstMaterial = Self.makeRedMaterial()
        mobius.eulerAngles = SCNVector3(-0.25, 0.45, 0)
        mobius.scale = SCNVector3(0.75, 0.75, 0.75)
        scene.rootNode.addChildNode(mobius)

        let spin = SCNAction.repeatForever(SCNAction.rotateBy(x: 0, y: CGFloat.pi * 2, z: 0, duration: 9.0))
        let bobUp = SCNAction.moveBy(x: 0, y: 0.06, z: 0, duration: 1.8); bobUp.timingMode = .easeInEaseOut
        mobius.runAction(.group([spin, .repeatForever(.sequence([bobUp, bobUp.reversed()]))]))

        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {}

    private static func makeRedMaterial() -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased

        let gradient = CAGradientLayer()
        gradient.colors = [
            UIColor(red: 0.88, green: 0.04, blue: 0.09, alpha: 1).cgColor, // crimson
            UIColor(red: 0.95, green: 0.00, blue: 0.00, alpha: 1).cgColor, // vivid red
            UIColor(red: 0.82, green: 0.00, blue: 0.05, alpha: 1).cgColor, // deep red
            UIColor(red: 0.95, green: 0.00, blue: 0.00, alpha: 1).cgColor  // vivid red
        ]
        gradient.locations = [0.0, 0.5, 0.8, 1.0]
        gradient.startPoint = CGPoint(x: 0, y: 0.5)
        gradient.endPoint   = CGPoint(x: 1, y: 0.5)
        gradient.frame = CGRect(x: 0, y: 0, width: 512, height: 512)

        let rotation = CABasicAnimation(keyPath: "transform.rotation.z")
        rotation.toValue = CGFloat.pi * 2
        rotation.duration = 14
        rotation.repeatCount = .infinity
        gradient.add(rotation, forKey: "rotate")

        UIGraphicsBeginImageContextWithOptions(gradient.frame.size, false, 2)
        gradient.render(in: UIGraphicsGetCurrentContext()!)
        let img = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        m.diffuse.contents = img
        m.emission.contents = img
        m.emission.intensity = 0.75

        m.metalness.contents = 0.55
        m.roughness.contents = 0.32
        m.isDoubleSided = true
        return m
    }
}

// Shared Möbius geometry helper
private func makeMobiusGeometry(R: Float, width: Float, uCount: Int, vCount: Int) -> SCNGeometry {
    let U = max(12, uCount), V = max(2, vCount)
    var vertices: [SCNVector3] = [], normals: [SCNVector3] = [], uvs: [CGPoint] = [], indices: [CInt] = []

    func p(u: Float, v: Float) -> SIMD3<Float> {
        let theta = u * 2 * .pi
        let halfTwist = theta / 2
        let w = (width * v)
        let x = (R + w * cos(halfTwist)) * cos(theta)
        let y = (R + w * cos(halfTwist)) * sin(theta)
        let z =  w * sin(halfTwist)
        return .init(x, y, z)
    }

    for ui in 0...U {
        for vi in 0...V {
            let uu = Float(ui) / Float(U)
            let vv = (Float(vi) / Float(V)) * 2 - 1
            let pos = p(u: uu, v: vv)
            vertices.append(.init(pos))

            let eps: Float = 0.001
            let pu = p(u: min(1, uu + eps), v: vv) - p(u: max(0, uu - eps), v: vv)
            let pv = p(u: uu, v: min(1, vv + eps)) - p(u: uu, v: max(-1, vv - eps))
            var n = simd_normalize(simd_cross(pu, pv))
            if !(n.x.isFinite && n.y.isFinite && n.z.isFinite) || simd_length(n) == 0 { n = .init(0,0,1) }
            normals.append(.init(n))
            uvs.append(.init(x: CGFloat(uu), y: CGFloat((vv + 1) * 0.5)))
        }
    }

    let stride = V + 1
    for ui in 0..<U {
        for vi in 0..<V {
            let a = CInt(ui * stride + vi)
            let b = CInt((ui + 1) * stride + vi)
            let c = CInt((ui + 1) * stride + (vi + 1))
            let d = CInt(ui * stride + (vi + 1))
            indices.append(contentsOf: [a, b, c, a, c, d])
        }
    }

    let vSrc = SCNGeometrySource(vertices: vertices)
    let nSrc = SCNGeometrySource(normals: normals)
    let tSrc = SCNGeometrySource(textureCoordinates: uvs)
    let idx = Data(bytes: indices, count: indices.count * MemoryLayout<CInt>.size)
    let elem = SCNGeometryElement(data: idx, primitiveType: .triangles, primitiveCount: indices.count / 3, bytesPerIndex: MemoryLayout<CInt>.size)
    return SCNGeometry(sources: [vSrc, nSrc, tSrc], elements: [elem])
}

// MARK: - Reused UI bits

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

private struct BannerToast: View {
    let text: String
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "envelope.badge")
                .imageScale(.medium)
                .foregroundStyle(.white)
            Text(text)
                .foregroundStyle(.white)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(LinearGradient(colors: [.blue, .indigo],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .shadow(color: .black.opacity(0.15), radius: 10, y: 6)
        )
        .padding(.horizontal, 16)
    }
}

private struct LoadingOverlay: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.15).ignoresSafeArea()
            ProgressView()
                .controlSize(.large)
                .tint(.blue)
                .padding(16)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
    }
}
