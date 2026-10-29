# translate-app

Listen to speech through your microphone and read the translation live:
Spanish → English or English → Spanish (pick the direction at the top).

Version 1 is deliberately simple: one page, a Start button, and a running list of
phrases showing the English translation in large text with the original Spanish under it.

## How it works

- **Speech to text:** the browser's built-in speech recognition (Web Speech API),
  set to Spanish. Free, no key.
- **Translation:** Chrome's built-in on-device translator when your browser has it
  (Chrome 138+ on desktop). Otherwise the free [MyMemory](https://mymemory.translated.net/)
  API. No API key needed for either.

Everything is plain HTML, CSS, and JavaScript in `public/`. The web version and the
local version run the exact same files.

### Which browsers work

| Browser | Works? |
| --- | --- |
| Chrome (laptop or Android) | Yes, recommended |
| Edge | Yes |
| Safari (Mac or iPhone/iPad) | Yes |
| Firefox | No, it has no speech recognition |

Note: in Chrome and Edge, speech recognition sends the audio to Google's or Microsoft's
servers to turn it into text, so you need an internet connection.

## Option 1: Web page (laptop and phone)

The page is published with GitHub Pages every time `main` changes.

One-time setup:

1. On GitHub, open this repo's **Settings → Pages**.
2. Under **Build and deployment → Source**, choose **GitHub Actions**.
3. Go to the **Actions** tab, open **Deploy web page**, and click **Run workflow**
   (or just merge a change into `main`).

Your page will be at `https://elspaniard97.github.io/translate-app/`.
Open it on your phone or laptop, press **Start listening**, and allow the microphone.

Tip: on your phone you can use **Add to Home Screen** (Safari share menu, or Chrome's
⋮ menu) so it opens like an app.

## Option 2: Run it locally on your computer

You need [Node.js](https://nodejs.org/) (any recent version). There is nothing to install
from npm.

```bash
git clone https://github.com/ElSpaniard97/translate-app.git
cd translate-app
npm start
```

Then open <http://localhost:3000> in Chrome, Edge, or Safari.

To use a different port: `PORT=8080 npm start` (on Windows PowerShell: `$env:PORT=8080; npm start`).

**Make it feel like a desktop app:** with the page open in Chrome or Edge, click the
install icon in the address bar (or ⋮ menu → **Cast, save, and share → Install page as app**).
It then gets its own window and a shortcut in your Start menu, Dock, or app launcher.
You can do the same from the GitHub Pages link and skip running the local server entirely.

Note: the microphone only works on `https://` pages or on `localhost`. Opening the local
server from another device on your Wi-Fi (like `http://192.168.x.x:3000`) will not get mic
access. Use the GitHub Pages link on your phone instead.

## Option 3: Native Mac app

`mac/` holds a real macOS app (SwiftUI) that does the same job without a browser:

- **Speech to text:** Apple's speech recognizer. It runs on your Mac when Spanish
  on-device recognition is available.
- **Translation:** Apple's on-device Translation framework. Free, private, no daily limit.
  The first time, macOS asks to download the Spanish language pack.

Requirements: macOS 15 (Sequoia) or newer, and the Swift compiler. If `swiftc --version`
fails in Terminal, run `xcode-select --install` first. You don't need the full Xcode app.

```bash
cd translate-app/mac
./build.sh --install
```

That builds **Translator.app** and copies it to your `Applications` folder in your home folder
(`~/Applications`). Open it from Spotlight or Launchpad and drag it to your Dock if you like.
The first time you press **Start listening**, allow the microphone and speech recognition.
You can also press the space bar to start and stop.

If macOS says the app "can't be opened" because it is from an unidentified developer,
right-click it, choose **Open**, then **Open** again. You only need to do this once.

To update the app later with the newest code:

```bash
cd ~/Documents/translate-app && git checkout main && git pull && ./mac/build.sh --install
```

## Limits to know about

- MyMemory's free tier allows about 5,000 characters per day per network. That is plenty
  for testing; if you hit it, translations show an error until the next day. Using Chrome
  on desktop avoids this because it translates on your device.
- Speech recognition works best on clear speech close to the microphone. Background noise
  and several people talking at once will reduce accuracy.

## Project layout

```
public/          The app (shared by the web page and the local version)
  index.html
  app.js         Speech recognition + translation
  style.css
  sw.js, manifest.webmanifest, icon.svg   Lets the page be installed as an app
server.js        Tiny local web server (no dependencies)
mac/             Native macOS app (Swift), built with mac/build.sh
.github/workflows/pages.yml   Publishes public/ to GitHub Pages
```
