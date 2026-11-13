//
//  SettingsView.swift
//  CloudDoor
//
//  Created by dean on 30. 9. 24.
//

import SwiftUI

struct SettingsView: View {
    @State var alertTitle = ""
    @State var alertMessage = ""
    @State var showAlert = false
    @State var showAlertWithCancel = false

    @State private var username: String
    @State private var password: String
    
    let configuration = Configuration()
    
    init() {
        let values = configuration.get()
        self.username = values.username
        self.password = values.password
    }

    func fillTestAccountInfo() {
        self.username = "user@example.com"
        self.password = "password"
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Account")) {
                    LabeledContent {
                        TextField("", text: $username, prompt: Text("required"))
                            .keyboardType(UIKeyboardType.emailAddress)
                            .autocapitalization(.none)
                    } label: {
                        Text("Email")
                            .foregroundStyle(.secondary)
                    }

                    LabeledContent {
                        SecureField("", text: $password, prompt: Text("required"))
                    } label: {
                        Text("Password")
                            .foregroundStyle(.secondary)
                    }
                }

                Button("Test & update") {
                    Task {
                        let api = API(url: Hostname.hostname, username: username, password: password)
                        
                        do {
                            let _ = try await api.getToken()
                            
                            configuration.set(username: username, password: password)

                            alertTitle = "Success"
                            alertMessage = "Configuration saved."
                            showAlert = true
                        } catch ApiError.runtimeError(let err) {
                            alertTitle = "Error"
                            alertMessage = "\(err)"
                            showAlert = true
                        } catch {
                            alertTitle = "Error"
                            alertMessage = "Unknown error: \(error)"
                            showAlert = true
                        }
                    }
                }
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
            .alert(alertTitle, isPresented: $showAlert, actions: {
                Button("OK", role: .cancel) { }
            }, message: {
                Text(alertMessage)
            })
        }
    }
}

#Preview {
    SettingsView()
}
