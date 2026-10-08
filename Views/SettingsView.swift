import SwiftUI

struct SettingsView: View {
    @Bindable var store: DisplayStore
    @State private var presetName = ""
    @State private var showsPresets = false

    var body: some View {
        VStack(spacing: 0) {
            DisplaysView(store: store)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            presetsSection
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
        }
        .frame(minWidth: 840, minHeight: 600)
        .navigationTitle(L10n.t("app.name", store.language))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Picker(L10n.t("settings.language", store.language), selection: Binding(
                    get: { store.language },
                    set: { store.setLanguage($0) }
                )) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.label).tag(language)
                    }
                }
                .frame(width: 170)
                .controlSize(.small)
                .help(L10n.t("settings.appLanguage", store.language))
            }
        }
    }

    private var presetsUnavailable: Bool {
        store.displays.isEmpty || store.isChangingPhysicalConfiguration || store.physicalConfigurationRequest != nil ||
        store.isPreparingVirtualHiDPI || store.pendingModeChange != nil ||
        store.pendingVirtualSeconds != nil || store.virtualSession != nil
    }

    private var presetsSection: some View {
        DisclosureGroup(isExpanded: $showsPresets) {
            VStack(alignment: .leading, spacing: 10) {
                Text(L10n.t("preset.note", store.language))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    TextField(L10n.t("preset.name", store.language), text: $presetName)
                        .accessibilityLabel(L10n.t("preset.name", store.language))
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 280)
                        .onSubmit(savePreset)
                    Button(L10n.t("preset.saveCurrent", store.language), action: savePreset)
                        .buttonStyle(.bordered)
                        .disabled(presetsUnavailable || presetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                if store.presets.isEmpty {
                    Text(L10n.t("preset.empty", store.language))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(store.presets) { preset in
                                HStack(alignment: .top, spacing: 12) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(preset.name).font(.body.weight(.semibold))
                                        Text(preset.displayModes.map { "\($0.displayName): \($0.mode.label)" }.joined(separator: " · "))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    Spacer()
                                    Button(L10n.t("hidpi.apply", store.language)) {
                                        store.applyPreset(preset)
                                    }
                                    .disabled(presetsUnavailable || preset.displayModes.isEmpty)
                                    Button(L10n.t("preset.delete", store.language), role: .destructive) {
                                        store.deletePreset(preset)
                                    }
                                    .disabled(store.isChangingPhysicalConfiguration || store.physicalConfigurationRequest != nil)
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 150)
                }
            }
            .padding(.top, 10)
        } label: {
            Label(L10n.t("preset.title", store.language), systemImage: "bookmark")
                .font(.callout.weight(.medium))
        }
    }

    private func savePreset() {
        let name = presetName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !presetsUnavailable, !name.isEmpty else { return }
        store.savePreset(named: name)
        presetName = ""
    }
}
