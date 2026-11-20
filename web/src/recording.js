let recording = null;
let exportedVideo = null;
let recordingMessage = '';
const captureRate = 30;
const captureTypes = ['video/webm;codecs=vp9,opus','video/webm;codecs=vp8,opus','video/webm','video/mp4',''];

function recordingSupported() {
  const AudioContext = window.AudioContext || window.webkitAudioContext;
  return typeof roll.captureStream === 'function' &&
    typeof window.MediaRecorder === 'function' &&
    typeof AudioContext?.prototype?.createMediaStreamDestination === 'function';
}

function updateRecordingUI() {
  const capturing = recording?.phase === 'capturing';
  const busy = Boolean(recording && !capturing);
  const control = $('record');
  const title = t(capturing ? 'stopRecording' : busy ? 'preparingVideo' : 'recordVideo');
  setIcon(control,capturing ? 'stop' : 'video',title);
  control.setAttribute('aria-pressed',Boolean(capturing));
  control.disabled = busy;
  $('recordLabel').textContent = t(capturing ? 'stop' : busy ? 'preparing' : 'video');
  $('recordingStatus').textContent = t(recordingMessage || (exportedVideo ? 'videoReady' : ''));
  $('recordingResult').hidden = Boolean(recording || (!recordingMessage && !exportedVideo));
  const download = $('downloadVideo');
  download.hidden = Boolean(recording || !exportedVideo);
  if (exportedVideo) {
    download.href = exportedVideo.url;
    download.download = exportedVideo.name;
  }
}

function captureFrame(now) {
  if (recording?.phase !== 'capturing' || now-recording.lastFrame < 1000/captureRate-1) return;
  const {canvas, context} = recording;
  const scale = Math.min(canvas.width/roll.width,canvas.height/roll.height);
  const width = roll.width*scale, height = roll.height*scale;
  context.fillStyle = '#000000';
  context.fillRect(0,0,canvas.width,canvas.height);
  context.drawImage(roll,(canvas.width-width)/2,(canvas.height-height)/2,width,height);
  recording.lastFrame = now;
}

function openMediaRecorder(stream) {
  const Recorder = window.MediaRecorder;
  let error;
  for (const mimeType of captureTypes) {
    if (mimeType && Recorder.isTypeSupported && !Recorder.isTypeSupported(mimeType)) continue;
    const options = {videoBitsPerSecond:4_000_000,audioBitsPerSecond:128_000};
    if (mimeType) options.mimeType = mimeType;
    try {
      const recorder = new Recorder(stream,options);
      recorder.start(1000);
      return recorder;
    } catch (reason) {
      error = reason;
    }
  }
  throw error || new LocalizedError('videoFormatUnavailable');
}

function releaseRecording(job) {
  if (job.output) {
    try { limiter.disconnect(job.output); } catch {}
  }
  const tracks = new Set([...(job.stream?.getTracks() || []),...(job.output?.stream.getTracks() || [])]);
  for (const track of tracks) track.stop();
}

function completeRecording(job) {
  if (recording !== job) return;
  releaseRecording(job);
  recording = null;
  recordingMessage = job.error || '';
  const type = job.recorder.mimeType || job.chunks.find(chunk=>chunk.type)?.type || 'video/webm';
  const blob = new Blob(job.chunks,{type});
  if (blob.size) {
    const url = URL.createObjectURL(blob);
    if (exportedVideo) URL.revokeObjectURL(exportedVideo.url);
    exportedVideo = {url,name:'our-pianoroll.'+(type.includes('mp4') ? 'mp4' : 'webm')};
  } else if (!recordingMessage) {
    recordingMessage = 'videoNoFrames';
  }
  job.chunks.length = 0;
  updateRecordingUI();
}

async function startRecording() {
  if (recording) return;
  if (!recordingSupported()) {
    recordingMessage = 'recordingUnavailable';
    updateRecordingUI();
    return;
  }
  const job = {phase:'starting',chunks:[],lastFrame:-Infinity};
  recording = job;
  recordingMessage = '';
  updateRecordingUI();
  try {
    initAudio();
    if (audio.state !== 'running') await audio.resume();
    if (!state.playing && state.duration && state.position >= state.duration-.01) jump(0);
    drawRoll(position());

    const scale = Math.min(1,1920/roll.width,1080/roll.height);
    job.canvas = document.createElement('canvas');
    job.canvas.width = Math.max(2,Math.floor(roll.width*scale/2)*2);
    job.canvas.height = Math.max(2,Math.floor(roll.height*scale/2)*2);
    job.context = job.canvas.getContext('2d',{alpha:false});
    job.output = audio.createMediaStreamDestination();
    job.stream = job.canvas.captureStream(captureRate);
    const audioTrack = job.output.stream.getAudioTracks()[0];
    if (!job.stream.getVideoTracks().length || !audioTrack) throw new LocalizedError('recordingTracksUnavailable');
    job.stream.addTrack(audioTrack);
    limiter.connect(job.output);

    const recorder = job.recorder = openMediaRecorder(job.stream);
    recorder.addEventListener('dataavailable',event => { if (event.data.size) job.chunks.push(event.data); });
    recorder.addEventListener('stop',() => completeRecording(job));
    recorder.addEventListener('error',() => {
      job.error = 'recordingInterrupted';
      if (recorder.state !== 'inactive') stopRecording();
    });
    job.phase = 'capturing';
    captureFrame(performance.now());
    updateRecordingUI();
    markDirty();
    play();
  } catch {
    if (job.recorder?.state === 'recording') {
      job.error = 'recordingContinueFailed';
      job.phase = 'capturing';
      stopRecording();
    } else {
      releaseRecording(job);
      recording = null;
      recordingMessage = 'recordingStartFailed';
      updateRecordingUI();
    }
  }
}

function stopRecording() {
  if (recording?.phase !== 'capturing') return;
  const job = recording;
  job.phase = 'stopping';
  updateRecordingUI();
  if (job.recorder.state !== 'inactive') {
    try { job.recorder.stop(); }
    catch { job.error = 'recordingStopFailed'; completeRecording(job); }
  }
}

function initRecording() {
  $('record').addEventListener('click',() => recording?.phase === 'capturing' ? stopRecording() : startRecording());
  updateRecordingUI();
}
