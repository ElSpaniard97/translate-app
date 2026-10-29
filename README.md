# translate-app

Listen to Spanish speech through your microphone and read it in English, live.

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
.github/workflows/pages.yml   Publishes public/ to GitHub Pages
```
