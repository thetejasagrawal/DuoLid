'use strict';
const video = document.querySelector('#demo');
const playButton = document.querySelector('#play-demo');
const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)');
function reflectPlayback() {
  playButton.textContent = video.paused ? 'Play the preview ▷' : 'Pause the preview Ⅱ';
  playButton.setAttribute('aria-pressed', String(!video.paused));
}
playButton.addEventListener('click', async () => {
  if (video.paused) {
    try { await video.play(); }
    catch { playButton.textContent = 'Use the video controls to play'; }
  } else video.pause();
});
video.addEventListener('play', reflectPlayback);
video.addEventListener('pause', reflectPlayback);
reflectPlayback();
// Never autoplay. An explicit play action also works with Reduce Motion enabled.
reducedMotion.addEventListener('change', event => { if (event.matches) video.pause(); });
document.addEventListener('visibilitychange', () => { if (document.hidden) video.pause(); });

async function loadRelease() {
  try {
    const response = await fetch('release.json', {cache: 'no-cache'});
    if (!response.ok) return;
    const release = await response.json();
    const expectedDownload = `https://github.com/thetejasagrawal/DuoLid/releases/download/v${release.version}/DuoLid-${release.version}.dmg`;
    const expectedNotes = `https://github.com/thetejasagrawal/DuoLid/releases/tag/v${release.version}`;
    if (release.status !== 'available' || !/^\d+\.\d+\.\d+(?:-beta\.\d+)?$/.test(release.version) ||
        release.download !== expectedDownload || release.notes !== expectedNotes) return;
    const download = document.querySelector('#download');
    download.href = release.download;
    download.textContent = `Download ${release.beta ? 'Beta' : 'DuoLid'} ↓`;
    const status = document.querySelector('#release-status');
    status.textContent = `${release.beta ? 'Beta' : 'Release'} ${release.version}`;
    status.href = release.notes;
    document.querySelector('#release-detail').textContent = `v${release.version} · macOS 14+ · Apple silicon & Intel`;
    document.querySelector('#release-note').textContent = 'Automatic effects require a compatible lid-angle sensor.';
    document.querySelector('#release-notes').href = release.notes;
    document.querySelector('#availability-answer').textContent = `DuoLid ${release.version} is available. Use the download button above. Review the compatibility notes before installing; ${release.beta ? 'this is a beta release.' : 'hardware sensor support varies.'}`;
  } catch {
    // Keep the valid source link and honest preparation state if metadata fails.
  }
}
loadRelease();
