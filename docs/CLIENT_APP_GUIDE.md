<p align="center">
  <img src="../assets/branding/blind_way_logo.png" width="140" alt="Blind Way logo">
</p>

# Blind Way — Client App Guide

This guide explains the complete app journey in simple language. It covers what the blind user and guardian see, what every menu does, and what happens during an emergency.

> **Safety note:** Blind Way is an assistance tool. It does not replace a white cane, guide dog, trained mobility support, or local emergency services. Camera, AI, GPS, internet, Bluetooth, and notifications can sometimes be unavailable or inaccurate.

## 1. The basic idea

Blind Way connects four parts:

1. An **ESP32-CAM** sees the area in front of the blind user.
2. The **Blind Way Android app** receives a camera image and asks the AI what is ahead.
3. The app speaks short guidance through **Bluetooth earbuds** or the phone speaker.
4. If help is requested, linked **guardians** receive an emergency notification, live location, the last scene description, and the last camera view.

### Example used in this guide

- **Ravi** is the blind user.
- **Anjali** is Ravi's guardian.
- Ravi wears the ESP32-CAM and Bluetooth earbuds.
- Both Ravi and Anjali have Blind Way installed on their Android phones.

## 2. First-time setup checklist

Before using the app:

- Install Blind Way on both phones.
- Turn on internet access on both phones.
- Pair Ravi's earbuds in Android Bluetooth settings.
- Power on the ESP32-CAM.
- Keep Ravi's phone and the camera on the same Wi-Fi network.
- Allow notifications on both phones.
- Allow microphone access on Ravi's phone.
- Allow location access when Ravi sends an emergency.

For reliable wake-word detection, remove battery restrictions for Blind Way on Ravi's phone. Android may stop background listening if the app is force-stopped, the phone restarts, microphone permission is removed, or the manufacturer applies aggressive battery saving.

## 3. Login screen

The first screen asks: **How will you use the app?**

### Option A — I need vision assistance

Ravi selects this role. It gives him access to:

- ESP32-CAM connection;
- spoken vision assistance;
- emergency wake word and emergency button;
- trusted-contact invitations;
- active emergency status.

### Option B — I am a trusted contact

Anjali selects this role. It gives her access to:

- emergency notifications;
- Ravi's live emergency map;
- the last scene description and camera view;
- alert acknowledgement and resolution;
- trusted-user linking.

### Login method 1 — Continue securely

1. Select the correct role.
2. Tap **Continue securely**.
3. The secure Auth0 login page opens.
4. Complete the enabled login method, such as Google or email.
5. After successful authentication, Blind Way returns to the app.

### Login method 2 — Sign in with phone OTP

1. Select the correct role.
2. Tap **Sign in with phone OTP**.
3. Enter the full phone number with country code.
   - Example: `+919876543210`
4. Tap **Send code**.
5. Enter the six-digit SMS code.
6. Tap **Verify**.

Use **Change number** if the wrong phone number was entered. Use **Cancel** to close the OTP window.

## 4. Blind-user app menus

Ravi sees three menus at the bottom:

1. **Assist**
2. **People**
3. **Settings**

## 5. Assist menu

The Assist menu is Ravi's main screen.

### 5.1 Camera status

The first card says either **Camera not connected** or **Camera connected**.

Tap **Connect** to open the camera window. If a camera was connected earlier, tap **Change** to use a different address or camera.

#### Method A — Connect an already configured camera

1. Confirm the phone and ESP32-CAM are on the same Wi-Fi.
2. Tap **Find automatically**.
3. Blind Way searches for `blindway-camera.local` and fills the camera address.
4. Enter the camera API token printed in Serial Monitor.
5. Tap **Connect**.

If automatic discovery does not work, enter the IP address manually.

Example:

- Camera address: `192.168.1.8`
- Camera token: the 16-character value printed as **Camera API token**

Blind Way automatically adds `http://` if it is omitted. It tests the `/capture` endpoint and saves the connection only after receiving a valid JPEG image.

#### Method B — Set up camera Wi-Fi for the first time

1. Connect the ESP32-CAM to power and open Serial Monitor.
2. In the camera window, tap **Set up Wi-Fi**.
3. Enter the values printed by the camera:
   - **PROV_BW device name**, for example `PROV_BW_A1B2C3`;
   - **Device code**, shown as **Proof of possession**;
   - **Wi-Fi name**;
   - **Wi-Fi password**.
4. Tap **Provision**.
5. Wait for Serial Monitor to print **Camera Ready** and its IP address.
6. Return to the camera connection window, tap **Find automatically**, enter the camera API token, and tap **Connect**.

The device code and camera token are private. They should not be shared publicly.

### 5.2 Bluetooth audio status

The second card says either:

- **Bluetooth audio connected** — guidance should play through the paired earbuds; or
- **Phone audio active** — guidance will use the phone speaker.

Tap **Bluetooth** to open Android Bluetooth settings. Pair or select the earbuds, return to Blind Way, and check the status again.

The phone or currently routed earbud microphone is used for emergency listening, depending on the Bluetooth device and Android audio routing.

### 5.3 Voice emergency status

This card shows whether emergency listening is ready:

- **Offline wake word ready** — the on-device wake-word detector is active.
- **Voice emergency ready** — Android short-command recognition is active during assistance.
- **Voice emergency starts with assistance** — tap Start assistance to enable the fallback listener.
- **Voice emergency unavailable** — check microphone permission and app configuration.

With the custom offline model, Ravi says:

> **Hey Blind Way**

If the offline model is not configured, the fallback listens during assistance for exact short commands such as:

- **Help**
- **Help me**
- **Emergency**
- **SOS**

The app also includes configured Hindi and Tamil emergency phrases. Offline wake-word detection does not upload ordinary conversation.

### 5.4 Start assistance

1. Make sure the camera card says **Camera connected**.
2. Make sure the preferred earbuds are connected.
3. Tap **Start assistance**.
4. Blind Way captures camera images, analyses the scene, and speaks important guidance.

Example guidance:

> “Move slightly left. A chair is two metres ahead.”

The **Latest guidance** card displays:

- the latest spoken instruction;
- risk level, such as CLEAR, CAUTION, or DANGER;
- AI confidence percentage.

Higher-risk changes are processed and repeated more quickly. Clear scenes are not spoken repeatedly unless the guidance changes.

Tap **Stop assistance** when continuous scene guidance is no longer needed. If the offline wake word is configured, emergency listening can remain active after vision assistance stops.

### 5.5 Emergency button

The large red button says **Hold for Emergency SOS**.

1. Press and hold it for two seconds.
2. A five-second countdown appears.
3. Tap **Cancel emergency** during the countdown if it was accidental.
4. If it is not cancelled, the emergency is sent automatically.

This hold-and-countdown design helps prevent accidental alerts.

### 5.6 Spoken emergency

1. Ravi says the configured wake phrase or fallback help command.
2. Blind Way stops listening temporarily and announces a three-second emergency countdown.
3. Ravi can tap **Cancel emergency** if the trigger was accidental.
4. Otherwise, the alert is sent to every linked guardian.

### 5.7 Active emergency

After sending, Ravi sees **Emergency active**. The app:

- tells linked guardians that help is needed;
- shares current location and GPS accuracy;
- updates location approximately every 15 seconds;
- shares whether the voice or button triggered the emergency;
- includes the latest scene description;
- securely includes the last available camera view.

When Ravi is safe, he taps **I am safe — cancel alert**. This closes the emergency and stops location sharing.

## 6. People menu — blind user

Ravi uses this menu to add guardians.

1. Tap **Create secure invite**.
2. A one-time code appears.
3. Give the code privately to Anjali.
4. Anjali must use it within 10 minutes.

Example:

> Ravi calls Anjali and reads the displayed code `8F31A5C902`.

After Anjali redeems it, she appears under **Your trusted contacts** as a verified emergency contact. A blind user can link up to five guardians.

## 7. Settings menu — blind user

### Spoken guidance language

Choose **English**, **Hindi**, or **Tamil**. This controls scene guidance language and the Android speech-recognition fallback locale.

### Bluetooth audio settings

Opens Android Bluetooth settings to pair, connect, disconnect, or change the audio device.

### Privacy information

Explains that routine camera frames are analysed transiently. The last frame is stored only during an emergency, is available only to authorised linked guardians, and is deleted when the alert closes or by the 30-day cleanup rule. Location is shared only while an emergency is active.

### Sign out

Stops active assistance and signs the user out securely. An active emergency should be cancelled or resolved before intentionally signing out.

## 8. Guardian app menus

Anjali sees:

1. **Alerts**
2. **People**
3. **Settings**

## 9. People menu — guardian

This is where Anjali links her account to Ravi.

1. Ask Ravi to create a secure invite from his People menu.
2. Enter the invite code in **Invite code**.
3. Tap **Link trusted user**.
4. Ravi appears under **People who trust you**.

The code is single-use and expires after 10 minutes. If it expires, Ravi creates a new one.

## 10. Alerts menu — guardian

### No active emergency

The screen says **Monitoring active**. Blind Way is registered for high-priority notifications from linked users.

### When an emergency arrives

Anjali receives a notification such as:

> **Blind Way emergency — Ravi needs help**

Tapping the notification opens Blind Way. The Alerts menu can show:

- Ravi's name;
- alert start time;
- whether it was triggered by voice or the button;
- live map position;
- GPS accuracy and latest update time;
- **Open live location**, which opens the coordinates in Google Maps;
- the last AI scene description and guidance;
- risk level and confidence;
- the protected last camera view, which can be zoomed.

Only linked guardians and the blind user can retrieve the emergency snapshot.

### Acknowledge alert

Tap **Acknowledge alert** when Anjali has seen the emergency and is responding. Acknowledgement does not close the emergency; Ravi's location can continue updating.

Example:

> Anjali receives Ravi's alert, checks his map position, calls him, and taps Acknowledge alert while travelling to him.

### Mark resolved

Tap **Mark resolved** only when the incident has ended. Resolution closes the alert, stops active emergency sharing, and deletes the stored emergency snapshot.

## 11. Settings menu — guardian

The guardian Settings menu shows:

- account name and trusted-contact role;
- spoken app language selection;
- Bluetooth settings if the guardian wants app audio through another device;
- the privacy explanation;
- **Sign out**.

## 12. Complete example from start to finish

1. Ravi signs in as **I need vision assistance**.
2. Anjali signs in as **I am a trusted contact**.
3. Ravi opens People and creates an invite.
4. Anjali enters the code and links to Ravi.
5. Ravi connects the ESP32-CAM at `192.168.1.8` using its camera token.
6. Ravi pairs his earbuds and taps **Start assistance**.
7. Blind Way says, “Caution. Steps going down are ahead.”
8. Ravi becomes disoriented and says, “Hey Blind Way.”
9. The app announces a three-second countdown and sends the alert.
10. Anjali receives a high-priority notification.
11. She opens the app and sees Ravi's live location, the description of the steps, and the last camera view.
12. She taps **Acknowledge alert**, calls Ravi, and uses **Open live location** for navigation.
13. After Ravi is safe, Anjali taps **Mark resolved**. Alternatively, Ravi can tap **I am safe — cancel alert**.
14. Live emergency sharing stops and the stored emergency image is deleted.

## 13. Common messages and what to do

| Message | Meaning | Action |
|---|---|---|
| Camera not connected | The app has no working camera address | Connect the camera and verify both devices use the same Wi-Fi |
| No camera found | Automatic mDNS discovery failed | Enter the Serial Monitor IP manually |
| Camera connection error | The address/token is wrong or `/capture` did not return a JPEG | Recheck the IP, camera token, power, and Wi-Fi |
| Phone audio active | No Bluetooth audio output was detected | Pair earbuds or continue with the speaker |
| Voice emergency unavailable | Microphone access or wake-word setup is unavailable | Grant microphone permission and reopen the app |
| No trusted connections yet | No guardian relationship exists | Create and redeem a secure invite |
| Snapshot could not be loaded | Network access failed or the image is no longer authorised/available | Check connectivity and alert status |
| Vision unavailable | The camera, network, or cloud analysis failed | Stop safely, check connectivity, and retry |

## 14. Recommended client demonstration

For a clear demonstration, use two Android phones and follow this order:

1. Show both login roles.
2. Link the two accounts with an invite code.
3. Connect the ESP32-CAM and Bluetooth earbuds.
4. Start assistance and point the camera at a chair or doorway.
5. Show the spoken guidance and confidence card.
6. Trigger SOS, then cancel once to demonstrate accident protection.
7. Trigger SOS again and allow it to send.
8. Show the guardian notification, map, last scene, and camera snapshot.
9. Acknowledge and then resolve the alert.
10. End by showing the privacy card and explaining data deletion.

Always perform demonstrations in a controlled environment with a sighted assistant present.
