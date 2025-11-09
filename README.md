# WaveConnect 📞

A modern Flutter application for real-time voice communication using WebRTC, featuring user authentication, contact management, messaging, and call functionality.

## 🌟 Features

### Core Functionality
- **Real-time Voice Calls**: High-quality voice communication using WebRTC technology
- **User Authentication**: Secure sign-up and login with Firebase Authentication
- **Contact Management**: 
  - Search users by username
  - Add contacts to your contact list
  - View and manage your contacts
  - Remove contacts
- **Messaging**: Real-time text messaging between users
- **Call History**: View all your contacts with search functionality
- **Incoming Call Handling**: Receive and manage incoming calls

### UI/UX
- **Modern Dark Theme**: Beautiful gradient-based dark UI with classic design elements
- **Responsive Design**: Optimized for various screen sizes
- **Smooth Animations**: Polished user experience with smooth transitions
- **Intuitive Navigation**: Easy-to-use bottom navigation bar

## 🛠️ Technologies Used

### Frontend
- **Flutter** (SDK: ^3.9.2) - Cross-platform mobile framework
- **Material Design 3** - Modern UI components

### Backend & Services
- **Firebase Core** (^4.2.1) - Firebase initialization
- **Firebase Authentication** (^6.1.2) - User authentication
- **Cloud Firestore** (^6.1.0) - Real-time database for messages, calls, and user data

### Communication
- **WebRTC** (`flutter_webrtc: ^1.2.0`) - Real-time peer-to-peer voice communication
- **STUN/TURN Servers** - Network traversal for WebRTC connections

### Additional Packages
- **permission_handler** (^12.0.1) - Handle device permissions (microphone, etc.)
- **google_fonts** (^6.2.1) - Custom typography

## 📁 Project Structure

```
lib/
├── main.dart                          # App entry point
├── firebase_options.dart              # Firebase configuration
│
├── Screens/
│   ├── login.dart                     # Login screen
│   ├── sign_up.dart                   # Registration screen
│   ├── home_screen.dart                # Main navigation screen
│   ├── call_screen.dart                # Active call interface
│   ├── incoming_call_screen.dart      # Incoming call notification
│   │
│   └── sections/
│       ├── contacts_screen.dart        # User search and contact management
│       ├── chats_screen.dart          # Chat list view
│       ├── chat_screen.dart            # Individual chat interface
│       └── call_history_screen.dart    # Contacts list with search
│
└── Services/
    ├── firebase_service.dart           # Firebase operations (auth, Firestore)
    └── call_service.dart              # Incoming call handling service
```

## 🚀 Getting Started

### Prerequisites

- Flutter SDK (3.9.2 or higher)
- Dart SDK
- Android Studio / VS Code with Flutter extensions
- Firebase project set up
- Google account for Firebase services

### Installation

1. **Clone the repository**
   ```bash
   git clone <repository-url>
   cd netcalling
   ```

2. **Install dependencies**
   ```bash
   flutter pub get
   ```

3. **Firebase Setup**
   - Create a Firebase project at [Firebase Console](https://console.firebase.google.com/)
   - Enable Authentication (Email/Password)
   - Enable Cloud Firestore
   - Download `google-services.json` for Android
   - Place it in `android/app/google-services.json`
   - For iOS, download `GoogleService-Info.plist` and add it to `ios/Runner/`

4. **Configure Firebase**
   - Update `lib/firebase_options.dart` with your Firebase configuration
   - Or run `flutterfire configure` to auto-generate configuration

5. **Run the app**
   ```bash
   flutter run
   ```

## ⚙️ Configuration

### WebRTC Configuration

The app uses the following STUN/TURN servers for WebRTC:

- **STUN Servers**: Google's public STUN servers
- **TURN Servers**: Metered.ca relay servers (configured in `call_screen.dart`)

To use your own TURN servers, update the configuration in `lib/Screens/call_screen.dart`:

```dart
'iceServers': [
  {
    'urls': [
      'stun:stun1.l.google.com:19302',
      'stun:stun2.l.google.com:19302',
    ],
  },
  // Add your TURN server configuration here
],
```

### Firebase Firestore Structure

#### Users Collection
```
users/
  {userId}/
    - uid: string
    - name: string
    - username: string
    - email: string
    - createdAt: timestamp
```

#### Contacts Collection
```
users/{userId}/contacts/
  {contactId}/
    - uid: string
    - name: string
    - username: string
    - email: string
```

#### Chats Collection
```
chats/
  {chatId}/
    - participants: [userId1, userId2]
    - userNames: {userId1: name1, userId2: name2}
    - lastMessage: string
    - lastTimestamp: timestamp
    messages/
      {messageId}/
        - text: string
        - senderId: string
        - timestamp: timestamp
```

#### Calls Collection
```
calls/
  {callId}/
    - callerId: string
    - calleeId: string
    - state: string (pending/answered/ended)
    - offer: {sdp: string, type: string}
    - answer: {sdp: string, type: string}
    callerCandidates/
      {candidateId}/
        - candidate: string
        - sdpMid: string
        - sdpMLineIndex: number
    calleeCandidates/
      {candidateId}/
        - candidate: string
        - sdpMid: string
        - sdpMLineIndex: number
```

## 📱 Permissions

### Android Permissions
The app requires the following permissions (configured in `AndroidManifest.xml`):

- `RECORD_AUDIO` - For voice calls
- `INTERNET` - For network communication
- `ACCESS_NETWORK_STATE` - Check network connectivity
- `MODIFY_AUDIO_SETTINGS` - Audio routing control
- `BLUETOOTH` / `BLUETOOTH_CONNECT` - Bluetooth audio support

### iOS Permissions
Add to `ios/Runner/Info.plist`:

```xml
<key>NSMicrophoneUsageDescription</key>
<string>We need access to your microphone for voice calls</string>
```

## 🎯 Usage

### Sign Up
1. Open the app
2. Tap "Sign Up"
3. Enter your name, username, email, and password
4. Username must be unique

### Login
1. Enter your username and password
2. Tap "Login"

### Search & Add Contacts
1. Navigate to the Contacts tab
2. Enter a username in the search bar
3. Tap the search button
4. Tap the "Add to Contacts" icon on the search result
5. Contact will appear in the Calls tab

### Make a Call
1. Go to the Calls tab (Call History)
2. Find the contact you want to call
3. Tap the call icon
4. Wait for the connection to establish
5. Use mute/speaker controls during the call

### Send Messages
1. Navigate to the Chats tab
2. Select a chat or start a new one from contacts
3. Type your message and send

### Manage Contacts
- **View Contacts**: Go to Calls tab to see all your contacts
- **Search Contacts**: Use the search bar to filter contacts by name, username, or email
- **Remove Contact**: Tap the delete icon on any contact card

## 🏗️ Architecture

### State Management
- Uses Flutter's built-in `StatefulWidget` for local state
- `StreamBuilder` for real-time Firestore updates
- `CallService` for managing incoming calls

### Key Components

#### FirebaseService
Handles all Firebase operations:
- User authentication (sign up, login, logout)
- User data management
- Contact CRUD operations
- User search functionality

#### CallService
Manages incoming call notifications:
- Listens for incoming calls in Firestore
- Navigates to incoming call screen
- Handles call state changes

#### CallScreen
Core WebRTC implementation:
- Peer connection setup
- SDP offer/answer exchange
- ICE candidate handling
- Audio track management
- Audio output routing (speakerphone)

## 🔧 Troubleshooting

### Audio Issues
If voice is not working:
1. Check microphone permissions
2. Ensure both devices have stable internet connection
3. Verify WebRTC configuration
4. Check device audio settings

### Connection Issues
- Ensure Firebase is properly configured
- Check internet connectivity
- Verify Firestore rules allow read/write access
- Check TURN server credentials if using custom servers

### Build Issues
```bash
# Clean and rebuild
flutter clean
flutter pub get
flutter run
```

## 📝 Development Notes

### WebRTC Audio Optimization
The app includes several optimizations for reliable audio:
- SDP modification to ensure bidirectional audio (`a=sendrecv`)
- Periodic audio track re-enablement
- Multiple connection state checks
- Audio output routing management
- Delayed audio setup for reliability

### UI Theme
The app uses a consistent dark theme with:
- Gradient backgrounds
- Blue to purple color scheme
- Rounded corners and shadows
- Modern Material Design 3 components

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## 📄 License

This project is licensed under the MIT License.

## 👨‍💻 Author

NetCalling Development Team

## 🙏 Acknowledgments

- Flutter team for the amazing framework
- Firebase for backend services
- WebRTC community for real-time communication technology
- Metered.ca for TURN server services

---

**Note**: Make sure to configure your Firebase project and TURN servers before deploying to production.
