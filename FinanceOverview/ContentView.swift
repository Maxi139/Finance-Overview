import SwiftUI
import LocalAuthentication
import UIKit

struct ContentView: View {
    @EnvironmentObject var store: FinanceStore
    @AppStorage("appLockEnabled") private var appLockEnabled: Bool = false
    @Environment(\.scenePhase) private var scenePhase
    
    @State private var isLocked: Bool = false
    @State private var isAuthenticating: Bool = false
    @State private var authErrorMessage: String?
    // Merker: Wurde in dieser App-Sitzung bereits erfolgreich entsperrt?
    @State private var hasAuthenticatedThisSession: Bool = false
    // Zeitpunkt, wann die App den Fokus verloren hat (inactive/background)
    @State private var lastUnfocusedAt: Date?
    // Schwelle in Sekunden
    private let relockThreshold: TimeInterval = 30
    
    var body: some View {
        TabView {
            OverviewView()
                .tabItem { Label("Überblick", systemImage: "rectangle.grid.2x2") }
            
            TransactionsView()
                .tabItem { Label("Buchungen", systemImage: "list.bullet.rectangle") }
            
            AccountsView()
                .tabItem { Label("Konten", systemImage: "creditcard") }
            
            StatsView()
                .tabItem { Label("Statistiken", systemImage: "chart.line.uptrend.xyaxis") }
            
            SettingsView()
                .tabItem { Label("Einstellungen", systemImage: "gear") }
        }
        // Erfolgsoverlay (nur 🎉-Konfetti)
        .overlay {
            if let ov = store.successOverlay {
                GlobalSuccessOverlayView(data: ov)
                    .transition(.opacity)
                    .ignoresSafeArea()
                    .onTapGesture {
                        store.successOverlay = nil
                    }
                    .task(id: ov.id) {
                        // 5 Sekunden anzeigen, falls nicht vorher angetippt
                        try? await Task.sleep(nanoseconds: 5_000_000_000)
                        if store.successOverlay?.id == ov.id {
                            store.successOverlay = nil
                        }
                    }
            }
        }
        // Pot-Celebration Overlay (volle Emojis 🎉✨🎯💸🏆)
        .overlay {
            if let pc = store.potCelebration {
                PotGoalCelebrationOverlayView(data: pc)
                    .transition(.opacity)
                    .ignoresSafeArea()
                    .onAppear {
                        let gen = UINotificationFeedbackGenerator()
                        gen.notificationOccurred(.success)
                    }
                    .onTapGesture {
                        store.potCelebration = nil
                    }
                    .task(id: pc.id) {
                        try? await Task.sleep(nanoseconds: 4_000_000_000)
                        if store.potCelebration?.id == pc.id {
                            store.potCelebration = nil
                        }
                    }
            }
        }
        // App-Lock Overlay – liegt über allem
        .overlay {
            if isLocked && appLockEnabled {
                lockOverlay
                    .ignoresSafeArea()
                    .transition(.opacity)
            }
        }
        .onAppear {
            // Beim App-Start sperren (einmal pro Prozesslebenszeit)
            if appLockEnabled && !hasAuthenticatedThisSession {
                isLocked = true
                tryAuthIfNeeded()
            }
        }
        .onChange(of: appLockEnabled) { _, enabled in
            if enabled {
                // Beim Aktivieren: einmalig entsperren, falls noch nicht in dieser Sitzung
                if !hasAuthenticatedThisSession {
                    isLocked = true
                    tryAuthIfNeeded()
                }
            } else {
                // Deaktiviert: sofort entsperren
                isLocked = false
                authErrorMessage = nil
            }
        }
        // WICHTIG: Fokus-/Lebenszyklus-Überwachung für Re-Lock nach 30s
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .inactive, .background:
                // App verliert Fokus (z. B. Control Center, Multitasking, Anruf, App Switcher)
                lastUnfocusedAt = Date()
            case .active:
                // App wieder aktiv: prüfen, ob die Schwelle überschritten wurde
                if appLockEnabled, let left = lastUnfocusedAt {
                    let elapsed = Date().timeIntervalSince(left)
                    if elapsed >= relockThreshold {
                        // Re-Lock erzwingen, unabhängig von hasAuthenticatedThisSession
                        isLocked = true
                        authErrorMessage = nil
                        isAuthenticating = false
                        tryAuthIfNeeded(force: true)
                    }
                }
            @unknown default:
                break
            }
        }
    }
    
    private var lockOverlay: some View {
        ZStack {
            Color.black.opacity(0.25)
            VStack(spacing: 16) {
                Image(systemName: "lock.circle.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.tint)
                Text("App gesperrt")
                    .font(.headline)
                if let msg = authErrorMessage {
                    Text(msg)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                Button {
                    tryAuthIfNeeded(force: true)
                } label: {
                    Label("Entsperren", systemImage: "faceid")
                }
                .buttonStyle(.borderedProminent)
                .disabled(isAuthenticating)
            }
            .padding()
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding()
        }
    }
    
    private func tryAuthIfNeeded(force: Bool = false) {
        guard !isAuthenticating || force else { return }
        authenticate()
    }
    
    private func authenticate() {
        isAuthenticating = true
        authErrorMessage = nil
        
        let context = LAContext()
        context.localizedFallbackTitle = "Code eingeben"
        var error: NSError?
        let policy: LAPolicy = .deviceOwnerAuthentication // Biometrie mit Code-Fallback
        
        if context.canEvaluatePolicy(policy, error: &error) {
            let reason = "App entsperren"
            context.evaluatePolicy(policy, localizedReason: reason) { success, evalError in
                DispatchQueue.main.async {
                    self.isAuthenticating = false
                    if success {
                        self.isLocked = false
                        self.hasAuthenticatedThisSession = true
                        self.authErrorMessage = nil
                        let gen = UINotificationFeedbackGenerator()
                        gen.notificationOccurred(.success)
                    } else {
                        self.isLocked = true
                        if let evalError {
                            self.authErrorMessage = (evalError as NSError).localizedDescription
                        } else {
                            self.authErrorMessage = "Entsperren fehlgeschlagen."
                        }
                    }
                }
            }
        } else {
            DispatchQueue.main.async {
                self.isAuthenticating = false
                self.isLocked = true
                self.authErrorMessage = "Keine Biometrie/Code verfügbar."
            }
        }
    }
}

// MARK: - GlobalSuccessOverlayView (nur 🎉-Konfetti)

private struct GlobalSuccessOverlayView: View {
    let data: SaveSuccessOverlay
    
    var body: some View {
        ZStack {
            // Vollflächig System-Hintergrundfarbe, vollständig deckend
            Color(uiColor: .systemBackground)
                .ignoresSafeArea()
            
            // Konfetti + Inhalte
            VStack(spacing: 16) {
                EmojiConfettiView(emojis: ["🎉"])
                    .allowsHitTesting(false)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(
                        VStack(spacing: 8) {
                            Image(systemName: icon(for: data.kind))
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(color(for: data.kind))
                                .font(.system(size: 44, weight: .bold))
                            Text(data.name.isEmpty ? data.kind.rawValue : data.name)
                                .font(.headline)
                            Text(formatCurrency(data.amount))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text("Gespeichert")
                                .font(.footnote.weight(.semibold))
                                .padding(.top, 4)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(.thinMaterial, in: Capsule())
                        }
                        .padding()
                    )
            }
        }
    }
    
    private func icon(for kind: TransactionKind) -> String {
        switch kind {
        case .expense: return "arrow.down.circle.fill"
        case .income: return "arrow.up.circle.fill"
        case .transfer: return "arrow.left.arrow.right.circle.fill"
        }
    }
    private func color(for kind: TransactionKind) -> Color {
        switch kind {
        case .expense: return .red
        case .income: return .green
        case .transfer: return .blue
        }
    }
}

// MARK: - 🎯 Pot Goal Celebration Overlay (volle Emojis)

private struct PotGoalCelebrationOverlayView: View {
    let data: PotCelebrationOverlay
    
    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground)
                .ignoresSafeArea()
            VStack(spacing: 16) {
                EmojiConfettiView(intensity: .high, emojis: ["🎉","✨","🎯","💸","🏆"])
                    .allowsHitTesting(false)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(
                        VStack(spacing: 10) {
                            Image(systemName: "target")
                                .font(.system(size: 56, weight: .bold))
                                .foregroundStyle(.tint)
                            Text("Ziel erreicht!")
                                .font(.title2.weight(.bold))
                            Text(data.potName)
                                .font(.headline)
                            VStack(spacing: 4) {
                                Text("Ziel: \(formatCurrency(data.goal))")
                                Text("Gespart: \(formatCurrency(data.saved))")
                                    .foregroundStyle(.secondary)
                                    .font(.subheadline)
                            }
                            .font(.subheadline)
                            .padding(.top, 4)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.thinMaterial, in: Capsule())
                        }
                        .padding()
                    )
            }
        }
    }
}

// MARK: - 🎉 Emoji-Konfetti via CAEmitterLayer (parametrisierbar)

private struct EmojiConfettiView: UIViewRepresentable {
    enum Intensity { case normal, high }
    var intensity: Intensity = .normal
    var emojis: [String] = ["🎉"]
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        
        let emitter = CAEmitterLayer()
        emitter.emitterPosition = CGPoint(x: UIScreen.main.bounds.width / 2, y: -10)
        emitter.emitterShape = .line
        emitter.emitterSize = CGSize(width: UIScreen.main.bounds.width, height: 1)
        
        func cell(for emoji: String) -> CAEmitterCell {
            let cell = CAEmitterCell()
            cell.birthRate = intensity == .high ? 18 : 8
            cell.lifetime = 6.0
            cell.lifetimeRange = 2.0
            cell.velocity = intensity == .high ? 280 : 220
            cell.velocityRange = 120
            cell.emissionLongitude = .pi
            cell.emissionRange = .pi / 6
            cell.spin = 4.0
            cell.spinRange = 2.5
            cell.scale = 0.8
            cell.scaleRange = 0.4
            cell.contents = emojiImage(emoji, size: 28)?.cgImage
            return cell
        }
        
        emitter.emitterCells = emojis.map(cell(for:))
        view.layer.addSublayer(emitter)
        
        // Geburt kurzzeitig, dann stoppen
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            emitter.birthRate = 0
        }
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {}
    
    private func emojiImage(_ emoji: String, size: CGFloat) -> UIImage? {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        return renderer.image { _ in
            let font = UIFont.systemFont(ofSize: size)
            let attributes: [NSAttributedString.Key: Any] = [.font: font]
            let textSize = (emoji as NSString).size(withAttributes: attributes)
            let rect = CGRect(x: (size - textSize.width) / 2,
                              y: (size - textSize.height) / 2,
                              width: textSize.width,
                              height: textSize.height)
            (emoji as NSString).draw(in: rect, withAttributes: attributes)
        }
    }
}
