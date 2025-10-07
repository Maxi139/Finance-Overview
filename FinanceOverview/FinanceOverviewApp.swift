import SwiftUI

@main
struct FinanceOverviewApp: App {
    @StateObject private var store = FinanceStore()
    @AppStorage("appearanceMode") private var appearanceMode: AppearanceMode = .system
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .preferredColorScheme(appearanceMode.colorScheme)
        }
    }
}
