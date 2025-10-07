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
    
    // Kategorien
    @State private var showCategoryManager = false
    
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
                
                Section("Kategorien") {
                    NavigationLink {
                        CategoryManagementView()
                            .environmentObject(store)
                    } label: {
                        Label("Kategorien verwalten", systemImage: "tag")
                    }
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

// MARK: - Kategorieverwaltung (inline in derselben Datei, minimalinvasiv)

private struct CategoryManagementView: View {
    @EnvironmentObject var store: FinanceStore
    @State private var showCreate = false
    @State private var editing: TransactionCategory?
    
    var body: some View {
        List {
            if store.categories.isEmpty {
                Section {
                    Text("Noch keine Kategorien").foregroundStyle(.secondary)
                }
            } else {
                Section {
                    ForEach(store.categories) { cat in
                        HStack {
                            Circle()
                                .fill(cat.swiftUIColor)
                                .frame(width: 12, height: 12)
                            Text(cat.name)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            editing = cat
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                store.removeCategory(cat)
                            } label: {
                                Label("Löschen", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Kategorien")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showCreate = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        // Erstellen
        .sheet(isPresented: $showCreate) {
            NavigationStack {
                CreateOrEditCategoryView { new in
                    // Bereits in Store angelegt; nichts weiter nötig
                }
                .environmentObject(store)
            }
            .presentationDetents([.medium, .large])
        }
        // Bearbeiten
        .sheet(item: $editing) { cat in
            NavigationStack {
                EditCategoryView(original: cat)
                    .environmentObject(store)
            }
            .presentationDetents([.medium, .large])
        }
    }
}

// Einfache Bearbeitungsmaske, die CreateOrEditCategoryView-Logik spiegelt
private struct EditCategoryView: View {
    @EnvironmentObject var store: FinanceStore
    @Environment(\.dismiss) private var dismiss
    let original: TransactionCategory
    @State private var name: String
    @State private var color: Color
    
    init(original: TransactionCategory) {
        self.original = original
        _name = State(initialValue: original.name)
        _color = State(initialValue: original.swiftUIColor)
    }
    
    var body: some View {
        Form {
            Section("Kategorie") {
                TextField("Name", text: $name)
                ColorPicker("Farbe", selection: $color, supportsOpacity: false)
            }
        }
        .navigationTitle("Kategorie bearbeiten")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Abbrechen") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Speichern") {
                    var updated = original
                    updated.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    updated.color = ColorValue(color: color)
                    store.updateCategory(updated)
                    dismiss()
                }
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }
}
