# Google Drive Integration Setup Instructions

## ✅ Code Implementation Complete

All the code for Google Drive integration has been implemented. Now you need to:

## Step 1: Add Google Sign-In SDK

1. Open your project in Xcode
2. Go to **File → Add Package Dependencies...**
3. Enter this URL: `https://github.com/google/GoogleSignIn-iOS`
4. Click "Add Package"
5. Select "GoogleSignIn" (not GoogleSignInSwift)
6. Click "Add Package"
7. Make sure it's added to your "AudioBookPlayer" target

## Step 2: Get Google Cloud Credentials

Follow the instructions in `GOOGLE_DRIVE_SETUP.md` to:
- Create a Google Cloud project
- Enable Google Drive API
- Create OAuth 2.0 credentials (iOS Client ID)

## Step 3: Configure the App

1. **Update Client ID in Code:**
   - Open `AudioBookPlayer/Managers/GoogleDriveManager.swift`
   - Find line: `private let clientID = "YOUR_CLIENT_ID_HERE"`
   - Replace with your actual Client ID from Google Cloud Console

2. **Update URL Scheme in Info.plist:**
   - Open `AudioBookPlayer/Info.plist`
   - Find the `CFBundleURLSchemes` array
   - Replace `YOUR_CLIENT_ID_REVERSED` with your reversed Client ID
   - Example: If your Client ID is `123456789-abc.apps.googleusercontent.com`
   - The reversed format is: `com.googleusercontent.apps.123456789-abc`
   - (Take the part before `.apps.googleusercontent.com` and reverse it)

## Step 4: Uncomment Code

After adding the SDK, you need to uncomment the Google Sign-In code:

1. In `GoogleDriveManager.swift`:
   - Uncomment `import GoogleSignIn` at the top
   - Uncomment all the `// TODO: Uncomment after adding Google Sign-In SDK` sections

2. In `GoogleDrivePickerView.swift`:
   - Uncomment `import GoogleSignIn` at the top
   - Uncomment all the implementation code in the methods

## Step 5: Test

1. Build and run the app
2. Go to Library → Import
3. Tap "Import from Google Drive"
4. Sign in with your Google account
5. Browse and select a folder containing an M4B file
6. The app will download all related files (M4B, CUE, JPEG, NFO)

## File Structure Expected

The app expects folders with this structure:
```
Book Folder/
  ├── BookName.m4b          (required)
  ├── BookName.cue          (optional)
  ├── BookName.jpg          (optional - cover art)
  └── BookName.nfo          (optional - metadata)
```

Or alternative naming:
- `cover.jpg` or `folder.jpg` for cover images
- `BookName.m4b.cue` for CUE files

## Troubleshooting

- **Build errors about GoogleSignIn**: Make sure you added the package dependency
- **Authentication fails**: Check that your Client ID is correct and URL scheme matches
- **Can't see folders**: Make sure you added your Google account as a test user in OAuth consent screen
- **Download fails**: Check network connection and that files exist in the folder

