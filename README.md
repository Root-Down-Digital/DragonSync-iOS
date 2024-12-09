# DragonSync iOS

<p align="center">
  <img src="https://github.com/user-attachments/assets/35f7de98-7256-467d-a983-6eed49e90796" alt="Dragon Logo" width="175">
</p>

> Revolutionize your airspace awareness. Stay ahead with real-time monitoring, instant alerts, and robust protocol support.

## Features

- **Real-Time Airspace Monitoring**  
  Effortlessly track the status and location of Remote ID-compliant UAVs on your iOS device, no setup required.   

- **Instant System Alerts**  
  Stay informed with real-time notifications about your WarDragon system’s performance.

- **Seamless WarDragon Integration**  
  Designed to work flawlessly with the WarDragon DragonOS platform, providing a unified and user-friendly experience out of the box. 

- **Flexible Protocol Support**  
  Supports ZMQ and Multicast configurations to receive Cursor on Target (CoT) and status messages, tailored to your operational needs.   

## Functionality

- View decoded OpenDroneID data from serial numbers to operator locations: 

<p align="left">
  <img src="https://github.com/user-attachments/assets/aa022b5b-5ce3-4798-9004-7509b027c5bf">
<img src="https://github.com/user-attachments/assets/885d1451-e05a-4393-ba3f-21b34393ed69">

  - Configurable network settings and an immersive UI. Detail views in the system and live map view provide insights, flight paths & more

<img src="https://github.com/user-attachments/assets/c72413d8-37f3-4768-8a87-65554e0f2f31">
</p>

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

- Once installed, launch DragonSync on your iOS device. Ensure that your device is connected to the same network as your WarDragon system.

- **WarDragon**: already installed as a service. **Other devices**: Launch the scripts from DroneID and dragonsync to start the monitor and broadcast. *(Specific commands to follow after testing is complete)*. 

- The app will automatically detect and connect to the system when you select Start Listening, providing you with real-time CoT data and status updates.

## Credits

Foundational: [DragonSync](https://github.com/alphafox02/DragonSync) and [DroneID](https://github.com/bkerler/DroneID). 

None of this would be possible without that work. A big thanks to the devs at [Sniffle](https://github.com/nccgroup/Sniffle). And of course to [@alphafox02](https://github.com/alphafox02) for creating the WarDragon, DragonOS, the above scripts- and showing me how to make this work.

DragonSync is built upon the foundational work of [cemaxecuter](cemaxecuter.com). Check out his work here on GitHub: [@alphafox02](https://github.com/alphafox02). We extend our gratitude for their contributions to the open-source community, which have been instrumental in the development of this application.

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
