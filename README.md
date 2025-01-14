# DragonSync iOS
<p align="left">
  <img src="https://github.com/user-attachments/assets/866fe12d-2bd7-431c-9979-0bc32e2bd2fd" >
</p>

> *Revolutionize your airspace awareness. Bridge the power of WarDragon to your iOS device. Stay ahead with real-time monitoring, instant alerts, and robust protocol support.*

## Features

<p align="left">
  <img src="https://github.com/user-attachments/assets/1f7ea78b-37f7-4ef1-939b-a1291d6216b4">
</p>

- **Real-Time Airspace Monitoring**  
  Track the status and location of Remote ID-compliant UAVs on your iOS device. See flightpaths and comprehensive decoded data of any RID broadcast.

- **Spoof Detection**
  Uses advanced algorithms to identify anomalies in flight data, providing a confidence score and detailed insights when spoofing is detected.

  ![image](https://github.com/user-attachments/assets/b06547b7-4f04-4e80-a562-232b96cc8a5b)


- **Instant System Alerts**  
  Stay informed with real-time status updates about your system’s performance. Memory, CPU, temp and more.

- **Seamless WarDragon Integration**  
  Designed to work flawlessly with the WarDragon DragonOS platform directly over ZMQ or broader applications with Multicast. A unified and user-friendly experience out of the box. 

- **Flexible Protocol Support**  
  Supports ZMQ and Multicast configurations to receive CoT and status messages, tailored to your operational needs.

## Installation

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

## Usage
**WarDragon Direct ZMQ**
- Ensure that your device is connected to the same network as your WarDragon or host system.
- Launch the app & choose ZMQ from settings 
- Tap the address and enter the IP of the WarDragon (use `arp -a` for example)
- Start the listener & status and drone detection will happen automatically. 

**Multicast**
- Start dragonsync.py and wardragon-monitor.py from the DragonSync repo.
- From the DroneId repo start zmq_decoder.py and WiFi/BT sniffer. 

(Default multicast address is pre-configured for `dragonsync.py`, adjust per network requirements.)

  _**Refer to [dragonsync.py](https://github.com/alphafox02/DragonSync) for detailed instructions & commands**_

## Credits
We extend our gratitude for their contributions to the open-source community, which have been instrumental in the development of this application.

Foundational: [DragonSync](https://github.com/alphafox02/DragonSync) and [DroneID](https://github.com/bkerler/DroneID). A big thanks to the devs at [Sniffle](https://github.com/nccgroup/Sniffle). And of course to [@alphafox02](https://github.com/alphafox02) for creating the WarDragon, DragonOS, the above scripts- and showing me how to make this work. Thanks to [@bkerler]((https://github.com/bkerler) for the work on `DroneID` and inspiring this project. 

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
