# DragonSync iOS

<p align="left">
  <img src="https://github.com/user-attachments/assets/d21ab909-7dba-4b42-8996-a741248e9223">
</p>

> *Revolutionize your airspace awareness. Bridge the power of WarDragon to your iOS device. Stay ahead with real-time monitoring, instant alerts, and robust protocol support.*

***TestFlight is open: [Join the beta](https://testflight.apple.com/join/QKDKMSfA)***

## Features

- **Real-Time Airspace Monitoring**  
  Track the status and location of Remote ID-compliant UAVs on your iOS device. See flightpaths and comprehensive decoded data of any RID broadcast.

- **Spoof Detection**
  Uses advanced algorithms to identify anomalies in flight data, providing a confidence score and detailed insights when spoofing is detected.

  ![image](https://github.com/user-attachments/assets/b06547b7-4f04-4e80-a562-232b96cc8a5b)


- **Instant System Alerts**  
  Stay informed with real-time status updates about your system’s performance & location. Memory, GPS, CPU, temp and more. WarDragon Pro also displays ANTSDR internal temperatures.

- **Detect the Undetectable:**

  *SDR-Powered Drone Detection & Decoding with WarDragon Pro. Support for Ocusync and other difficult signals*

  OcuSync's advanced frequency-hopping and encrypted communication make it nearly invisible to standard detection tools.

- **Seamless WarDragon Integration**  
  Designed to work flawlessly with the WarDragon DragonOS platform directly over ZMQ or broader applications with Multicast. A unified and user-friendly experience out of the box. 

- **Flexible Protocol Support**  
  Supports ZMQ and Multicast configurations to receive CoT and status messages, tailored to your operational needs.

## Requirements

**Option 1. [WarDragon/Pro](https://cemaxecuter.com/?post_type=product)**

**Option 2. DIY**

*Hardware*
- ESP32
- Sniffle compatible BT dongle
- ANTSDR E200
- GPS unit

*Software*
- [DroneID](https://github.com/alphafox02/DroneID)
- [DragonSync Python](https://github.com/alphafox02/DragonSync)
- [DJI Firmware - E200](https://github.com/alphafox02/antsdr_dji_droneid)
- [DJI Firmware - ESP32](https://github.com/alphafox02/T-Halow/tree/wifi_rid/examples/DragonOS_RID_Scanner)


## Usage

> [!NOTE]
> It's important to be using the latest versions of @alphafox02 DroneID and DragonSync repos listed above.
>
>To update, navigate to the folders in the `WarDragon` directory in the home directory of the dragon (or in your location) using the command line. Run `git pull` inside both. 

### Connection
The app supports two connection formats:

> **ZMQ Server (JSON)**
> - Includes all data available. Easy setup with direct ZMQ connection and minimal configuration. ***Recommended***

> **Multicast (CoT)**
> - Limited data compared to ZMQ. Needs additional script running and network setup for multicast. Supports multiple sources at once on same network. 

**Using WarDragon Direct ZMQ**
- Ensure that your device is connected to the same network as your WarDragon or host system.
- Launch the app & choose ZMQ from settings 
- Tap the address and enter the IP of the WarDragon (use `arp -a` for example)
- Start the listener & status and drone detection will happen automatically. 

**Multicast**
- Start dragonsync.py and wardragon-monitor.py from the DragonSync repo.
- From the DroneId repo start zmq_decoder.py and WiFi/BT sniffer. 

(Default multicast address is pre-configured for `dragonsync.py`, adjust per network requirements.)

  _**Refer to [dragonsync.py](https://github.com/alphafox02/DragonSync) for detailed instructions & commands**_

  
### Detection

Once activated, detected drones appear in the Drones and History tabs. 

**Drones View**
- Tap the map to view a live feed of drone flight paths from the current session. Select the text to open the detail view, which displays collected data, including takeoff and operator locations when available.

**Encounter History**
- Swipe left on each row to delete it. To export a CSV file or delete the history, use the icon in the top right corner.
- Select a row to visualize the flight data. To export a KML file or change the map style, use the icon in the top right corner. 

### Settings

Warning dials set the value at which dashboard elements change or appear. These differ from the static defaults in the status view. 

![image](https://github.com/user-attachments/assets/3a3651c2-38c5-4eab-902a-d61198e677c0)

- Temps and usage will show red when settings are exceeded
- Drones nearby warning is based on the proximity warning value. 

## Build/Install

1. **Clone the Repository**  
   Clone the project repository to your local machine using the following command:  
   `git clone https://github.com/Root-Down-Digital/DragonSync-iOS.git`

2. **Install Dependencies**  
   Navigate to the project directory and install CocoaPods dependencies:  
   `cd DragonSync-iOS`  
   `pod install`

3. **Open the Project in Xcode**  
   Open the workspace file generated by CocoaPods:  
   `open WarDragon.xcworkspace`

4. **Build and Run the Project**  
   - Connect your iOS device to your computer.  
   - In Xcode, select your device from the build target options.  
   - Click the **Build and Run** button to install and launch the app on your device.

## Credits
We extend our gratitude for their contributions to the open-source community, which have been instrumental in the laying the foundation for this app to exist. 

Foundational: [DragonSync](https://github.com/alphafox02/DragonSync) and [DroneID](https://github.com/bkerler/DroneID). 

A big thanks to the devs at [Sniffle](https://github.com/nccgroup/Sniffle). 
And of course to [@alphafox02](https://github.com/alphafox02) for creating the WarDragon, DragonOS, the above scripts- and showing me how to make this work. Thanks to [@bkerler](https://github.com/bkerler) for the work on `DroneID` repo. 

## Disclaimer

> [!WARNING]
> This software is provided as-is, without warranty of any kind. Use at your own risk.
Root Down Digital and associated developers are not responsible for any damages, legal issues, or misuse that may arise from the use of DragonSync. Always operate in compliance with local laws and regulations. Ensure compatibility with your WarDragon system and associated hardware.

## License

This project is licensed under the MIT License. See the LICENSE.md file for details.

## Contributing

We welcome contributions to DragonSync. If you have suggestions or improvements, please submit a pull request or open an issue in this repository.

## Contact

For support or inquiries, please contact the development team by opening an issue.

## Additional Notes

> [!NOTE]
> DragonSync is currently in active development. Some features may be incomplete or subject to change.

> [!IMPORTANT]
> Ensure that your WarDragon DragonOS image is updated for optimal compatibility with DragonSync.

> [!TIP]
> Keep your iOS device and WarDragon system on the same local network to ensure seamless communication.

> [!CAUTION]
> Always operate in compliance with local regulations and guidelines to ensure safety and legality.

> [!WARNING]
> Unauthorized use of this application with systems other than WarDragon may result in unexpected behavior or system instability
