enum WiFiCredentialAuthentication {
    case personal
    case eapTLS
}

struct WiFiCredential {
    let ssid: String
    let authentication: WiFiCredentialAuthentication
    let personalSecurity: WiFiPersonalSecurity
    let password: String?
    let eapIdentity: String?
    let caCertificate: [UInt8]?
    let clientCertificate: [UInt8]?
    let privateKey: [UInt8]?
    let privateKeyPassword: String?

    static func personal(
        ssid: String,
        password: String? = nil,
        security: WiFiPersonalSecurity = .wpa2OrWpa3
    ) -> WiFiCredential {
        WiFiCredential(
            ssid: ssid,
            authentication: .personal,
            personalSecurity: security,
            password: password,
            eapIdentity: nil,
            caCertificate: nil,
            clientCertificate: nil,
            privateKey: nil,
            privateKeyPassword: nil
        )
    }

    static func wpa3Personal(ssid: String, password: String) -> WiFiCredential {
        personal(ssid: ssid, password: password, security: .wpa3Only)
    }

    static func eapTLS(
        ssid: String,
        identity: String? = nil,
        caCertificate: [UInt8],
        clientCertificate: [UInt8],
        privateKey: [UInt8],
        privateKeyPassword: String? = nil
    ) -> WiFiCredential {
        WiFiCredential(
            ssid: ssid,
            authentication: .eapTLS,
            personalSecurity: .wpa2OrWpa3,
            password: nil,
            eapIdentity: identity,
            caCertificate: caCertificate,
            clientCertificate: clientCertificate,
            privateKey: privateKey,
            privateKeyPassword: privateKeyPassword
        )
    }
}

enum WiFiCredentials {
    static let all = configuredWiFiCredentials()
}
