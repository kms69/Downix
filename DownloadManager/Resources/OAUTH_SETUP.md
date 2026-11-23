# OAuth Credentials Setup

This file is a template for your OAuth credentials. **DO NOT commit actual credentials to git!**

## Setup Instructions

1. Copy this file and remove the `.template` extension:
   ```bash
   cp Secrets.plist.template Secrets.plist
   ```

2. Open `Secrets.plist` and replace the placeholder values with your actual OAuth credentials:
   - Get Dropbox credentials from: https://www.dropbox.com/developers/apps
   - Get Google Drive credentials from: https://console.cloud.google.com/
   - Get OneDrive credentials from: https://portal.azure.com/
   - Get Box credentials from: https://app.box.com/developers/console

3. The `Secrets.plist` file is automatically ignored by git (see `.gitignore`)

## Alternative: Environment Variables

Instead of using a config file, you can set environment variables:

```bash
export DROPBOX_CLIENT_ID="your_dropbox_client_id"
export DROPBOX_CLIENT_SECRET="your_dropbox_client_secret"

export GOOGLE_CLIENT_ID="your_google_client_id"
export GOOGLE_CLIENT_SECRET="your_google_client_secret"

export ONEDRIVE_CLIENT_ID="your_onedrive_client_id"
export ONEDRIVE_CLIENT_SECRET="your_onedrive_client_secret"

export BOX_CLIENT_ID="your_box_client_id"
export BOX_CLIENT_SECRET="your_box_client_secret"
```

## Security Note

⚠️ **NEVER commit files containing real credentials to version control!**

The application will:
1. First check environment variables
2. Then check for `Secrets.plist` file
3. If no credentials are found, cloud integration features will be disabled
