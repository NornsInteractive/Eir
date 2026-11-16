# Eir Privacy Policy

**Effective Date**: November 16, 2026  
**Last Updated**: November 16, 2026  
**Developer / Operating Entity**: Norns Interactive  
**Application Name**: Eir (Synchronized Cinema & Live Screen Share)  
**Package Name / Application ID**: `com.norns.eir`  
**Official Website**: [https://eir.norns.cc.cd](https://eir.norns.cc.cd)  
**Contact Email**: support@norns.cc.cd  

---

## Welcome to Eir

Norns Interactive ("we", "us", or "our") is committed to protecting and respecting your personal privacy. Eir is a cross-platform client application dedicated to real-time synchronized co-watching and 60 FPS live screen sharing.

Our product architecture is built on the fundamental pillars of **"Data Minimization", "Zero Cloud Storage of Media", and "End-to-End Peer-to-Peer (P2P) Transmission"**. This Privacy Policy explains transparently how we handle information, the device permissions we request, why they are needed, and how you retain full control over your privacy.

Please read this policy carefully before using Eir. By downloading, accessing, or using Eir, you acknowledge that you have read, understood, and agreed to the practices described in this Privacy Policy.

---

## 1. Information We Collect and Process

Eir is designed from the ground up as an account-free, decentralized tool. **We do not require you to create an account, register an email address, link a phone number, or provide payment details.**

### 1.1 Local Media and Video Files
- **How it works**: When you choose to play a local video or audio file in a co-watching room, Eir reads the file stream selected by you via the standard operating system file picker.
- **Zero Cloud Upload**: Your chosen media files **are NEVER uploaded to any central cloud server, storage bucket, or database**. When watching synchronously with a friend, video and audio streams are transmitted directly between your device and your peer via WebRTC / Tailcat encrypted peer-to-peer connections.

### 1.2 Live Screen Sharing Streams
- **How it works**: When you actively initiate screen sharing as a broadcaster, the operating system captures your selected screen, application window, or system audio. The stream is encoded locally and delivered in real time to room members via direct WebRTC P2P channels.
- **No Video Recording or Archiving**: We do not record, intercept, analyze, store, or snapshot your screen content on any server. Temporary rendering buffers are destroyed immediately upon stopping the broadcast.

### 1.3 Two-Way Voice Intercom
- **How it works**: When you choose to unmute your microphone in a room or live broadcast session, audio is captured and streamed peer-to-peer using standard DTLS-SRTP encryption.
- **Zero Audio Retention**: We do not record, transcribe, eavesdrop, or retain any voice communications.

### 1.4 Signaling and Ephemeral Session Data
- **Room Codes & Session Tokens**: To establish a direct connection between peers, our edge signaling service (`wss://eir.norns.cc.cd/ws`) temporarily routes ephemeral handshake signals: 6-digit numeric room codes, random session UUIDs, WebRTC Session Description Protocol (SDP) offers/answers, and ICE network candidates. These signaling states exist only in volatile server memory and are **immediately purged** when the room is disbanded or members disconnect.
- **In-Room Chat & Danmaku**: Text messages and floating comments are exchanged directly over the WebRTC DataChannel or ephemeral signaling connection. They are not stored on any server and are cleared when you leave the room.
- **Local Settings & History**: Eir stores your preferences (theme, language, recent room history) solely in your device's private sandboxed local storage. You can wipe this data at any time via in-app Settings.

### 1.5 What We NEVER Collect
- ❌ **No Advertising Trackers**: No third-party ad networks (e.g., AdMob, Unity, AppLovin).
- ❌ **No Behavioral Analytics**: No profiling, user tracking, or telemetry monitoring SDKs.
- ❌ **No Hardware Identifiers**: We never read IMEI, IMSI, MAC addresses, or serial numbers.
- ❌ **No Location Data**: We do not request or track GPS or fine network location.

---

## 2. Device Permissions and Usage

To enable synchronized playback and screen sharing capabilities, Eir may request specific system permissions. We only request permissions when you invoke corresponding features, and you may revoke them at any time in your device's operating system settings.

| Permission / Identifier | Platform | Business Purpose & Context | Is Required? |
| :--- | :--- | :--- | :--- |
| **Microphone**<br>`RECORD_AUDIO` | Android / iOS / Desktop | Used solely when you actively unmute to speak in co-watching rooms or screen share sessions. Never accessed when muted. | No (Optional) |
| **Screen Capture / Media Projection**<br>`MEDIA_PROJECTION` | Android / Desktop / Web | Requested via system dialog only when you initiate screen sharing to stream your screen to peers. | No (Optional) |
| **Media / Video Access**<br>`READ_MEDIA_VIDEO` / `READ_EXTERNAL_STORAGE` | Android / Mobile | Invoked solely when you open the file picker to choose a local video file from your device storage to watch with friends. | No (Optional) |
| **Internet & Network State**<br>`INTERNET` / `ACCESS_NETWORK_STATE` | All Platforms | Required to connect to edge signaling, negotiate WebRTC connections, and perform peer-to-peer streaming. | Yes (Core Functionality) |
| **Foreground Service (Projection)**<br>`FOREGROUND_SERVICE_MEDIA_PROJECTION` | Android | Ensures continuous, uninterrupted screen streaming when switching to games or other apps on Android, showing a persistent status bar notification. | No (Only during broadcast) |
| **System Alert Window (Overlay)**<br>`SYSTEM_ALERT_WINDOW` | Android | Displays an optional floating chat capsule while broadcasting full-screen games, enabling the broadcaster to view incoming peer reactions without exiting the game. | No (Optional in Settings) |
| **Notifications**<br>`POST_NOTIFICATIONS` | Android 13+ | Displays active screen sharing status in the notification drawer with a quick "Stop Sharing" action button. | No (Optional) |

---

## 3. Third-Party Services and Data Sharing

1. **Zero Third-Party Commercial SDKs**: Eir contains no commercial tracking, advertising, analytics, or social login SDKs.
2. **NAT Traversal Relays (STUN / TURN Infrastructure)**:
   - When two devices cannot establish a direct peer-to-peer route due to strict symmetric NATs or corporate firewalls, encrypted media packets may transit through our dedicated TURN relay servers (`ip.norns.cc.cd`).
   - All relay traffic is encrypted end-to-end with WebRTC DTLS-SRTP. The relay server acts purely as a blind packet router; **it cannot decrypt, inspect, or retain the content of your media stream**.
3. **No Sale of Data**: We do not sell, rent, monetize, or disclose your personal data to any third parties for any purpose.

---

## 4. Security and Encryption Standards

1. **Transport Layer Security**: All signaling interactions are strictly conducted over TLS 1.3 / WSS secure encrypted websockets.
2. **End-to-End Media Encryption**: WebRTC audio, video, and data channels use industry-standard DTLS and SRTP with ephemeral keys negotiated directly between participating peers.
3. **Encrypted Configuration Payloads**: Remote server addresses and relay credentials are delivered using AES-256-GCM symmetric encryption to prevent tampering.
4. **Sandboxed Local Storage**: Configuration and cache files are stored exclusively within OS-enforced private sandbox containers.

---

## 5. Your Rights and Data Control

In accordance with international privacy regulations (including GDPR, CCPA, and PIPL):

- **No Account Dependency**: You can use Eir completely anonymously without registration.
- **Revoke Permissions**: You can disable any granted device permission at any time through your operating system settings.
- **One-Click Local Cache Purge**: Inside Eir's **Settings -> Storage & Cache**, you can immediately delete all room history, saved tokens, and cached configurations.
- **Data Erasure**: Uninstalling the application completely deletes all application sandbox data stored on your device.

---

## 6. Children's Privacy

Eir is not directed toward children under 13 years of age (or under 16/14 where specified by local law). We do not knowingly collect personal information from children. If you believe a child has provided us with personal information, please contact us immediately, and we will take prompt steps to remove such information.

---

## 7. Changes to This Privacy Policy

We may update this Privacy Policy periodically to reflect technological advancements, new features, or evolving legal obligations. Any updates will be published on this page with a revised "Last Updated" date. For significant updates, we will notify you through application notices or our website.

---

## 8. Contact Information

If you have any questions, feedback, or concerns regarding this Privacy Policy or our security practices, please reach out to us:

- **Organization**: Norns Interactive  
- **Official Website**: [https://norns.cc.cd](https://norns.cc.cd)  
- **Open Source Repository**: [https://github.com/NornsInteractive/Eir](https://github.com/NornsInteractive/Eir)  
- **Email**: [support@norns.cc.cd](mailto:support@norns.cc.cd)  
- **Response Commitment**: We endeavor to review and respond to inquiries within 15 business days.
