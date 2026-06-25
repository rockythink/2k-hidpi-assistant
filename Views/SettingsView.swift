import SwiftUI

struct SettingsView: View {
    @Bindable var store: DisplayStore

    var body: some View {
        Form {
            Section(L10n.t("settings.language", store.language)) {
                Picker(L10n.t("settings.appLanguage", store.language), selection: Binding(
                    get: { store.language },
                    set: { store.setLanguage($0) }
                )) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.label).tag(language)
                    }
                }
                .pickerStyle(.menu)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 360)
        .padding()
    }
}
