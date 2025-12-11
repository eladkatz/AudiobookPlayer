# Quick Start Guide

## Running the App in Xcode

### Step 1: Open the Project
1. Open Xcode
2. File → Open → Navigate to `AudioBookPlayer.xcodeproj`
3. Double-click the `.xcodeproj` file

### Step 2: Configure Signing
1. In Xcode, click on the **AudioBookPlayer** project (blue icon) in the left navigator
2. Select the **AudioBookPlayer** target
3. Go to the **Signing & Capabilities** tab
4. Check ✅ **"Automatically manage signing"**
5. Select your **Team** from the dropdown:
   - If you have an Apple Developer account, select it
   - If not, select **"Personal Team"** (this works for simulator and limited device testing)

### Step 3: Select a Destination
- In the toolbar at the top, click the device selector (next to the play button)
- Choose an **iOS Simulator** (e.g., "iPhone 15 Pro" or "iPhone 15")
- Or connect your iPhone and select it

### Step 4: Build and Run
- Press **⌘ + R** (Command + R) or click the **▶️ Play** button
- Xcode will build and launch the app

## Troubleshooting

### "No signing certificate" error
- Make sure you're signed into Xcode with your Apple ID
- Xcode → Settings → Accounts → Add your Apple ID
- Then go back to Signing & Capabilities and select your team

### Build errors
- Make sure you're using Xcode 15.0 or later (for iOS 17.0 deployment target)
- Clean build folder: Product → Clean Build Folder (⇧⌘K)
- Try building again

### Simulator not launching
- Make sure you have at least one iOS Simulator installed
- Xcode → Settings → Platforms → Download iOS Simulator if needed

## Testing the App

Since the import functionality is stubbed, you can test the UI by:
1. The Library will be empty initially
2. Tap the **+** button to see the import screen (stub)
3. Navigate to Settings to see the playback controls
4. The Player screen will show "No Book Selected" until you import a book

## Next Steps

To test with actual M4B files, you'll need to:
1. Implement the file import functionality
2. Add M4B files to the app's Documents directory
3. Or implement Google Drive integration


