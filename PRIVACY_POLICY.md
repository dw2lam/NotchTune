# Privacy Policy

**Last updated: 2026-11-05**

NotchTune is a macOS app that runs on your Mac. It has no account, no server of
its own, and no analytics, telemetry, crash reporting or tracking SDKs. Nothing
about you or your work is sent to its developer.

## What's stored on your Mac

These stay on your Mac until you delete them. Most live in
`~/Library/Application Support/NotchTune`:

- **Myspace**: your thoughts, dictated text and reminders, plus copies of any
  files and images you add.
- **Music** (`Music/library.json`): the last Apple Music library it read, the
  Spotify links you pinned, and a history of the Spotify tracks it saw playing.
- **Session records**: recent agent sessions, including titles, summaries,
  working directories and the prompts you gave them, so sessions survive a
  restart. Records older than 24 hours are dropped the next time the file is
  saved.
- **Settings**, in the app's macOS preferences.
- **The hooks helper** and a local socket, which is how your agents reach the
  app. Usage figures are cached in `/tmp`.

NotchTune also reads agent transcripts and configuration on your Mac (for example
`~/.claude` and `~/.codex`) to find sessions, and adds hooks to those agents'
configuration files. You can remove the hooks in Settings → Setup.

## What goes over the network

NotchTune doesn't listen on the network; agents talk to it over a local socket.
It makes these outgoing connections:

- **GitHub**, to check for updates about once an hour and to download them. GitHub
  sees your IP address and NotchTune version, as with any download.
- **Spotify**, when you paste a Spotify link: the link is sent to Spotify's
  `open.spotify.com/oembed` service to look up its title and artwork.
- **Artwork hosts**: album art for what's playing and for your Music tab is
  downloaded from the addresses Spotify and the Music app supply.
- **Images in agent messages**: if a finished agent's message contains an image
  link, the image is fetched from wherever it's hosted.

Links you click, like a meeting's Join button, open in your own apps.

## Permissions

Each of these is yours to grant or refuse in System Settings:

- **Camera**: used only while the Mirror tab is open. Nothing is recorded, stored
  or sent anywhere.
- **Calendars**: off until you turn on meeting heads-ups, then read on your Mac
  only.
- **Automation**: to jump back to your terminals and editors, to send them
  keystrokes through System Events, and to read and control Spotify and Music.
- **Accessibility**: to find terminal windows and jump back to a session.
- **Notifications**: for your Myspace reminders.

## Contact

Questions about this policy are welcome at
https://github.com/dw2lam/NotchTune/issues.
