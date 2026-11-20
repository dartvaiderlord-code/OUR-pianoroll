#!/usr/bin/env bash
set -euo pipefail
web_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd -- "$web_dir/src"
{
  cat markup.html
  printf '<style>\n'
  cat style.css
  printf '</style>\n'
  cat body.html
  printf '<script>\n'
  cat artwork.js i18n.js midi.js player.js visual.js recording.js app.js
  printf '</script>\n</body>\n</html>\n'
} > "$web_dir/index.html"
cp -- "$web_dir/index.html" "$web_dir/../native/assets/our-pianoroll.html"
