function svgIcon(name) {
  const ns = 'http://www.w3.org/2000/svg';
  const icon = document.createElementNS(ns,'svg');
  const use = document.createElementNS(ns,'use');
  use.setAttribute('href','#i-'+name);
  icon.setAttribute('aria-hidden','true');
  icon.append(use);
  return icon;
}
function setIcon(button,icon,label) {
  button.firstElementChild.firstElementChild.setAttribute('href','#i-'+icon);
  button.title = label;
  button.setAttribute('aria-label',label);
}
let noticeMessages = [];
function notice(...messages) {
  noticeMessages = messages;
  $('notice').textContent = messages.map(localize).join(' · ');
  $('notice').hidden = !messages.length;
}
function clock(seconds) {
  const time = Math.max(0,Math.floor(seconds+.00001));
  const h = Math.floor(time/3600);
  const m = h ? Math.floor(time/60)%60 : Math.floor(time/60);
  const s = time%60;
  return (h ? h+':' : '') + String(m).padStart(2,'0')+':'+String(s).padStart(2,'0');
}
function updateTime(time) {
  const elapsed = clock(time);
  if ($('elapsed').textContent !== elapsed) {
    $('elapsed').textContent = elapsed;
    $('elapsedCopy').textContent = elapsed;
  }
  $('seek').value = state.duration ? Math.round(time/state.duration*10000) : 0;
  $('seek').setAttribute('aria-valuetext',elapsed+' / '+clock(state.duration));
}
function updateTransport() {
  const controls = ['play','rewind','seek'];
  for (const control of controls) $(control).disabled = !state.duration;
  const length = clock(state.duration);
  $('duration').textContent = $('durationCopy').textContent = length;
  setIcon($('play'),state.playing ? 'pause' : 'play',t(state.playing ? 'pause' : 'play'));
  $('loop').setAttribute('aria-pressed',state.loop);
  setIcon($('mute'),state.volume ? 'volume' : 'muted',t(state.volume ? 'mute' : 'unmute'));
  $('volume').value = Math.round(state.volume*100);
  updateTime(position());
}

function trackButton(icon,label) {
  const button = document.createElement('button');
  button.className = 'icon-button';
  button.type = 'button';
  button.title = label;
  button.setAttribute('aria-label',label);
  button.append(svgIcon(icon));
  return button;
}
let noteLayer, noteModeButton;
const layerName = layer => layer.demo ? t(layer.name) : layer.name;
function updateNoteModeButton(layer,button) {
  const mode = t(noteModes[layer.noteMode]);
  button.dataset.multicolor = layer.noteMode !== 'solid';
  button.title = t('layerModeTitle',{mode});
  button.setAttribute('aria-label',t('layerModeLabel',{name:layerName(layer),mode}));
}
function showNoteSwatches(layer) {
  const swatches = paletteOf(layer).map(color => {
    const swatch = document.createElement('span');
    swatch.className = 'note-swatch';
    swatch.style.backgroundColor = color;
    return swatch;
  });
  $('noteSwatches').replaceChildren(...swatches);
}
function layerList() {
  const holder = $('tracks');
  const active = new Set(state.active);
  holder.replaceChildren();
  for (const layer of state.layers) {
    const name = layerName(layer);
    const row = document.createElement('div');
    row.className = 'track' + (active.has(layer) ? '' : ' off');
    row.style.setProperty('--track',colorOf(layer));
    const thumbnail = document.createElement('span');
    thumbnail.className = 'note-icon';
    thumbnail.append(svgIcon('note'));
    const desc = document.createElement('div');
    desc.className = 'track-text';
    const title = document.createElement('strong');
    title.title = title.textContent = name;
    const meta = document.createElement('small');
    const status = !layer.enabled ? 'layerDisabled' : !active.has(layer) ? 'layerOverLimit' : layer.demo ? 'demo' : '';
    meta.textContent = (status ? t(status)+' · ' : '') + clock(layer.duration);
    desc.append(title,meta);
    const color = document.createElement('input');
    color.type = 'color';
    color.className = 'color-pick';
    color.value = colorOf(layer);
    color.setAttribute('aria-label',t('layerColorLabel',{name}));
    color.title = t('layerColor');
    color.addEventListener('input',() => {
      layer.color = color.value;
      row.style.setProperty('--track',color.value);
      updateLegend();
      markDirty();
    });
    const mode = trackButton('colors',t('noteColors'));
    mode.classList.add('note-mode-button');
    mode.setAttribute('aria-haspopup','dialog');
    updateNoteModeButton(layer,mode);
    mode.addEventListener('click',() => {
      noteLayer = layer;
      noteModeButton = mode;
      $('noteLayerName').textContent = layerName(layer);
      $('noteMode').value = layer.noteMode;
      showNoteSwatches(layer);
      $('noteDialog').showModal();
    });
    const mute = trackButton(layer.enabled ? 'volume' : 'muted',t(layer.enabled ? 'disableLayer' : 'enableLayer',{name}));
    mute.setAttribute('aria-pressed',!layer.enabled);
    mute.addEventListener('click',() => {
      layer.enabled = !layer.enabled;
      const index = state.layers.indexOf(layer);
      refreshLayers();
      $('tracks').children[index]?.querySelector('[aria-pressed]')?.focus();
    });
    const remove = trackButton('close',t('removeLayer',{name}));
    remove.addEventListener('click',() => {
      const index = state.layers.indexOf(layer);
      state.layers.splice(index,1);
      refreshLayers();
      const next = $('tracks').children[Math.min(index,state.layers.length-1)];
      (next?.querySelector('button:last-child') || $('add')).focus();
    });
    row.append(thumbnail,desc,color,mode,mute,remove);
    holder.append(row);
  }
  $('trackCount').textContent = state.active.length+' / '+state.limit;
  $('trackCount').title = t('layerLimit');
}
function updateLegend() {
  const target = $('legend');
  target.replaceChildren();
  for (const layer of state.active) {
    const item = document.createElement('span');
    item.className = 'legend-item';
    item.title = layerName(layer);
    const dot = document.createElement('i');
    if (layer.noteMode !== 'solid') dot.className = 'multicolor';
    dot.style.setProperty('--swatch',colorOf(layer));
    const name = item.title.replace(/\.(midi?|smf)$/i,'');
    item.append(dot,name.length > 22 ? name.slice(0,20)+'…' : name);
    target.append(item);
  }
}
function updateEmptyRoll() {
  $('empty').hidden = state.active.length > 0;
  $('empty').textContent = t(state.layers.length ? 'layersDisabled' : 'emptyRoll');
}
function refreshLayers() {
  const time = position();
  state.active = state.layers.filter(layer=>layer.enabled).slice(0,state.limit);
  state.duration = Math.max(0,...state.active.map(layer => layer.duration));
  state.position = clamp(time,0,state.duration);
  if (state.playing && state.position < state.duration) restartAudio(state.position);
  else if (state.playing || (!state.duration && state.starting)) {
    state.playing = false;
    state.starting = false;
    state.run++;
    stopPlaybackVoices();
  }
  updateEmptyRoll();
  layerList();
  updateLegend();
  updateTransport();
  updateWave();
  clearEffects();
  markDirty();
}
function changeLimit(value) {
  state.limit = clamp(Math.round(Number(value) || state.limit),1,16);
  $('limit').value = state.limit;
  $('limitDown').disabled = state.limit <= 1;
  $('limitUp').disabled = state.limit >= 16;
  refreshLayers();
}

let importChain = Promise.resolve();
function queueFiles(files) {
  const queue = [...files];
  if (!queue.length) return;
  importChain = importChain.then(() => addFiles(queue)).catch(error => notice(errorMessage(error,'importFailed')));
}
async function addFiles(files) {
  const errors = [];
  const parsedFiles = [];
  for (const file of files) {
    if (state.layers.filter(layer=>!layer.demo).length + parsedFiles.length >= 16) {
      errors.push(message('midiFileLimit'));
      break;
    }
    try {
      if (file.size > 16*1024*1024) throw new LocalizedError('midiTooLarge');
      const data = parseMidi(await file.arrayBuffer());
      parsedFiles.push({name:file.name,...data});
    } catch (error) {
      errors.push(message('fileError',{name:file.name,error:errorMessage(error,'midiReadFailed')}));
    }
  }
  if (parsedFiles.length) {
    const replacedDemo = state.layers.some(layer=>layer.demo);
    const next = state.layers.filter(layer=>!layer.demo);
    const colors = activeTheme().palette;
    for (const {name,notes,duration} of parsedFiles) {
      const color = next.length ? colors.find(candidate => !next.some(layer=>colorOf(layer) === candidate)) || colors[next.length % colors.length] : null;
      next.push(makeLayer(name,notes,duration,color));
    }
    state.layers = next;
    if (replacedDemo) { pause(); state.position = 0; }
    refreshLayers();
  }
  notice(...errors);
}
function fillSettings() {
  $('noteColor').value = primaryNoteColor();
  $('keyColor').value = activeKeyColor();
  fillKeyboardRange();
  $('horizon').value = state.style.horizon;
  $('noteFill').value = state.style.noteFill;
  showRoundness();
  for (const checkbox of document.querySelectorAll('[data-effect]')) checkbox.checked = state.style.effects[checkbox.dataset.effect];
  fillAppearance();
}
function fillKeyboardRange() {
  const {range,keyFrom,keyTo} = state.style;
  const count = keyTo-keyFrom+1;
  $('range').value = range;
  $('customRangeFields').hidden = range !== 0;
  $('firstKey').value = keyFrom;
  $('lastKey').value = keyTo;
  $('visibleKeys').value = count;
  $('keyCount').textContent = t(range === 0 ? 'customKeyCount' : range === 128 ? 'fullKeys' : 'standardKeys',{count});
}

function applyKeyboardRange() {
  fillKeyboardRange();
  for (const pointer of previews.keys()) releaseKey(pointer);
  clearEffects();
  saveStyle();
}
function applyLanguage() {
  $('language').value = language;
  translatePage();
}
function applyTheme() {
  document.documentElement.dataset.theme = state.style.theme;
  $('theme').value = state.style.theme;
}
function showRoundness() {
  $('noteRoundness').value = state.style.noteRoundness;
  $('roundnessValue').textContent = state.style.noteRoundness+'%';
}
function fillAppearance() {
  $('keyStyle').value = state.style.keyStyle;
  const selector = $('backgroundOptions');
  for (const radio of selector.querySelectorAll('input')) radio.checked = radio.value === state.style.background;
  $('customBackgroundOption').hidden = !customBackground;
  $('backgroundName').hidden = !customBackground;
  const name = customBackground ? customBackground.name || t('customBackground') : '';
  $('backgroundName').textContent = $('backgroundName').title = name;
  $('customBackgroundThumb').style.backgroundImage = customBackground ? 'url("'+customBackground.source+'")' : '';
  $('backgroundShadeRow').hidden = state.style.background !== 'custom' || !customBackground;
  $('backgroundShade').value = state.style.backgroundShade;
}
function saveStyle() {
  try { localStorage.setItem('neon-midi-style-v1',JSON.stringify(state.style)); } catch {}
  markDirty();
}
const backgroundStorageKey = 'neon-midi-background-v1';
let backgroundLoad = 0;
let backgroundMessage = null;
function backgroundStatus(next = null) {
  backgroundMessage = next;
  $('backgroundStatus').textContent = localize(next);
  $('backgroundStatus').hidden = !next;
}
function backgroundImage(source) {
  return new Promise((resolve,reject) => {
    const image = new Image();
    image.onload = () => image.naturalWidth && image.naturalHeight
      ? resolve(image) : reject(new LocalizedError('imageOpenFailed'));
    image.onerror = () => reject(new LocalizedError('imageOpenFailed'));
    image.src = source;
  });
}
function setCustomBackground(image) {
  customBackground = image;
  backgroundRevision++;
  fillAppearance();
  markDirty();
}
async function restoreBackground() {
  const request = backgroundLoad;
  try {
    const saved = JSON.parse(localStorage.getItem(backgroundStorageKey));
    if (typeof saved?.source === 'string' && /^data:image\/(webp|jpeg|png);base64,/.test(saved.source)) {
      const image = await backgroundImage(saved.source);
      if (request === backgroundLoad) setCustomBackground({source:saved.source,name:String(saved.name || ''),image});
      return;
    }
  } catch {}
  if (request === backgroundLoad && state.style.background === 'custom') {
    state.style.background = 'theme';
    fillAppearance();
    saveStyle();
  }
}
async function loadBackground(file) {
  const request = ++backgroundLoad;
  backgroundStatus(message('imageOpening'));
  try {
    if (file.size > 25*1024*1024) throw new LocalizedError('imageTooLarge');
    const url = URL.createObjectURL(file);
    let source;
    try {
      const original = await backgroundImage(url);
      if (request !== backgroundLoad) return;
      const canvas = document.createElement('canvas');
      const scale = Math.min(1,1920/Math.max(original.naturalWidth,original.naturalHeight));
      canvas.width = Math.max(1,Math.round(original.naturalWidth*scale));
      canvas.height = Math.max(1,Math.round(original.naturalHeight*scale));
      canvas.getContext('2d').drawImage(original,0,0,canvas.width,canvas.height);
      source = canvas.toDataURL('image/webp',.82);
      if (source.length > 1_000_000) source = canvas.toDataURL('image/jpeg',.74);
    } finally {
      URL.revokeObjectURL(url);
    }
    const image = await backgroundImage(source);
    if (request !== backgroundLoad) return;
    state.style.background = 'custom';
    setCustomBackground({image,name:file.name,source});
    try {
      localStorage.setItem(backgroundStorageKey,JSON.stringify({name:file.name,source}));
      backgroundStatus();
    } catch {
      try { localStorage.removeItem(backgroundStorageKey); } catch {}
      backgroundStatus(message('imageSessionOnly'));
    }
    saveStyle();
  } catch (error) {
    if (request === backgroundLoad) {
      backgroundStatus(errorMessage(error,'imageLoadFailed'));
      if (!customBackground && state.style.background === 'custom') restoreBackground();
    }
  }
}
function showSettings(show, focus = false) {
  $('settings').hidden = !show;
  $('workbench').classList.toggle('collapsed',!show);
  $('toggleSettings').setAttribute('aria-expanded',show);
  if (focus && show && matchMedia('(max-width: 760px)').matches) $('settings').scrollIntoView({block:'nearest',behavior:media.matches?'auto':'smooth'});
  if (focus && !show) $('toggleSettings').focus();
  markDirty();
}

for (const id of ['open','add']) $(id).addEventListener('click',() => $('files').click());
$('files').addEventListener('change',event => { queueFiles(event.target.files); event.target.value = ''; });
$('demo').addEventListener('click',() => {
  if (state.layers.every(layer => layer.demo) && state.layers.length === 2 && state.active.length) {
    jump(0);
  } else {
    pause();
    state.position = 0;
    state.layers = makeDemo();
    refreshLayers();
  }
  notice();
  seedDemo();
  play();
});
let dragDepth = 0;
$('dropZone').addEventListener('dragenter',event => {
  if (!event.dataTransfer.types.includes('Files')) return;
  event.preventDefault();
  dragDepth++;
  $('dropHint').hidden = false;
});
$('dropZone').addEventListener('dragover',event => {
  if (!event.dataTransfer.types.includes('Files')) return;
  event.preventDefault();
  event.dataTransfer.dropEffect = 'copy';
});
$('dropZone').addEventListener('dragleave',() => {
  dragDepth = Math.max(0,dragDepth-1);
  if (!dragDepth) $('dropHint').hidden = true;
});
$('dropZone').addEventListener('drop',event => {
  event.preventDefault();
  dragDepth = 0;
  $('dropHint').hidden = true;
  queueFiles(event.dataTransfer.files);
});
window.addEventListener('dragover',event => {
  if (event.dataTransfer.types.includes('Files')) event.preventDefault();
});
window.addEventListener('drop',event => {
  if (event.dataTransfer.files.length) event.preventDefault();
});

$('limit').addEventListener('change',event => changeLimit(event.target.value));
$('limit').addEventListener('keydown',event => { if (event.key === 'Enter') changeLimit(event.target.value); });
$('limitDown').addEventListener('click',() => changeLimit(state.limit-1));
$('limitUp').addEventListener('click',() => changeLimit(state.limit+1));
$('toggleSettings').addEventListener('click',() => showSettings($('settings').hidden,true));
$('closeSettings').addEventListener('click',() => showSettings(false,true));
$('language').addEventListener('change',event => {
  if (!['ru','en'].includes(event.target.value)) return;
  language = event.target.value;
  try { localStorage.setItem(languageStorageKey,language); } catch {}
  applyLanguage();
  fillSettings();
  layerList();
  updateLegend();
  updateEmptyRoll();
  updateTransport();
  updateRecordingUI();
  fullscreenChanged();
  if (noteLayer) $('noteLayerName').textContent = layerName(noteLayer);
  notice(...noticeMessages);
  backgroundStatus(backgroundMessage);
});
$('theme').addEventListener('change',event => {
  if (!Object.hasOwn(themes,event.target.value)) return;
  state.style.theme = event.target.value;
  applyTheme();
  fillSettings();
  layerList();
  updateLegend();
  clearEffects();
  if (!state.playing && position() === 0) seedDemo();
  saveStyle();
});
$('more').addEventListener('click',() => $('effectDialog').showModal());
$('closeDialog').addEventListener('click',() => $('effectDialog').close());
$('closeNoteDialog').addEventListener('click',() => $('noteDialog').close());
$('noteMode').addEventListener('change',event => {
  const mode = event.target.value;
  if (!noteLayer || !Object.hasOwn(noteModes,mode)) return;
  noteLayer.noteMode = mode;
  updateNoteModeButton(noteLayer,noteModeButton);
  showNoteSwatches(noteLayer);
  updateLegend();
  clearEffects();
  if (!state.playing && position() === 0) seedDemo();
  markDirty();
});
$('appearance').addEventListener('click',() => $('appearanceDialog').showModal());
$('closeAppearance').addEventListener('click',() => $('appearanceDialog').close());
$('keyStyle').addEventListener('change',event => {
  if (!keyStyles.includes(event.target.value)) return;
  state.style.keyStyle = event.target.value;
  saveStyle();
});
$('backgroundOptions').addEventListener('change',event => {
  const setting = event.target.value;
  if (!backgroundStyles.includes(setting) || (setting === 'custom' && !customBackground)) return;
  state.style.background = setting;
  fillAppearance();
  saveStyle();
});
$('backgroundShade').addEventListener('input',event => {
  state.style.backgroundShade = clamp(+event.target.value,0,85);
  saveStyle();
});
$('uploadBackground').addEventListener('click',() => $('backgroundFile').click());
$('backgroundFile').addEventListener('change',event => {
  const file = event.target.files[0];
  event.target.value = '';
  if (file) return loadBackground(file);
});
$('noteColor').addEventListener('input',event => {
  state.style.noteColor = event.target.value;
  const rows = $('tracks').children;
  state.layers.forEach((layer,index) => {
    if (!layer.color && !layer.useSecondaryColor) {
      rows[index].style.setProperty('--track',event.target.value);
      rows[index].querySelector('input').value = event.target.value;
    }
  });
  updateLegend();
  saveStyle();
});
$('keyColor').addEventListener('input',event => { state.style.keyColor = event.target.value; saveStyle(); });
const pitchNames = ['C','C♯','D','D♯','E','F','F♯','G','G♯','A','A♯','B'];
for (let pitch = 0; pitch < 128; pitch++) {
  const name = pitchNames[pitch%12]+(Math.floor(pitch/12)-1)+' · '+pitch;
  $('firstKey').add(new Option(name,pitch));
  $('lastKey').add(new Option(name,pitch));
}
$('range').addEventListener('change',event => {
  state.style.range = Number(event.target.value);
  applyKeyboardRange();
});
$('firstKey').addEventListener('change',event => {
  state.style.keyFrom = Number(event.target.value);
  state.style.keyTo = Math.max(state.style.keyTo,state.style.keyFrom);
  applyKeyboardRange();
});
$('lastKey').addEventListener('change',event => {
  state.style.keyTo = Number(event.target.value);
  state.style.keyFrom = Math.min(state.style.keyFrom,state.style.keyTo);
  applyKeyboardRange();
});
$('visibleKeys').addEventListener('change',event => {
  const count = clamp(Math.round(event.target.valueAsNumber),1,128);
  if (Number.isFinite(count)) {
    state.style.keyFrom = Math.min(state.style.keyFrom,128-count);
    state.style.keyTo = state.style.keyFrom+count-1;
  }
  applyKeyboardRange();
});
$('horizon').addEventListener('change',event => { state.style.horizon = +event.target.value; saveStyle(); });
$('noteFill').addEventListener('change',event => {
  if (!noteFills.includes(event.target.value)) return;
  state.style.noteFill = event.target.value;
  saveStyle();
});
$('noteRoundness').addEventListener('input',event => {
  state.style.noteRoundness = clamp(Math.round(+event.target.value),0,100);
  showRoundness();
  saveStyle();
});
for (const control of document.querySelectorAll('[data-effect]')) {
  control.addEventListener('change',event => {
    const { dataset, checked } = event.target;
    state.style.effects[dataset.effect] = checked;
    if (dataset.effect === 'particles' && !checked) particles = [];
    if (dataset.effect === 'ripples' && !checked) flashes = [];
    saveStyle();
  });
}
$('reset').addEventListener('click',() => {
  state.style = {...defaultStyle,theme:state.style.theme,effects:{...defaultEffects}};
  fillSettings();
  layerList();
  updateLegend();
  clearEffects();
  if (!state.playing && position() === 0) seedDemo();
  saveStyle();
});
$('play').addEventListener('click',() => state.playing || state.starting ? pause() : play());
$('rewind').addEventListener('click',() => jump(0));
$('loop').addEventListener('click',() => { state.loop = !state.loop; updateTransport(); });
$('seek').addEventListener('input',event => jump(state.duration*Number(event.target.value)/10000));
$('speed').addEventListener('change',event => {
  const time = position();
  state.speed = +event.target.value;
  if (state.playing) restartAudio(time);
});
function changeVolume(value) {
  state.volume = value;
  if (value > 0) state.lastVolume = value;
  if (master) master.gain.setTargetAtTime(value,audio.currentTime,.016);
  updateTransport();
}
$('volume').addEventListener('input',event => changeVolume(+event.target.value/100));
$('mute').addEventListener('click',() => changeVolume(state.volume ? 0 : state.lastVolume));

function fullscreenChanged() {
  const expanded = document.fullscreenElement === $('stage') || $('stage').classList.contains('expanded');
  setIcon($('fullscreen'),expanded ? 'collapse' : 'expand',t(expanded ? 'exitFullscreen' : 'fullscreen'));
  markDirty();
}
$('fullscreen').addEventListener('click',async () => {
  const stage = $('stage');
  if (document.fullscreenElement === stage) await document.exitFullscreen();
  else if (stage.classList.contains('expanded')) stage.classList.remove('expanded');
  else {
    try { await stage.requestFullscreen(); }
    catch { stage.classList.add('expanded'); }
  }
  fullscreenChanged();
});
document.addEventListener('fullscreenchange',fullscreenChanged);
window.addEventListener('keydown',event => {
  if (event.code === 'Escape' && $('stage').classList.contains('expanded')) {
    $('stage').classList.remove('expanded');
    fullscreenChanged();
  }
  if (event.defaultPrevented || event.altKey || event.ctrlKey || event.metaKey || $('effectDialog').open || $('noteDialog').open || $('appearanceDialog').open ||
      /^(BUTTON|INPUT|SELECT|TEXTAREA|A)$/.test(event.target.tagName) || event.target.isContentEditable) return;
  if (event.code === 'Space' && !event.repeat) {
    event.preventDefault();
    if (state.playing || state.starting) pause(); else play();
  } else if (event.code === 'ArrowLeft' || event.code === 'ArrowRight') {
    event.preventDefault();
    jump(position() + (event.code === 'ArrowLeft' ? -5 : 5));
  }
});
function pianoHit(event) {
  const rect = roll.getBoundingClientRect();
  const x = event.clientX-rect.left;
  const y = event.clientY-rect.top;
  const {impact,h,black,white} = buildGeometry();
  if (y < impact || y > h) return null;
  const matches = slot => x >= slot.x && x < slot.x+slot.width;
  const slot = (y < impact+(h-impact)*.61 && black.find(matches)) || white.find(matches);
  return slot?.pitch ?? null;
}
roll.addEventListener('pointerdown',event => {
  if (event.button !== 0) return;
  const pitch = pianoHit(event);
  if (pitch === null) return;
  roll.setPointerCapture(event.pointerId);
  animatePreviewUntil = performance.now()+830;
  previewKey(pitch,event.pointerId);
});
roll.addEventListener('pointermove',event => {
  if (!roll.hasPointerCapture(event.pointerId)) return;
  const pitch = pianoHit(event);
  if (pitch === null) { releaseKey(event.pointerId); return; }
  if (previews.get(event.pointerId)?.pitch === pitch) return;
  animatePreviewUntil = performance.now()+830;
  previewKey(pitch,event.pointerId);
});
for (const type of ['pointerup','pointercancel','lostpointercapture']) roll.addEventListener(type,event => releaseKey(event.pointerId));
window.addEventListener('blur',() => { for (const pointer of previews.keys()) releaseKey(pointer); });
new ResizeObserver(markDirty).observe(roll);
new ResizeObserver(markDirty).observe(overview);
media.addEventListener?.('change',markDirty);
$('download').href = location.href;
applyLanguage();
applyTheme();
fillSettings();
changeLimit(state.limit);
seedDemo();
restoreBackground();
initRecording();
