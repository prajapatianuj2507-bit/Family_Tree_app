# Family Tree & Event Manager App

A high-performance, offline-first mobile application built with **Flutter** and **Firebase** that enables family networks to build interactive family trees, manage role-based members, schedule events with smart notifications, and sync data seamlessly between local cache and cloud storage.

---

## 🚀 Key Features

### 1. Interactive Family Tree Layout Engine
* **Dynamic Coordinate Grid**: Custom recursive layout algorithm that groups family members into generational tiers, places spouses horizontally, and centers parent nodes above children nodes.
* **Custom Connections Drawing**: Renders clean relational lines (parent drops, spouse joins, sibling collectors) dynamically beneath UI member cards using Flutter's `CustomPainter` canvas.
* **Zoom & Scroll Support**: Interactive panning and zooming to navigate large, multi-generational family trees comfortably.

### 2. Offline-First Synchronization
* **Local Caching**: Continuous database access in offline environments enabled through native Firestore persistence.
* **Offline Auth Bridge Trigger**: Wrote background Cloud Functions (`onMemberCreated`) that listen for database writes and automatically register Firebase Auth accounts when offline-created user profiles sync online.
* **Cached Media Storage**: Uses local directory storage and cache managers to retrieve profile and cover photos instantly when offline.

### 3. Event Scheduler & Conditional Reminders
* **Timezone Corrected**: Formats scheduled dates in the `"Asia/Kolkata"` timezone for accurate cross-regional scheduling.
* **Cron-Scheduled Reminders**: Google Cloud Pub/Sub scheduling that evaluates and delivers push alerts at 48-hour, 24-hour, and 2-hour milestones prior to events.
* **Time-Window Constraints**: Prevents duplicate or redundant historical alerts by matching creation timestamps against scheduling thresholds.

### 4. Interactive Notifications & Deep Linking
* **Seen/Read Status Tracking**: Real-time read status tracking utilizing Firestore array collections to filter badge notifications.
* **Deep Linking**: Clickable push notification payloads that direct the user to specific event detail screens using a global key navigation service.
* **Swipable Media Gallery**: Full-screen swipable viewer with photo zooming and inline video players for viewing uploaded event media files.

---

## 🛠️ Technology Stack

* **Frontend**: Flutter & Dart (Cross-platform iOS/Android code compiler)
* **State Management**: Provider (For modular reactive dependency injections)
* **Backend Services**: Firebase Suite (Authentication, Cloud Firestore, Cloud Storage, Cloud Messaging)
* **Cloud Functions**: Node.js & TypeScript (For background database triggers and cron-scheduled jobs)

---

## 📂 Database Schema Overview

* `/masters`: Administrative portal users.
* `/families`: Individual family groups containing settings, members, and event sub-collections.
* `/members`: User profile details, relationship references (`fatherId`, `motherId`, `spouseId`), and security credentials.
* `/notifications`: Central logs for all dispatch history.
* `/fcm_tokens`: Registered FCM tokens for routing notifications.
* `/password_reset_requests`: Security portal requests routed to administrative masters.

---

## ⚙️ Local Setup Guide

### 1. Prerequisites
* Flutter SDK (3.x or later)
* Node.js & npm (for Firebase CLI and Cloud Functions)
* Firebase CLI installed (`npm install -g firebase-tools`)

### 2. Setting Up the Flutter App
1. Navigate to the frontend directory:
   ```bash
   cd familytree
   ```
2. Fetch package dependencies:
   ```bash
   flutter pub get
   ```
3. Run the application locally (injecting the Google Maps/Places API Key):
   ```bash
   flutter run --dart-define=MAPS_API_KEY=YOUR_PLACES_API_KEY
   ```

### 3. Setting Up Firebase Cloud Functions
1. Navigate to the functions folder:
   ```bash
   cd functions
   ```
2. Install npm modules:
   ```bash
   npm install
   ```
3. Compile TypeScript files:
   ```bash
   npm run build
   ```
4. Deploy rules and functions:
   ```bash
   firebase deploy --only functions,firestore:rules,storage:rules
   ```
