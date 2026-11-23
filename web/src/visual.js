const roll = $('roll');
const overview = $('overview');
const background = document.createElement('canvas');
const noteLayerCanvas = document.createElement('canvas');
const ctx = roll.getContext('2d', {alpha:false});
const waveCtx = overview.getContext('2d');
const bgCtx = background.getContext('2d', {alpha:false});
const noteCtx = noteLayerCanvas.getContext('2d');
const sovietArtwork = new Image();
let geometry, stamp = '', waveBins = [];
let customBackground = null;
let backgroundRevision = 0;
let frame = 0, burstClock = 0, previousTime = -0.00001;
let particles = [], flashes = [];
let animatePreviewUntil = 0;
const rgbCache = new Map();
const rgba = (color, alpha) => {
  if (!rgbCache.has(color)) {
    if (rgbCache.size > 256) rgbCache.clear();
    const hex = parseInt(color.slice(1),16);
    rgbCache.set(color, [hex >> 16, hex >> 8 & 255, hex & 255]);
  }
  return 'rgba(' + rgbCache.get(color).join(',') + ',' + alpha + ')';
};
const blackPitch = pitch => [1,3,6,8,10].includes(pitch % 12);
const KEY_NAMES = ['C','C♯','D','D♯','E','F','F♯','G','G♯','A','A♯','B'];
const stageBackgrounds = {
  aurora:{ base:['#0e0b19','#160d26','#100919'] },
  soviet:{ base:['#14080f','#350d19','#651f20'], halos:[[.52,.90,.46,'#fc632b',.43],[.24,.75,.42,'#b32b50',.25]], stars:0 },
  orbit:{ base:['#040711','#0c1530','#130f2a'], halos:[[.28,.42,.55,'#407cde',.29],[.78,.72,.36,'#a95fd9',.24]], stars:140 },
  ocean:{ base:['#050e1c','#092137','#061727'], halos:[[.55,.16,.62,'#2789ac',.33],[.28,.96,.47,'#197b91',.26]], stars:45 },
  sunset:{ base:['#140b21','#3d193d','#240f25'], halos:[[.60,.92,.51,'#db6583',.42],[.36,.30,.42,'#7951ba',.30]], stars:65 }
};
const rollColors = {
  classic:{
    lane:['#03020b30','#7160804d','#9784b31c'], band:['#8e73a31b','#8f72b82e'],
    line:'#bc89fd', mutedLine:'#7b638d', track:'#0e0b16', cursor:'#d9afff', trace:'#9e6ce2'
  },
  soviet:{
    lane:['#13020728','#e88e7461','#ef9a6c20'], band:['#ba5d451e','#fc957c28'],
    line:'#ff875f', mutedLine:'#a55b47', track:'#150a0e', cursor:'#ffc685', trace:'#ec6a47'
  }
};
const keyboardSurfaces = {
  piano:{
    white:['#9d8bad','#d3c9e0','#f6eef8'], black:['#332840','#191324','#100c18'],
    border:['','#675671'], label:'#3e304e', detail:'#65566c91', radius:2.1
  },
  soviet:{
    white:['#d36e74','#ffd8b8','#fff1dd'], black:['#6e292d','#311019','#1c0710'],
    border:['#ffd39d','#ff735c'], label:'#5e2a30', detail:'#ff976bac', radius:2.4
  },
  glass:{
    white:['#eee3ff2b','#d2c4f019','#f6e7ff39'], black:['#140c2769','#0e071b48','#110b2669'],
    border:['#d6c4f376','#ac91d6a5'], label:'#fff1fd', detail:'#d8c4ff60', radius:3
  },
  neon:{
    white:['#251b47','#11142d','#190c31'], black:['#371942','#190d27','#120a22'],
    border:['#7ba4eb','#d185e7'], label:'#d3cdff', detail:'#ba8ee5a4', radius:3.4
  },
  matte:{
    white:['#646872','#595d65','#454951'], black:['#20232b','#1a1e25','#11141a'],
    border:['#969ba8','#515663'], label:'#f6f4ff', detail:'#bcbecb78', radius:1.5
  },
  square:{
    white:['#292a34','#1b1c24','#14151d'], black:['#11121a','#0c0c13','#08090f'],
    border:['#b5b8c7','#71768b'], label:'#f9f7ff', detail:'#aeb1c265', radius:0
  },
  gold:{
    white:['#9d6025','#edbd69','#fbe1a4'], black:['#775127','#472a19','#2d160e'],
    border:['#f8de9b','#c09051'], label:'#4f260f', detail:'#fff1c891', radius:2.8
  },
  spectrum:{
    border:['#f4e9ff91','#ffe4faa1'], label:'#160e20', detail:'#ffebff8c', radius:3.4
  },
  ice:{
    white:['#457d95','#9ed6e4','#dffbff'], black:['#306077','#194452','#112936'],
    border:['#d6fbff','#6dc3d9'], label:'#173a56', detail:'#d0f9ffb8', radius:3.1
  },
  inverted:{
    white:['#30303a','#16161f','#080911'], black:['#999eac','#e1e5ed','#fbf9ff'],
    border:['#656777','#ffffff'], label:'#edeaf6', detail:'#9193a488', radius:2.1
  }
};
const effectiveKeyStyle = () => state.style.keyStyle === 'theme' ? activeTheme().keyboard : state.style.keyStyle;
function resize(canvas) {
  const w = canvas.clientWidth;
  const h = canvas.clientHeight;
  const dpr = Math.min(devicePixelRatio || 1, 2);
  const width = Math.max(1,Math.round(w*dpr));
  const height = Math.max(1,Math.round(h*dpr));
  if (canvas.width !== width || canvas.height !== height) {
    canvas.width = width;
    canvas.height = height;
  }
  return {w,h,dpr};
}
function rounded(context, x, y, w, h, radius) {
  context.beginPath();
  const r = Math.min(radius,w/2,h/2);
  if (!r) {
    context.rect(x,y,w,h);
  } else if (context.roundRect) {
    context.roundRect(x,y,w,h,r);
  } else {
    context.moveTo(x+r,y);
    context.arcTo(x+w,y,x+w,y+h,r);
    context.arcTo(x+w,y+h,x,y+h,r);
    context.arcTo(x,y+h,x,y,r);
    context.arcTo(x,y,x+w,y,r);
    context.closePath();
  }
}
function gradient(context, x, y, radius, color, opacity) {
  const fill = context.createRadialGradient(x,y,0,x,y,radius);
  fill.addColorStop(0,rgba(color,opacity));
  fill.addColorStop(.46,rgba(color,opacity*.36));
  fill.addColorStop(1,rgba(color,0));
  return fill;
}
function buildGeometry() {
  const {w,h,dpr} = resize(roll);
  const {effects,keyStyle,background,backgroundShade,theme} = state.style;
  const [min,max] = keyboardRange(state.style);
  const key = [w,h,dpr,min,max,keyStyle,background,backgroundShade,theme,backgroundRevision,effects.ambient,effects.bands,effects.lanes].join('-');
  if (key === stamp) return geometry;
  stamp = key;
  const padding = w < 550 ? 8 : 15;
  const impact = h - clamp(h*.173,54,102);
  const leading = blackPitch(min) ? .32 : 0;
  let span = leading+(blackPitch(max) ? .32 : 0);
  for (let p = min; p <= max; p++) if (!blackPitch(p)) span++;
  const width = Math.max(1,w-padding*2) / span;
  const white = [], black = [], pitches = new Map();
  let index = 0;
  for (let p = min; p <= max; p++) {
    const dark = blackPitch(p);
    const size = width * (dark ? .64 : 1);
    const center = padding + (leading + index + (dark ? 0 : .5)) * width;
    const x = center-size/2;
    const slot = {
      pitch:p, x, center, width:size, dark,
      faceX:x+(dark ? 0 : .52), faceWidth:Math.max(1,size-(dark ? .38 : 1.04))
    };
    (dark ? black : white).push(slot);
    pitches.set(p,slot);
    if (!dark) index++;
  }
  geometry = {w,h,dpr,padding,impact,white,black,pitches,keyWidth:width};
  paintBackground();
  return geometry;
}

function fitBackground(image,w,h) {
  const scale = Math.min(w/image.naturalWidth,h/image.naturalHeight);
  const width = image.naturalWidth*scale;
  const height = image.naturalHeight*scale;
  bgCtx.drawImage(image,(w-width)/2,(h-height)/2,width,height);
}

function paintBackground() {
  const {w,h,dpr,padding,impact,white,black} = geometry;
  background.width = roll.width;
  background.height = roll.height;
  bgCtx.setTransform(dpr,0,0,dpr,0,0);
  const {background: setting, backgroundShade, effects} = state.style;
  const keyStyle = effectiveKeyStyle();
  const colors = rollColors[state.style.theme];
  const custom = setting === 'custom' && customBackground;
  const automatic = setting === 'theme' || (setting === 'custom' && !custom);
  const name = automatic ? activeTheme().background : setting;
  const theme = stageBackgrounds[name];
  const imageHeight = keyStyle === 'glass' ? h : impact;
  bgCtx.fillStyle = '#000000';
  bgCtx.fillRect(0,0,w,h);
  if (custom) {
    fitBackground(custom.image,w,imageHeight);
    bgCtx.fillStyle = rgba('#000000',backgroundShade/100);
    bgCtx.fillRect(0,0,w,h);
  } else if (name === 'soviet' && sovietArtwork.complete && sovietArtwork.naturalWidth) {
    fitBackground(sovietArtwork,w,imageHeight);
    bgCtx.fillStyle = '#14080f38';
    bgCtx.fillRect(0,0,w,imageHeight);
  } else if (theme) {
    const fill = bgCtx.createLinearGradient(0,0,0,h);
    fill.addColorStop(0,theme.base[0]);
    fill.addColorStop(.66,theme.base[1]);
    fill.addColorStop(1,theme.base[2]);
    bgCtx.fillStyle = fill;
    bgCtx.fillRect(0,0,w,h);
    const aurora = [
      [.29,.92,.46,'#743bd8',.34], [.73,.85,.43,'#60338b',.35],
      [.48,.96,.32,'#1e718b',.18], [.48,.25,.54,'#42256c',.2]
    ];
    for (const [x,y,r,color,alpha] of theme.halos || (effects.ambient ? aurora : [])) {
      bgCtx.fillStyle = gradient(bgCtx,w*x,impact*y,Math.max(w*r,90),color,alpha);
      bgCtx.fillRect(0,0,w,keyStyle === 'glass' ? h : impact);
    }
  }
  if (effects.lanes) {
    for (const slot of black) {
      bgCtx.fillStyle = colors.lane[0];
      bgCtx.fillRect(slot.x,0,slot.width,impact);
    }
    for (const slot of white) {
      const octave = slot.pitch % 12 === 0;
      bgCtx.fillStyle = colors.lane[octave ? 1 : 2];
      bgCtx.fillRect(Math.round(slot.x)+.5,0,1,impact);
    }
    if (name === 'aurora') {
      bgCtx.fillStyle = '#1a1329';
      bgCtx.fillRect(0,0,padding,impact);
      bgCtx.fillRect(w-padding,0,padding,impact);
    }
  }
  if (effects.bands) {
    for (let i = 1; i <= 7; i++) {
      const y = Math.round(impact*i/8)+.5;
      bgCtx.fillStyle = colors.band[i%2 ? 0 : 1];
      bgCtx.fillRect(padding,y,w-2*padding,1);
    }
  }
  if (theme && effects.ambient) {
    for (let i = 0; i < (theme.stars ?? 85); i++) {
      const t = (Math.sin((i+2)*38.5)*21412.2) % 1;
      const u = (Math.sin((i+3)*85.4)*7942.4) % 1;
      const x = padding + Math.abs(t)*(w-2*padding);
      const y = impact*(.16+.84*Math.abs(u));
      bgCtx.fillStyle = i % 3 ? '#baa1fd30' : '#ead1ff56';
      bgCtx.fillRect(x,y,i%5 ? .8 : 1.4,i%5 ? .8 : 1.4);
    }
  }
  if (keyStyle !== 'glass' && name !== 'black') {
    bgCtx.fillStyle = name === 'aurora' ? '#100b1a' : name === 'soviet' ? '#230910' : '#07050bdc';
    bgCtx.fillRect(0,impact,w,h-impact);
  }
}

function clearEffects() {
  particles = [];
  flashes = [];
  previousTime = position() - .00001;
  burstClock = 0;
}
function emitImpact(pitch,color,velocity,age = 0) {
  const fx = state.style.effects;
  if (media.matches || (!fx.particles && !fx.ripples)) return;
  if (fx.ripples) {
    if (flashes.length >= 90) flashes.shift();
    flashes.push({pitch,color,born:burstClock-age,velocity});
  }
  if (fx.particles) {
    const count = 5 + Math.floor(velocity*7);
    for (let i = 0; i < count; i++) {
      if (particles.length >= 440) particles.shift();
      particles.push({
        pitch,color,born:burstClock-age,
        dx:(Math.random()-.5)*215, dy:38+Math.random()*150,
        lifetime:.3+Math.random()*.5, size:.8+Math.random()*2.55
      });
    }
  }
}
function seedDemo() {
  if (!state.layers.some(layer => layer.demo)) return;
  for (const layer of state.active) {
    for (const note of layer.notes) {
      if (note.start > .001) break;
      emitImpact(note.pitch,noteColorOf(layer,note),note.velocity,.16);
    }
  }
  markDirty();
}
function effectsAt(time) {
  if (time < previousTime || time - previousTime > .38) previousTime = time - .02;
  for (const layer of state.active) {
    for (let i = lowerBound(layer.notes,previousTime); i < layer.notes.length && layer.notes[i].start <= time; i++) {
      const note = layer.notes[i];
      if (note.start > previousTime) emitImpact(note.pitch,noteColorOf(layer,note),note.velocity);
    }
  }
  previousTime = time;
}
function drawNote(slot, top, bottom, color, velocity) {
  const y = Math.max(0,top);
  const end = Math.min(geometry.impact,bottom);
  const height = end-y;
  if (height <= 0) return;
  const {faceX:x,faceWidth:width} = slot;
  rounded(noteCtx,x,y,width,height,Math.min(width,height)*state.style.noteRoundness/200);
  const {noteFill} = state.style;
  const glow = state.style.effects.glow;
  if (glow) {
    noteCtx.shadowBlur = 10 + velocity*13;
    noteCtx.shadowColor = rgba(color,.84);
  }
  if (noteFill !== 'outline') {
    if (noteFill === 'solid') {
      noteCtx.fillStyle = color;
    } else {
      const fill = noteCtx.createLinearGradient(0,y,0,end);
      if (noteFill === 'gradient') {
        fill.addColorStop(0,'#22162e');
        fill.addColorStop(.62,color);
        fill.addColorStop(1,'#ffeffc');
      } else {
        fill.addColorStop(0,rgba(color,glow ? .26 : .47));
        fill.addColorStop(.7,rgba(color,.68));
        fill.addColorStop(1,rgba(color,.96));
      }
      noteCtx.fillStyle = fill;
    }
    noteCtx.fill();
    noteCtx.shadowBlur = 0;
  }
  noteCtx.lineWidth = noteFill === 'outline' ? 1.3 : glow ? 1.05 : .8;
  noteCtx.strokeStyle = noteFill === 'outline' ? color : rgba(color,glow ? .98 : .76);
  noteCtx.stroke();
  noteCtx.shadowBlur = 0;
  if (noteFill !== 'outline' && glow && height >= 3 && width > 3) {
    noteCtx.fillStyle = '#fff9ffae';
    noteCtx.fillRect(x+1.5,end-2.3,width-3,1.2);
  }
}

function drawMidiLayers(visible,time,scale) {
  if (!visible.length) return;
  const {dpr,impact,pitches} = geometry;
  const width = roll.width;
  const height = Math.max(1,Math.ceil((impact+1)*dpr));
  if (noteLayerCanvas.width !== width || noteLayerCanvas.height !== height) {
    noteLayerCanvas.width = width;
    noteLayerCanvas.height = height;
  }
  noteCtx.setTransform(dpr,0,0,dpr,0,0);
  // The first file in the list is the top layer, so draw it last.
  for (let i = visible.length-1; i >= 0; i--) {
    const {layer,notes} = visible[i];
    noteCtx.clearRect(0,0,width/dpr,height/dpr);
    for (const note of notes) {
      const slot = pitches.get(note.pitch);
      drawNote(slot,impact-(note.end-time)*scale,impact-(note.start-time)*scale,noteColorOf(layer,note),note.velocity);
    }
    ctx.drawImage(noteLayerCanvas,0,0,width/dpr,height/dpr);
  }
}

function drawKey(slot, active) {
  const {impact,h} = geometry;
  const {faceX:keyX,faceWidth:keyWidth,dark,pitch} = slot;
  const height = (h-impact-2)*(dark ? .61 : 1);
  const y = impact+1;
  const lit = state.style.effects.keys && active;
  const color = lit?.color;
  const keyStyle = effectiveKeyStyle();
  const surface = keyboardSurfaces[keyStyle];
  const glass = keyStyle === 'glass';
  const spectrumColor = keyStyle === 'spectrum' ? rainbow[pitch % rainbow.length] : null;
  const body = ctx.createLinearGradient(0,y,0,y+height);
  if (color) {
    body.addColorStop(0,rgba(color,glass ? .69 : .96));
    body.addColorStop(.42,rgba(color,dark || glass ? .52 : .71));
    body.addColorStop(1,rgba(color,glass ? .62 : .92));
  } else {
    const colors = spectrumColor
      ? [rgba(spectrumColor,dark ? .52 : .72),rgba(spectrumColor,dark ? .34 : .87),rgba(spectrumColor,dark ? .46 : 1)]
      : (dark ? surface.black : surface.white);
    body.addColorStop(0,colors[0]);
    body.addColorStop(.37,colors[1]);
    body.addColorStop(1,colors[2]);
  }
  if (dark && !glass) { ctx.shadowColor = color || '#08050e'; ctx.shadowBlur = color ? 13 : 4; }
  else if (color) { ctx.shadowColor = color; ctx.shadowBlur = 16; }
  const border = dark && spectrumColor ? spectrumColor : surface.border[dark ? 1 : 0];
  rounded(ctx,keyX,y,keyWidth,height,surface.radius+(dark && surface.radius > 0 ? .5 : 0));
  ctx.fillStyle = body;
  ctx.fill();
  ctx.shadowBlur = 0;
  if (border || color) {
    ctx.lineWidth = .8;
    ctx.strokeStyle = color ? rgba(color,.96) : border;
    ctx.stroke();
    if (keyWidth > 4) {
      ctx.fillStyle = color ? '#fff1fa9c' : surface.detail;
      ctx.fillRect(keyX+1.25,y+height-3,keyWidth-2.5,1);
    }
  }
  if (!dark && pitch % 12 === 0 && geometry.keyWidth >= 9.5) {
    ctx.font = (geometry.keyWidth > 14 ? 9 : 8) + 'px ui-monospace, monospace';
    ctx.fillStyle = color ? '#fff5ff' : surface.label;
    ctx.textAlign = 'center';
    ctx.fillText(KEY_NAMES[pitch%12]+(Math.floor(pitch/12)-1),slot.center,y+height-7);
  }
}

function drawRoll(time) {
  const {w,h,dpr,padding,impact,white,black,pitches} = buildGeometry();
  const fx = state.style.effects;
  const keyColor = activeKeyColor();
  ctx.setTransform(dpr,0,0,dpr,0,0);
  ctx.drawImage(background,0,0,w,h);
  const lit = new Map();
  const scale = impact / state.style.horizon;
  const until = time + state.style.horizon + .02;
  const visible = [];
  for (const layer of state.active) {
    const notes = [];
    for (let i = firstOverlapping(layer,time); i < layer.notes.length; i++) {
      const note = layer.notes[i];
      if (note.start > until) break;
      if (!pitches.has(note.pitch) || note.end <= time) continue;
      notes.push(note);
      const current = lit.get(note.pitch);
      if (note.start <= time+1e-8 && (!current || (current.layer === layer && note.velocity >= current.velocity))) {
        const noteColor = noteColorOf(layer,note);
        lit.set(note.pitch,{layer,color:fx.layerKeys ? noteColor : keyColor,velocity:note.velocity,noteColor});
      }
    }
    if (notes.length) visible.push({layer,notes});
  }
  for (const preview of previews.values()) lit.set(preview.pitch,{color:keyColor,velocity:.8,noteColor:keyColor});

  ctx.save();
  ctx.beginPath();
  ctx.rect(padding,0,w-2*padding,impact+1);
  ctx.clip();
  if (fx.beams) {
    for (const [pitch,{noteColor,velocity}] of lit) {
      const slot = pitches.get(pitch);
      if (!slot) continue;
      const height = impact*(.18+.38*velocity);
      const width = Math.max(12,slot.width*3.4);
      const beam = ctx.createLinearGradient(0,impact-height,0,impact);
      beam.addColorStop(0,rgba(noteColor,0));
      beam.addColorStop(.7,rgba(noteColor,.08));
      beam.addColorStop(1,rgba(noteColor,.38));
      ctx.fillStyle = beam;
      ctx.beginPath();
      ctx.moveTo(slot.center-width*.08,impact-height);
      ctx.lineTo(slot.center+width*.08,impact-height);
      ctx.lineTo(slot.center+width*.5,impact);
      ctx.lineTo(slot.center-width*.5,impact);
      ctx.fill();
      ctx.fillStyle = gradient(ctx,slot.center,impact,Math.max(23,slot.width*3.2),noteColor,.46);
      ctx.fillRect(slot.center-width*1.5,impact-width*2,width*3,width*2);
    }
  }
  drawMidiLayers(visible,time,scale);
  if (fx.ripples && !media.matches) {
    for (const effect of flashes) {
      const slot = pitches.get(effect.pitch);
      const progress = (burstClock-effect.born)/.58;
      if (!slot || progress > 1) continue;
      const radius = 6 + progress*34 + effect.velocity*7;
      ctx.strokeStyle = rgba(effect.color,(1-progress)*.72);
      ctx.lineWidth = 1.15;
      ctx.beginPath();
      ctx.ellipse(slot.center,impact,radius,Math.max(1,radius*.35),0,Math.PI,Math.PI*2);
      ctx.stroke();
    }
  }
  if (fx.particles && !media.matches) {
    for (const particle of particles) {
      const slot = pitches.get(particle.pitch);
      const age = burstClock-particle.born;
      const progress = age/particle.lifetime;
      if (!slot || progress > 1) continue;
      const x = slot.center+particle.dx*age;
      const y = impact-1-particle.dy*age+48*age*age;
      const r = Math.max(.45,particle.size*(1-progress*.65));
      ctx.shadowColor = particle.color;
      ctx.shadowBlur = 9;
      ctx.fillStyle = rgba(particle.color, (1-progress)*.95);
      ctx.beginPath();
      ctx.arc(x,y,r,0,Math.PI*2);
      ctx.fill();
    }
    ctx.shadowBlur = 0;
  }
  ctx.restore();

  for (const slot of white) drawKey(slot,lit.get(slot.pitch));
  for (const slot of black) drawKey(slot,lit.get(slot.pitch));
  if (fx.strikeLine) {
    const colors = rollColors[state.style.theme];
    ctx.shadowColor = colors.line;
    ctx.shadowBlur = fx.ambient ? 10 : 0;
    ctx.fillStyle = fx.ambient ? colors.line : colors.mutedLine;
    ctx.fillRect(padding,impact-.5,w-2*padding,1.15);
    ctx.shadowBlur = 0;
  }
  if (fx.beams) {
    for (const [pitch,{noteColor}] of lit) {
      const slot = pitches.get(pitch);
      if (!slot) continue;
      ctx.fillStyle = gradient(ctx,slot.center,impact,Math.max(14,slot.width*2),noteColor,.88);
      ctx.fillRect(slot.center-28,impact-6,56,12);
      ctx.fillStyle = '#fff5fd';
      ctx.fillRect(slot.center-2,impact-1.2,4,1.9);
    }
  }
}

function updateWave() {
  waveBins = Array.from({length:220},()=>({ volume:0, peak:0, layer:null, note:null }));
  if (!state.duration) return;
  for (const layer of state.active) {
    for (const note of layer.notes) {
      const index = clamp(Math.floor(note.start/state.duration*waveBins.length),0,waveBins.length-1);
      const bin = waveBins[index];
      bin.volume += note.velocity;
      if (bin.peak < note.velocity) {
        bin.peak = note.velocity;
        bin.layer = layer;
        bin.note = note;
      }
    }
  }
}
function drawWave(time) {
  const {w,h,dpr} = resize(overview);
  const colors = rollColors[state.style.theme];
  waveCtx.setTransform(dpr,0,0,dpr,0,0);
  waveCtx.clearRect(0,0,w,h);
  waveCtx.fillStyle = colors.track;
  rounded(waveCtx,0,0,w,h,5);
  waveCtx.fill();
  const left = 6, available = Math.max(1,w-12);
  const step = available / Math.max(waveBins.length,1);
  const progress = state.duration ? (time/state.duration) : 0;
  if (state.duration) {
    waveCtx.fillStyle = rgba(colors.trace,.12);
    waveCtx.fillRect(left,0,progress*available,h);
  }
  waveCtx.fillStyle = rgba(colors.trace,.31);
  waveCtx.fillRect(left,h/2,available,1);
  for (let i = 0; i < waveBins.length; i++) {
    const bin = waveBins[i];
    if (!bin.layer) continue;
    const x = left + i*step;
    const height = Math.min(h-7,4+Math.log2(1+bin.volume)*12);
    waveCtx.fillStyle = rgba(noteColorOf(bin.layer,bin.note),i/waveBins.length < progress ? .96 : .57);
    waveCtx.fillRect(x,(h-height)/2,Math.max(.7,step-1.35),height);
  }
  if (state.duration) {
    const line = left+progress*available;
    waveCtx.fillStyle = colors.cursor;
    waveCtx.fillRect(line-1,2,2,h-4);
  }
}

sovietArtwork.onload = () => {
  backgroundRevision++;
  markDirty();
};
sovietArtwork.src = sovietArtworkSource;

let lastFrame = 0;
function markDirty() {
  if (!frame) frame = requestAnimationFrame(draw);
}
function draw(now) {
  frame = 0;
  const elapsed = lastFrame ? Math.min(.08,(now-lastFrame)/1000) : 0;
  lastFrame = now;
  const time = position();
  const animate = state.playing || now < animatePreviewUntil;
  if (animate) {
    burstClock += elapsed;
    particles = particles.filter(particle => burstClock-particle.born < particle.lifetime);
    flashes = flashes.filter(flash => burstClock-flash.born < .58);
  }
  if (state.playing) effectsAt(time);
  drawRoll(time);
  captureFrame(now);
  drawWave(time);
  updateTime(time);
  if (animate || recording?.phase === 'capturing') markDirty();
}
