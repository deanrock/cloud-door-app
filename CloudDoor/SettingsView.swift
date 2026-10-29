//
//  SettingsView.swift
//  CloudDoor
//
//  Created by dean on 30. 9. 24.
//

import CloudDoorKit
import os
import SwiftUI

struct SettingsView: View {
    @State var alertTitle = ""
    @State var alertMessage = ""
    @State var showAlertWithCancel = false

    @State private var username: String
    @State private var password: String
    @State private var hostname: String
    @FocusState private var focusedField: Field?
    /// What went wrong the last time signing in failed; shown under the button, with its technical details.
    @State private var saveError: ErrorInfo?
    /// The email of the account that is saved, or nil if nobody is signed in. A failed attempt never changes it,
    /// and the error says so.
    @State private var savedAccount: String?
    @State private var showClearConfirmation = false
    /// True after the server accepted the details and they were saved.
    @State private var saveSucceeded = false

    private enum Field {
        case email, password, hostname
    }
    
    let testingHost = "https://cloud-door-mock.test.dejanlevec.com"
    let productionHost = "https://api.doorcloud.com"
    let configuration = Configuration()
    /// Called after new details were saved, so the rest of the app can load the new account's doors.
    let onAccountChanged: () -> Void

    init(onAccountChanged: @escaping () -> Void = {}) {
        self.onAccountChanged = onAccountChanged
        let values = configuration.get()
        self._savedAccount = State(initialValue: values.hostname.isEmpty ? nil : values.username)
        self.username = values.username
        self.password = values.password
        self.hostname = values.hostname == "" ? self.productionHost : values.hostname
    }

    func fillTestAccountInfo() {
        self.username = "user@example.com"
        self.password = "password"
        self.hostname = testingHost
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Account")) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Email")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("", text: $username, prompt: Text("required"))
                            .keyboardType(.emailAddress)
                            .textContentType(.username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.next)
                            .focused($focusedField, equals: .email)
                            .accessibilityIdentifier("emailField")
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Password")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        SecureField("", text: $password, prompt: Text("required"))
                            .textContentType(.password)
                            .submitLabel(.next)
                            .focused($focusedField, equals: .password)
                            .accessibilityIdentifier("passwordField")
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Server")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("", text: $hostname, prompt: Text("required"))
                            .keyboardType(.URL)
                            .textContentType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.done)
                            .focused($focusedField, equals: .hostname)
                            .accessibilityIdentifier("serverField")
                    }
                }
                // Return moves to the next field, and the last one dismisses the keyboard.
                .onSubmit {
                    switch focusedField {
                    case .email: focusedField = .password
                    case .password: focusedField = .hostname
                    default: focusedField = nil
                    }
                }

                Button("Sign In & Save") {
                    // Dismiss the keyboard so the result isn't hidden behind it.
                    focusedField = nil
                    saveError = nil
                    saveSucceeded = false
                    // New details are only saved once the server has accepted them, so a failed attempt keeps
                    // whatever was saved before.
                    Task {
                        let api = API(url: self.hostname, username: username, password: password)

                        do {
                            let _ = try await api.getToken()

                            try configuration.set(username: username, password: password, hostname: hostname)

                            savedAccount = username
                            saveSucceeded = true
                            onAccountChanged()
                        } catch {
                            let info = ErrorInfo(error: error, title: "Couldn't sign in")
                            saveError = info
                            Logger(subsystem: "com.dejanlevec.dooropener", category: "settings")
                                .error("\(info.title, privacy: .public): \(info.message, privacy: .public) [\(info.details ?? "no details", privacy: .public)]")
                        }
                    }
                }

                if saveSucceeded {
                    Section {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(SignInText.successTitle)
                                    .font(.headline)
                                Text(SignInText.successDetail(account: username))
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title2)
                                .foregroundStyle(.green)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("saveSuccess")
                    }
                }

                if let saveError {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            // No icon here: the status below has one, and a second identity icon would say the same twice.
                            Text(saveError.title)
                                .font(.headline)
                                .foregroundStyle(.red)
                            Text(saveError.message)
                                .font(.callout)

                            // What happened to the saved account matters as much as the error itself.
                            if let savedAccount {
                                Label {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(SignInText.stillSignedInTitle)
                                            .font(.subheadline.bold())
                                        Text(SignInText.stillSignedInDetail(account: savedAccount))
                                            .font(.callout)
                                            .foregroundStyle(.secondary)
                                    }
                                } icon: {
                                    Image(systemName: "checkmark.shield.fill")
                                        .foregroundStyle(.green)
                                }
                                .padding(.top, 4)
                                .accessibilityIdentifier("stillSignedIn")
                            } else {
                                Label {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(SignInText.notSignedInTitle)
                                            .font(.subheadline.bold())
                                        Text(SignInText.notSignedInDetail)
                                            .font(.callout)
                                            .foregroundStyle(.secondary)
                                    }
                                } icon: {
                                    Image(systemName: "person.crop.circle.badge.exclamationmark")
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.top, 4)
                            }

                            // The technical facts, such as the server's own code, open in a popup.
                            if saveError.details != nil {
                                DetailsView(info: saveError, alignment: .leading)
                                    .padding(.top, 4)
                            }
                        }
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("saveError")
                    }
                }

                if self.hostname != self.productionHost {
                    Section {
                        Button("Reset to default server") {
                            self.hostname = self.productionHost
                        }
                    }
                }

                // Removes the saved account, for signing out or for starting over.
                if let savedAccount {
                    Section {
                        Button(SignInText.clearButton, role: .destructive) {
                            showClearConfirmation = true
                        }
                        .accessibilityIdentifier("clearCredentials")
                    } footer: {
                        Text("Signed in as \(savedAccount)")
                    }
                }
            }
            .confirmationDialog(SignInText.clearConfirmationTitle, isPresented: $showClearConfirmation, titleVisibility: .visible) {
                Button(SignInText.clearButton, role: .destructive) {
                    configuration.clear()
                    savedAccount = nil
                    username = ""
                    password = ""
                    saveError = nil
                    saveSucceeded = false
                    onAccountChanged()
                }
            } message: {
                Text(SignInText.clearConfirmationMessage)
            }
            .scrollDismissesKeyboard(.interactively)
            .sensoryFeedback(.success, trigger: saveSucceeded) { _, new in new }
            .sensoryFeedback(.error, trigger: saveError?.id)
            // Edited details have not been tried yet, so the "saved and working" message no longer applies.
            .onChange(of: [username, password, hostname]) {
                saveSucceeded = false
            }
            .navigationTitle("Settings")
            .alert(alertTitle, isPresented: $showAlertWithCancel, actions: {
                Button("Cancel", role: .cancel) {}
                Button("OK", role: .destructive) {
                    fillTestAccountInfo()
                }
            }, message: {
                Text(alertMessage)
            })
        }
    }
}

#Preview {
    SettingsView()
}
