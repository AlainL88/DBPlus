//
//  LockedView.swift
//  DB+
//
//  Schermata di blocco con autenticazione biometrica (Face ID / Touch ID)
//  o passcode. Protegge l'accesso all'app e alle credenziali salvate.
//

import SwiftUI
import LocalAuthentication

struct LockedView: View {
    var onUnlock: () -> Void

    @State private var isAuthenticating = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.fill")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text("DB+ è bloccato")
                .font(.title2)
                .bold()
            Text("Sblocca con Face ID, Touch ID o passcode per accedere alle tue connessioni.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 40)
            }

            Button {
                authenticate()
            } label: {
                Label(isAuthenticating ? "Verifica in corso…" : "Sblocca", systemImage: "faceid")
            }
            .buttonStyle(.borderedProminent)
            .disabled(isAuthenticating)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        .task { authenticate() }
    }

    private func authenticate() {
        guard !isAuthenticating else { return }
        isAuthenticating = true
        errorMessage = nil

        let context = LAContext()
        context.localizedCancelTitle = "Annulla"
        context.localizedFallbackTitle = "Usa passcode"
        let reason = "Sblocca DB+ per accedere alle connessioni salvate."

        var error: NSError?
        let biometricsAvailable = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        let policy: LAPolicy = biometricsAvailable ? .deviceOwnerAuthenticationWithBiometrics : .deviceOwnerAuthentication

        context.evaluatePolicy(policy, localizedReason: reason) { [weak context] success, evalError in
            DispatchQueue.main.async {
                guard !success else {
                    isAuthenticating = false
                    onUnlock()
                    return
                }
                if let laError = evalError as? LAError, laError.code == .userFallback, let context {
                    evaluateWithPasscode(context)
                } else {
                    isAuthenticating = false
                    errorMessage = (evalError as? LAError)?.localizedDescription ?? "Autenticazione non riuscita."
                }
            }
        }
    }

    private func evaluateWithPasscode(_ context: LAContext) {
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Inserisci il passcode per sbloccare DB+.") { success, evalError in
            DispatchQueue.main.async {
                isAuthenticating = false
                if success {
                    onUnlock()
                } else {
                    errorMessage = (evalError as? LAError)?.localizedDescription ?? "Autenticazione non riuscita."
                }
            }
        }
    }
}
