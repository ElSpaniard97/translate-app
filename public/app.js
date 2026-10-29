// Listens for Spanish speech with the browser's built-in speech recognition,
// then shows each finished phrase with its English translation.

const SpeechRecognition = window.SpeechRecognition || window.webkitSpeechRecognition;

const toggleBtn = document.getElementById('toggle');
const clearBtn = document.getElementById('clear');
const dialectSelect = document.getElementById('dialect');
const statusEl = document.getElementById('status');
const linesEl = document.getElementById('lines');
const interimEl = document.getElementById('interim');

let recognition = null;
let listening = false;
let builtInTranslator = null;

function setStatus(text) {
  statusEl.textContent = text;
}

if (!SpeechRecognition) {
  toggleBtn.disabled = true;
  setStatus('This browser does not support speech recognition. Use Chrome, Edge, or Safari.');
}

// Chrome 138+ ships an on-device translator. Use it when available, since it
// is free, private, and has no rate limit. Otherwise fall back to MyMemory.
async function prepareBuiltInTranslator() {
  if (builtInTranslator || !('Translator' in self)) return;
  try {
    const availability = await Translator.availability({ sourceLanguage: 'es', targetLanguage: 'en' });
    if (availability === 'unavailable') return;
    builtInTranslator = await Translator.create({ sourceLanguage: 'es', targetLanguage: 'en' });
  } catch (err) {
    console.warn('Built-in translator not available, using MyMemory instead.', err);
  }
}

async function translate(text) {
  if (builtInTranslator) {
    try {
      return await builtInTranslator.translate(text);
    } catch (err) {
      console.warn('Built-in translation failed, trying MyMemory.', err);
    }
  }
  // Free public API, no key needed. Anonymous use is limited to roughly
  // 5,000 characters per day per IP.
  const url = 'https://api.mymemory.translated.net/get?langpair=es|en&q=' + encodeURIComponent(text);
  const res = await fetch(url);
  if (!res.ok) throw new Error('Translation request failed: ' + res.status);
  const data = await res.json();
  if (data.responseStatus !== 200) throw new Error(data.responseDetails || 'Translation failed');
  return data.responseData.translatedText;
}

async function addLine(spanish) {
  const li = document.createElement('li');
  const en = document.createElement('div');
  const es = document.createElement('div');
  en.className = 'en';
  es.className = 'es';
  en.textContent = 'Translating…';
  es.textContent = spanish;
  li.append(en, es);
  linesEl.append(li);
  li.scrollIntoView({ behavior: 'smooth', block: 'end' });

  try {
    en.textContent = await translate(spanish);
  } catch (err) {
    en.textContent = '(Could not translate: ' + err.message + ')';
  }
}

function createRecognition() {
  const r = new SpeechRecognition();
  r.lang = dialectSelect.value;
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
  dialectSelect.disabled = true;
  setStatus('Listening for Spanish…');
  recognition = createRecognition();
  recognition.start();
  prepareBuiltInTranslator();
}

function stop() {
  listening = false;
  toggleBtn.textContent = 'Start listening';
  toggleBtn.classList.remove('listening');
  dialectSelect.disabled = false;
  if (recognition) recognition.stop();
  setStatus('Stopped.');
}

toggleBtn.addEventListener('click', () => (listening ? stop() : start()));
clearBtn.addEventListener('click', () => {
  linesEl.innerHTML = '';
  interimEl.textContent = '';
});

if ('serviceWorker' in navigator) {
  navigator.serviceWorker.register('sw.js').catch(() => {});
}
