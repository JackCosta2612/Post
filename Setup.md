# Connect Gmail to Post

Post supports one Gmail or Google Workspace mailbox at a time. You need your own Google Cloud project and Desktop OAuth client. The repository contains no shared Google credentials.

## 1. Create a project

Open [Google Cloud Console](https://console.cloud.google.com/). Use the project selector, choose **New project**, name it Post, and create it. Select the new project. Open **APIs & Services → Library**, find **Gmail API**, and click **Enable**.

## 2. Configure Google Auth Platform

Open **Google Auth Platform**. If it shows Get started, complete it:

- Branding: app name Post and your support email.
- Audience: External for a personal Gmail account. A Workspace organization may offer Internal for its own users.
- Contact information: your email.

In **Audience**, keep Testing for initial setup and add your Gmail address under **Test users**.

In **Data Access**, add the scope `https://www.googleapis.com/auth/gmail.modify`. It lets Post read mail, manage labels, Trash mail, manage drafts, and send. It does not grant Drive access. If the scope picker does not list it, use its exact URL when adding a scope manually. Save.

## 3. Create the Desktop client

Open **Clients → Create client**. Set application type to **Desktop app**, name it Post on my Mac, and create it. Download the JSON. No manually configured web redirect URI is needed. Post uses a temporary localhost callback and PKCE, following [Google's installed-app OAuth flow](https://developers.google.com/identity/protocols/oauth2/native-app).

Keep the JSON local and do not commit it. Each friend should create their own project and client rather than use your file.

## 4. Import and sign in

Open Post, then **Settings → Account**:

1. Choose **Import Google client…**, select the downloaded Desktop JSON.
2. Choose **Sign in with Google**.
3. Sign in to the Gmail account you added as a test user and approve the Gmail scope in your browser.
4. Return to Post. Your account address and Connected to Gmail should appear. Mail will load in pages of 50.

Google can show an unverified-app warning for your own unverified project. Check the project, app, and requested scope before continuing. Workspace policy can block unverified apps; an administrator may need to approve it.

## 5. Daily use

Google's Testing status expires authorizations using Gmail scopes after seven days. For a project used only by you or a small number of known users, review Google's [personal-use verification exemption](https://support.google.com/cloud/answer/13464323) and [publishing status rules](https://support.google.com/cloud/answer/10311615). Set **Audience → Publishing status → In production** when appropriate. Production status does not itself verify the app or remove the warning. A broadly distributed shared Google OAuth client may require restricted-scope verification and additional assessment; Post's documented setup uses individual personal projects.

## Sync and storage

Post checks for changes every 60 seconds while it is open. Switching folders and searching fetch the requested results. Manual refresh shows the loading strip; background sync is quiet. Cached bodies are reused and requests are paced. Gmail quota errors cause a cooldown instead of repeated requests.

The Google client and tokens are in macOS Keychain. Cached mail, preferences, and local drafts are in `~/Library/Application Support/Post/mail-cache.json`. Embedded image bytes are cached with mail after download. External images are blocked by default and can be enabled per message or in settings. Attachments download on demand and can be saved to a location you choose.

## Troubleshooting

| Symptom | Action |
| --- | --- |
| Access blocked in Testing | Add the exact signed-in Gmail address as a test user. |
| Invalid client or redirect mismatch | Import a Desktop app JSON, not a Web client JSON. |
| Sign-in expires weekly | Review Testing versus Production status above. |
| Repeated Keychain prompts after edits | Use the stable signing setup in [Build instructions](docs/build.md). |
| Quota warning | Wait for the cooldown; do not repeatedly press Refresh. |
| Images missing | Embedded images download when a conversation opens. External images require Load images unless automatic loading is enabled. |
| Mail has the wrong colors in Dark mode | Use the message's menu → Use original email colors. |

Disconnect removes Post's saved sign-in token but retains the local cache. To revoke server access too, remove Post from your Google account's connected apps.
