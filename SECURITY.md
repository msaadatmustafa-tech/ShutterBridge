# Security and privacy

ShutterBridge is intended for trusted nearby devices and trusted local Wi-Fi. BLE PIN gating is basic application authorization, not a promise of encrypted pairing. Local HTTP is unencrypted; the random preview URL is a bearer-access link. Commands over HTTP additionally require the visible iPhone Wi-Fi-controls switch. Do not forward the port to the internet.

Never publish active links, session PINs, Apple account credentials, certificates, provisioning profiles, personal footage or private logs. Turn Wi-Fi preview off to revoke its link. If a secret was exposed, revoke/rotate it before reporting the incident.

Please avoid posting exploitable details or credentials in public issues. For non-sensitive security concerns, open an issue with a minimal description and request a private follow-up channel; if GitHub private vulnerability reporting is available on the repository, use it. This personal project has no guaranteed security-response SLA.
