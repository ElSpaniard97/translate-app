// Listens for speech with the browser's built-in speech recognition, then shows
// each finished phrase with its translation (Spanish → English or English → Spanish).

const SpeechRecognition = window.SpeechRecognition || window.webkitSpeechRecognition;

const toggleBtn = document.getElementById('toggle');
const clearBtn = document.getElementById('clear');
const directionSelect = document.getElementById('direction');
const dialectSelect = document.getElementById('dialect');
const statusEl = document.getElementById('status');
const linesEl = document.getElementById('lines');
const interimEl = document.getElementById('interim');

let recognition = null;
let listening = false;
const builtInTranslators = {};

// The languages for the current direction, e.g. { from: 'es', to: 'en' }.
function languages() {
  const [from, to] = directionSelect.value.split('-');
  return { from, to };
}

function setStatus(text) {
  statusEl.textContent = text;
}

if (!SpeechRecognition) {
  toggleBtn.disabled = true;
  setStatus('This browser does not support speech recognition. Use Chrome, Edge, or Safari.');
}

// Chrome 138+ ships an on-device translator. Use it when available, since it
// is free, private, and has no rate limit. Otherwise fall back to MyMemory.
async function prepareBuiltInTranslator({ from, to }) {
  const key = from + '-' + to;
  if (key in builtInTranslators || !('Translator' in self)) return;
  builtInTranslators[key] = null;
  try {
    const availability = await Translator.availability({ sourceLanguage: from, targetLanguage: to });
    if (availability === 'unavailable') return;
    builtInTranslators[key] = await Translator.create({ sourceLanguage: from, targetLanguage: to });
  } catch (err) {
    console.warn('Built-in translator not available, using MyMemory instead.', err);
  }
}

async function translate(text, { from, to }) {
  const builtIn = builtInTranslators[from + '-' + to];
  if (builtIn) {
    try {
      return await builtIn.translate(text);
    } catch (err) {
      console.warn('Built-in translation failed, trying MyMemory.', err);
    }
  }
  // Free public API, no key needed. Anonymous use is limited to roughly
  // 5,000 characters per day per IP.
  const url = 'https://api.mymemory.translated.net/get?langpair=' + from + '|' + to + '&q=' + encodeURIComponent(text);
  const res = await fetch(url);
  if (!res.ok) throw new Error('Translation request failed: ' + res.status);
  const data = await res.json();
  if (data.responseStatus !== 200) throw new Error(data.responseDetails || 'Translation failed');
  return data.responseData.translatedText;
}

async function addLine(original) {
  const langs = languages();
  const li = document.createElement('li');
  const en = document.createElement('div');
  const es = document.createElement('div');
  en.className = 'en';
  es.className = 'es';
  en.textContent = 'Translating…';
  es.textContent = original;
  li.append(en, es);
  linesEl.append(li);
  li.scrollIntoView({ behavior: 'smooth', block: 'end' });

  try {
    en.textContent = await translate(original, langs);
  } catch (err) {
    en.textContent = '(Could not translate: ' + err.message + ')';
  }
}

function createRecognition() {
  const r = new SpeechRecognition();
  r.lang = languages().from === 'es' ? dialectSelect.value : 'en-US';
  r.continuous = true;
  r.interimResults = true;

  r.onresult = (event) => {
    let interim = '';
    for (let i = event.resultIndex; i < event.results.length; i++) {
      const result = event.results[i];
      const text = result[0].transcript.trim();
      if (result.isFinal) {
        if (text) addLine(text);
      } else {
        interim += text + ' ';
      }
    }
    interimEl.textContent = interim;
  };

  r.onerror = (event) => {
    if (event.error === 'no-speech' || event.error === 'aborted') return;
    if (event.error === 'not-allowed' || event.error === 'service-not-allowed') {
      setStatus('Microphone access was blocked. Allow it in your browser settings and try again.');
      stop();
      return;
    }
    setStatus('Speech recognition error: ' + event.error);
  };

  // Browsers end recognition after a pause or a time limit. Restart it so
  // listening continues until the user presses Stop.
  r.onend = () => {
    interimEl.textContent = '';
    if (listening) {
      try { r.start(); } catch (err) { console.warn(err); }
    }
  };

  return r;
}

async function start() {
  listening = true;
  toggleBtn.textContent = 'Stop';
  toggleBtn.classList.add('listening');
  directionSelect.disabled = true;
  dialectSelect.disabled = true;
  setStatus(languages().from === 'es' ? 'Listening for Spanish…' : 'Listening for English…');
  recognition = createRecognition();
  recognition.start();
  prepareBuiltInTranslator(languages());
}

function stop() {
  listening = false;
  toggleBtn.textContent = 'Start listening';
  toggleBtn.classList.remove('listening');
  directionSelect.disabled = false;
  updateDialectState();
  if (recognition) recognition.stop();
  setStatus('Stopped.');
}

// The dialect only matters when listening for Spanish.
function updateDialectState() {
  dialectSelect.disabled = languages().from !== 'es';
}
directionSelect.addEventListener('change', updateDialectState);
updateDialectState();

toggleBtn.addEventListener('click', () => (listening ? stop() : start()));
clearBtn.addEventListener('click', () => {
  linesEl.innerHTML = '';
  interimEl.textContent = '';
});

if ('serviceWorker' in navigator) {
  navigator.serviceWorker.register('sw.js').catch(() => {});
}
