import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject var store: FinanceStore
    @AppStorage("appearanceMode") private var appearanceMode: AppearanceMode = .system
    @AppStorage("appLockEnabled") private var appLockEnabled: Bool = false
    @State private var confirmReset = false
    
    // Import
    @State private var showImportSheet = false
    @State private var pendingImportURL: URL?
    @State private var confirmImport = false
    @State private var importResultMessage: String?
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Sicherheit") {
                    Toggle("Beim Öffnen mit Face ID/Code entsperren", isOn: $appLockEnabled)
                    Text("Wenn aktiviert, muss beim Start der App (oder nach dem Zurückkehren in den Vordergrund) per Face ID oder Gerätecode entsperrt werden.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                
                Section("Darstellung") {
                    Picker("Modus", selection: $appearanceMode) {
                        ForEach(AppearanceMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text("Die Einstellung überschreibt die Systemvorgabe, wenn „Hell“ oder „Dunkel“ gewählt ist.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                
                Section("Backup") {
                    // Export: kompletter Zustand als JSON
                    ShareLink(item: store.exportAll(),
                              preview: SharePreview("FinanceOverview-Backup.json")) {
                        Label("Alles exportieren", systemImage: "square.and.arrow.up")
                    }
                    
                    // Import: JSON auswählen und nach Bestätigung importieren
                    Button {
                        showImportSheet = true
                    } label: {
                        Label("Alles importieren", systemImage: "square.and.arrow.down")
                    }
                    .tint(.accentColor)
                    
                    if let msg = importResultMessage {
                        Text(msg)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Section("Daten") {
                    Button(role: .destructive) {
                        confirmReset = true
                    } label: {
                        Label("Alle Daten löschen", systemImage: "trash")
                    }
                }
                
                Section("Info") {
                    HStack {
                        Text("App")
                        Spacer()
                        Text("Finance Overview")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Einstellungen")
            .alert("Wirklich alle Daten löschen?", isPresented: $confirmReset) {
                Button("Abbrechen", role: .cancel) {}
                Button("Löschen", role: .destructive) {
                    store.resetToEmpty()
                }
            } message: {
                Text("Diese Aktion kann nicht rückgängig gemacht werden.")
            }
            .fileImporter(isPresented: $showImportSheet,
                          allowedContentTypes: [.json, .data, .plainText],
                          allowsMultipleSelection: false) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    pendingImportURL = url
                    confirmImport = true
                case .failure(let error):
                    importResultMessage = "Import fehlgeschlagen: \(error.localizedDescription)"
                }
            }
            .confirmationDialog("Alles importieren?",
                                isPresented: $confirmImport,
                                titleVisibility: .visible) {
                Button("Importieren (überschreibt alles)", role: .destructive) {
                    performImport()
                }
                Button("Abbrechen", role: .cancel) {}
            } message: {
                Text("Der Import ersetzt alle Konten, Buchungen, Geldanlagen, Schulden und Einstellungen.")
            }
        }
    }
    
    private func performImport() {
        guard let url = pendingImportURL else { return }
        do {
            try store.importAll(from: url)
            importResultMessage = "Import erfolgreich."
        } catch {
            importResultMessage = "Import fehlgeschlagen: \(error.localizedDescription)"
        }
    }
}
