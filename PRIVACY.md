# Privacy Policy for WarDragon

**Last Updated:** January 29, 2026

## Our Commitment to Privacy

WarDragon is committed to protecting your privacy. This privacy policy explains how our app handles data.

## Data Collection

**We do not collect, store, or transmit any personal data.**

WarDragon processes all data entirely on your device. Specifically:

- **No Analytics**: We do not use analytics services or tracking tools
- **No User Accounts**: The app does not require registration or user accounts
- **No Remote Servers**: We do not operate servers that collect or store your data
- **No Third-Party Data Sharing**: We do not share data with third parties

## On-Device Data Processing

WarDragon processes the following data locally on your device:

- **Drone Remote ID signals**: Broadcast signals from nearby drones (if equipped with compatible hardware)
- **ADS-B aircraft data**: Public aircraft position broadcasts from nearby aircraft
- **Location data**: Your device's location is used only for displaying your position relative to detected aircraft and drones. This data never leaves your device.
- **Detection history**: Records of detected drones and aircraft are stored locally in your device's storage using SwiftData

All data remains on your device and under your control. You can delete all stored data at any time through the app's settings.

## Third-Party Frameworks

WarDragon uses the following open-source frameworks for network communication and data processing. These frameworks operate entirely on your device and do not collect or transmit personal data:

- **SwiftyZeroMQ5**: For ZMQ network protocol communication with local hardware
- **CocoaMQTT**: For MQTT protocol support for local network communication
- **CocoaAsyncSocket**: For asynchronous socket communication with local receivers
- **Starscream**: For WebSocket communication support

These frameworks facilitate local network connections only and do not send data to external servers or third parties.

## Network Connectivity

WarDragon may connect to:

- **Local network receivers**: To receive drone and aircraft data from compatible hardware on your local network using the above networking frameworks
- **OpenSky Network** (optional): If you enable ADS-B tracking, the app queries the public OpenSky Network API to retrieve additional aircraft information. These queries use your approximate location but do not transmit personal identifiers.

## Notifications

If you enable notifications, WarDragon will send local notifications on your device when drones or aircraft are detected. These notifications are generated locally and do not involve remote servers.

## Background Processing

If you enable background detection, WarDragon continues processing signals while the app is in the background. All processing occurs on your device.

## Open Source

WarDragon is open source software. You can review the complete source code on GitHub to verify our privacy practices.

## Data Storage Location

All app data is stored locally in your device's:
- **SwiftData database**: For detection history and cached aircraft information
- **UserDefaults**: For app settings and preferences
- **Keychain**: For secure storage of network credentials (if configured)

## Your Rights

You have complete control over your data:
- **Access**: All data is accessible through the app interface
- **Deletion**: You can delete all stored data through the app's settings
- **Export**: Detection data can be exported in Settings > Database Manager

## Children's Privacy

WarDragon does not collect data from anyone, including children under 13.

## Changes to This Policy

We may update this privacy policy to reflect changes in the app. Any changes will be posted in the app's GitHub repository and included in app updates.

## Contact

WarDragon is an open source project available on GitHub. For questions or concerns about privacy, please open an issue on the project's GitHub repository.

## Legal Basis

No personal data is collected or processed, therefore no legal basis for data processing is required under GDPR, CCPA, or other privacy regulations.

---

**Summary**: WarDragon is a privacy-focused app that processes all data on your device. We do not collect, store, or transmit any personal information. Your data stays on your device, under your control.
