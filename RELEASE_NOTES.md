Post 0.2.7

- Fixed unread messages being hidden because Post reused stale cached labels. When a Gmail query conflicts with the cached Inbox or Unread state, Post fetches current label metadata while keeping the downloaded body.
- Apply explicit Inbox and Unread label constraints to both Gmail lists and counts.
- Exclude Spam and Trash from Primary’s server query, matching its message list.
