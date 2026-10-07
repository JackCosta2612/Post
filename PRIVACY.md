# Post privacy policy

Last updated: October 7, 2026.

Post is an open-source macOS email client maintained by JackCosta2612. This policy describes the app available at https://github.com/JackCosta2612/Post.

## Gmail access

When you connect Gmail, Post requests permission to read, send, organize, and delete mail using Google's Gmail API. These permissions support the email features you choose to use. Post connects directly to Google. The maintainer does not receive your mailbox contents or sign-in credentials through a Post server.

Each user supplies their own Google Desktop OAuth client. OAuth credentials are stored in macOS Keychain. Google handles sign-in and authorization under its own privacy policy.

## Local data

Post stores downloaded mail, drafts, scheduled messages, preferences, and label-learning examples on your Mac. Attachment and image caches may also be stored locally. The mail cache is not separately encrypted by Post. Protect it with your Mac's account security and disk encryption.

Label learning runs locally. Post does not send email content to an external AI service or use it to train a shared model. Gmail data is used to provide Post's email features, not for advertising or sale to third parties. Post's use of information received from Google APIs follows the Google API Services User Data Policy, including its Limited Use requirements.

## External connections

Post contacts Google to synchronize mail and perform requested email actions. When remote images are enabled or you choose to load them, image servers may receive network information such as your IP address. Opening a link sends you to the linked service, which has its own policies.

The updater contacts GitHub and downloads releases to check for and install updates. Those services receive ordinary connection information. Post does not include an app analytics or advertising service.

## Removal and control

You can disconnect Gmail in Post and revoke its access in your Google account. Disconnecting removes the sign-in token but retains downloaded mail. To remove local app data, quit Post and remove the Post folder in your user's Library/Application Support directory. Downloaded files in your chosen download folder remain until you delete them. Deleting a local cache does not delete mail from Gmail.

## Contact

For questions, open an issue at https://github.com/JackCosta2612/Post/issues. Do not include private mail or credentials in a public issue. The support contact for this Google OAuth project is giacomo.costantinogc2612@gmail.com.
