/*
 Copy this file to WiFiCredentials.local.swift. The local file is ignored by Git.
 Keep candidates in priority order; the first available valid network wins.
*/

func configuredWiFiCredentials() -> [WiFiCredential] {
    let enterpriseCACertificate: [UInt8] = []
    let enterpriseClientCertificate: [UInt8] = []
    let enterprisePrivateKey: [UInt8] = []

    return [
        .eapTLS(
            ssid: "Enterprise Wi-Fi",
            identity: nil,
            caCertificate: enterpriseCACertificate,
            clientCertificate: enterpriseClientCertificate,
            privateKey: enterprisePrivateKey
        ),
        .personal(
            ssid: "Backup Wi-Fi",
            password: "replace-with-the-Wi-Fi-password"
        ),
    ]
}
