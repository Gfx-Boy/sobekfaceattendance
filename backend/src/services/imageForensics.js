const Jimp = require('jimp');

/**
 * Pixel-level spoof forensics (#3 round 3 follow-up "more exception cases").
 * Complements the Rekognition checks with signals computed on the raw image:
 *  - perceptual hash: catches the SAME photo being reused across days
 *  - straight-edge scan: a phone/photo held to the camera leaves a long,
 *    high-contrast straight border in the frame (the "visuals around the
 *    picture") even when labels miss the device itself
 */

/** 16×16 average hash → 64-char hex string. */
async function perceptualHash(imagePath) {
  const img = await Jimp.read(imagePath);
  img.resize(16, 16).greyscale();
  const vals = [];
  for (let y = 0; y < 16; y++) {
    for (let x = 0; x < 16; x++) {
      vals.push(Jimp.intToRGBA(img.getPixelColor(x, y)).r);
    }
  }
  const mean = vals.reduce((s, v) => s + v, 0) / vals.length;
  let hex = '';
  for (let i = 0; i < 256; i += 4) {
    let nibble = 0;
    for (let b = 0; b < 4; b++) {
      if (vals[i + b] > mean) nibble |= 1 << (3 - b);
    }
    hex += nibble.toString(16);
  }
  return hex;
}

/** Hamming distance between two equal-length hex hashes (in bits). */
function hammingHex(a, b) {
  if (!a || !b || a.length !== b.length) return Infinity;
  let dist = 0;
  for (let i = 0; i < a.length; i++) {
    let x = parseInt(a[i], 16) ^ parseInt(b[i], 16);
    while (x) { dist += x & 1; x >>= 1; }
  }
  return dist;
}

/**
 * Detects a long, straight, high-contrast vertical or horizontal edge that
 * does not pass through the face — the typical border of a phone/photo held
 * up to the camera. Soft signal: real scenes have door frames too, so this
 * only counts combined with other suspicion.
 * faceBox is Rekognition-normalized {Left, Top, Width, Height}.
 */
async function straightEdgeSignal(imagePath, faceBox) {
  const img = await Jimp.read(imagePath);
  const W = 160;
  const H = Math.max(60, Math.round((img.getHeight() / img.getWidth()) * W));
  img.resize(W, H).greyscale();

  const lum = [];
  for (let y = 0; y < H; y++) {
    const row = [];
    for (let x = 0; x < W; x++) {
      row.push(Jimp.intToRGBA(img.getPixelColor(x, y)).r);
    }
    lum.push(row);
  }

  const fb = faceBox || { Left: 0.3, Top: 0.2, Width: 0.4, Height: 0.5 };
  const fx0 = Math.floor(fb.Left * W), fx1 = Math.ceil((fb.Left + fb.Width) * W);
  const fy0 = Math.floor(fb.Top * H), fy1 = Math.ceil((fb.Top + fb.Height) * H);

  const GRAD = 22;      // min per-pixel contrast step (0-255)
  const RUN = 0.62;     // fraction of the line that must hold the edge

  // vertical edges: column x with |L(x+1,y)-L(x-1,y)| strong for most rows
  for (let x = 2; x < W - 2; x++) {
    if (x >= fx0 && x <= fx1) continue; // skip through-face columns
    let strong = 0;
    for (let y = 0; y < H; y++) {
      if (Math.abs(lum[y][x + 1] - lum[y][x - 1]) / 2 >= GRAD) strong++;
    }
    if (strong / H >= RUN) return true;
  }
  // horizontal edges
  for (let y = 2; y < H - 2; y++) {
    if (y >= fy0 && y <= fy1) continue;
    let strong = 0;
    for (let x = 0; x < W; x++) {
      if (Math.abs(lum[y + 1][x] - lum[y - 1][x]) / 2 >= GRAD) strong++;
    }
    if (strong / W >= RUN) return true;
  }
  return false;
}

module.exports = { perceptualHash, hammingHex, straightEdgeSignal };
