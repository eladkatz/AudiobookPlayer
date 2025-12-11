# Google Drive API Setup Instructions

## Step 1: Create Google Cloud Project

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Click "Select a project" → "New Project"
3. Name it "AudioBook Player" (or your preferred name)
4. Click "Create"

## Step 2: Enable Google Drive API

1. In your project, go to "APIs & Services" → "Library"
2. Search for "Google Drive API"
3. Click on it and press "Enable"

## Step 3: Create OAuth 2.0 Credentials

1. Go to "APIs & Services" → "Credentials"
2. Click "Create Credentials" → "OAuth client ID"
3. If prompted, configure the OAuth consent screen:
   - User Type: External (unless you have a Google Workspace)
   - App name: "AudioBook Player"
   - User support email: Your email
   - Developer contact: Your email
   - Click "Save and Continue"
   - Scopes: Add "https://www.googleapis.com/auth/drive.readonly"
   - Click "Save and Continue"
   - **Test users: Add your Google account email (eladka999@gmail.com)**
     - This is CRITICAL - without this, you'll get "Access blocked" error
     - Click "Add Users" and enter your email
   - Click "Save and Continue"
4. Back to creating OAuth client ID:
   - Application type: **iOS**
   - Name: "AudioBook Player iOS"
   - Bundle ID: `com.eladkatz.audiobookplayer` (must match your app's bundle ID)
   - Click "Create"
5. **IMPORTANT**: Copy the **Client ID** - you'll need this in the code

## Step 4: Add to Your App

The Client ID will be added to the code in `GoogleDriveManager.swift` as a constant.

## Notes

- The OAuth consent screen will be in "Testing" mode initially
- You can publish it later if you want to distribute the app
- **IMPORTANT**: For testing, only the test users you add can sign in
  - If you see "Access blocked" error, it means your email is not in the test users list
  - Go back to OAuth consent screen → Test users → Add your email
- The `drive.readonly` scope allows reading files but not modifying them

## Troubleshooting

### "Access blocked" Error (403: access_denied)
**Solution**: Your email is not added as a test user. 
1. Go to Google Cloud Console → APIs & Services → OAuth consent screen
2. Scroll to "Test users" section
3. Click "Add Users"
4. Enter your Google account email (the one you're trying to sign in with)
5. Click "Add"
6. Try signing in again in the app

### Main Thread Checker Warnings
These should be fixed in the code, but if you still see them, they're usually harmless warnings from the simulator.

