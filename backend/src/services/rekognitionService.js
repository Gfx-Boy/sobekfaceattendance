const {
  RekognitionClient,
  CompareFacesCommand,
  DetectFacesCommand,
  DetectLabelsCommand,
  CreateFaceLivenessSessionCommand,
  GetFaceLivenessSessionResultsCommand,
} = require('@aws-sdk/client-rekognition');
const fs = require('fs');
const { straightEdgeSignal } = require('./imageForensics');

// In production (AWS EC2/EB), the instance IAM role is used automatically.
// Locally, use the SSO profile via AWS_PROFILE env var or default profile.
const rekognitionClientConfig = { region: process.env.AWS_REGION || 'us-east-1' };
if (process.env.NODE_ENV !== 'production' && !process.env.AWS_ACCESS_KEY_ID) {
  const { fromSSO } = require('@aws-sdk/credential-providers');
  rekognitionClientConfig.credentials = fromSSO({ profile: process.env.AWS_PROFILE || 'attendance' });
}
const rekognitionClient = new RekognitionClient(rekognitionClientConfig);

const FACE_MATCH_THRESHOLD = parseFloat(process.env.FACE_MATCH_THRESHOLD || '90');

/**
 * Compare a captured face image against a reference image stored in S3.
 */
async function compareFaces(sourceImagePath, targetS3Bucket, targetS3Key) {
  const sourceBytes = fs.readFileSync(sourceImagePath);

  const command = new CompareFacesCommand({
    SourceImage: {
      Bytes: sourceBytes,
    },
    TargetImage: {
      S3Object: {
        Bucket: targetS3Bucket,
        Name: targetS3Key,
      },
    },
    SimilarityThreshold: FACE_MATCH_THRESHOLD,
  });

  const response = await rekognitionClient.send(command);

  if (response.FaceMatches && response.FaceMatches.length > 0) {
    const bestMatch = response.FaceMatches[0];
    return {
      matched: true,
      confidence: bestMatch.Similarity,
    };
  }

  return {
    matched: false,
    confidence: 0,
  };
}

// Objects that mean "this face is being shown ON something" when the face's
// bounding box falls inside theirs. Covers screens AND printed media
// (paper photo, poster, ID card) per the client's spoof report (#3 r3).
const SPOOF_DEVICE_LABELS = new Set([
  'Cell Phone',
  'Mobile Phone',
  'Phone',
  'Monitor',
  'Screen',
  'TV',
  'Television',
  'Laptop',
  'Computer',
  'Tablet Computer',
  'Computer Monitor',
  'LCD Screen',
  'Photo Frame',
  // Printed media
  'Poster',
  'Advertisement',
  'Photograph',
  'Painting',
  'Magazine',
  'Newspaper',
  'Id Cards',
  'Card',
  'Passport',
  'Document',
  'Picture Frame',
]);

/** Fraction of the face box covered by the device box (0..1). */
function faceCoveredByDevice(face, device) {
  const ix = Math.max(
    0,
    Math.min(face.Left + face.Width, device.Left + device.Width) -
      Math.max(face.Left, device.Left)
  );
  const iy = Math.max(
    0,
    Math.min(face.Top + face.Height, device.Top + device.Height) -
      Math.max(face.Top, device.Top)
  );
  const faceArea = face.Width * face.Height;
  return faceArea > 0 ? (ix * iy) / faceArea : 0;
}

/**
 * Screen/photo spoof check: DetectLabels finds phones/monitors/TVs WITH
 * bounding boxes. If the face sits inside such a device, the "person" is a
 * picture on a screen. A device elsewhere in the frame (e.g. a monitor in the
 * background of a real office) does NOT trigger this.
 */
// Labels that suggest a hand presenting something to the camera.
const HAND_LABELS = new Set(['Hand', 'Finger', 'Holding Hands', 'Fist', 'Wrist']);

async function detectScreenSpoof(imageBytes, faceBox) {
  const response = await rekognitionClient.send(
    new DetectLabelsCommand({
      Image: { Bytes: imageBytes },
      MaxLabels: 35,
      MinConfidence: 55,
    })
  );

  // Soft signals — each alone is not proof, but two together are (#3 r3):
  // a device/print label seen anywhere in the frame with high confidence,
  // and a hand presenting something while a device label is present.
  let frameLabel = null;
  let sawHand = false;
  let sawDevice = false;

  for (const label of response.Labels || []) {
    if (HAND_LABELS.has(label.Name) && label.Confidence >= 70) sawHand = true;
    if (!SPOOF_DEVICE_LABELS.has(label.Name)) continue;
    if (label.Confidence >= 70) sawDevice = true;
    if (label.Confidence >= 85) frameLabel = label.Name;
    for (const inst of label.Instances || []) {
      if (!inst.BoundingBox) continue;
      const covered = faceCoveredByDevice(faceBox, inst.BoundingBox);
      if (covered > 0.5) {
        console.log(
          `Screen spoof detected: face ${Math.round(covered * 100)}% inside a "${label.Name}" (conf ${label.Confidence?.toFixed(1)})`
        );
        return { spoof: true, device: label.Name };
      }
    }
  }
  return {
    spoof: false,
    softSignals: {
      frameLabel,                       // e.g. "Cell Phone" seen w/o box
      handDevice: sawHand && sawDevice, // a hand holding a device/print
    },
  };
}

/**
 * Detect faces in an image and check for liveness indicators.
 * Uses face detail attributes like eye open, mouth open, pose quality.
 */
async function detectLiveness(imagePath) {
  const imageBytes = fs.readFileSync(imagePath);

  const command = new DetectFacesCommand({
    Image: {
      Bytes: imageBytes,
    },
    Attributes: ['ALL'],
  });

  const response = await rekognitionClient.send(command);

  if (!response.FaceDetails || response.FaceDetails.length === 0) {
    return {
      isLive: false,
      message: 'No face detected in the image. Please ensure your face is clearly visible.',
    };
  }

  if (response.FaceDetails.length > 1) {
    return {
      isLive: false,
      message: 'Multiple faces detected. Please ensure only your face is visible.',
    };
  }

  const face = response.FaceDetails[0];

  // Screen/photo-of-photo rejection (client point: "check if the picture is
  // from a screen"). Runs before the quality scoring — a crisp photo of a
  // phone screen scores well on sharpness/brightness, so quality alone never
  // catches it. Fail-open on API errors: a DetectLabels outage must not lock
  // everyone out of attendance.
  try {
    const spoofCheck = await detectScreenSpoof(
      imageBytes,
      face.BoundingBox || { Left: 0, Top: 0, Width: 1, Height: 1 }
    );
    if (spoofCheck.spoof) {
      return {
        isLive: false,
        spoof: true,
        spoofDevice: spoofCheck.device,
        // Exact wording requested by the client (#3 r3).
        message: 'Alert: the image is not live',
      };
    }

    // Combine soft signals: any TWO of {device label seen frame-wide, hand
    // presenting a device, long straight border edge} → spoof. One alone can
    // happen in an honest office (a monitor behind you, a doorframe), two
    // together mean a picture is being held to the camera.
    const soft = spoofCheck.softSignals || {};
    let signals = 0;
    const hit = [];
    if (soft.frameLabel) { signals++; hit.push(`label:${soft.frameLabel}`); }
    if (soft.handDevice) { signals++; hit.push('hand+device'); }
    if (signals >= 1) {
      // Only pay the pixel-scan cost when at least one label signal fired.
      try {
        const edge = await straightEdgeSignal(imagePath, face.BoundingBox);
        if (edge) { signals++; hit.push('straight-edge'); }
      } catch (e) {
        console.error('Edge scan failed (continuing):', e.message);
      }
    }
    if (signals >= 2) {
      console.log(`Spoof (combined signals): ${hit.join(', ')}`);
      return {
        isLive: false,
        spoof: true,
        message: 'Alert: the image is not live',
      };
    }
    if (signals === 1) console.log(`Spoof signal (allowed, only one): ${hit.join(', ')}`);
  } catch (e) {
    console.error('Screen spoof check failed (continuing):', e.message);
  }

  const confidence = face.Confidence || 0;
  const eyesOpenValue = face.EyesOpen?.Value ?? false;
  const eyesOpenConf = face.EyesOpen?.Confidence ?? 0;
  const qualitySharpness = face.Quality?.Sharpness ?? 0;
  const qualityBrightness = face.Quality?.Brightness ?? 0;
  const boundingBox = face.BoundingBox || {};
  const faceArea = (boundingBox.Width || 0) * (boundingBox.Height || 0);

  // Log details for debugging
  console.log('Liveness check details:', {
    confidence: confidence.toFixed(1),
    eyesOpen: eyesOpenValue,
    eyesOpenConf: eyesOpenConf.toFixed(1),
    sharpness: qualitySharpness.toFixed(1),
    brightness: qualityBrightness.toFixed(1),
    faceArea: faceArea.toFixed(4),
  });

  // Scoring-based liveness check (more lenient for phone cameras)
  let score = 0;
  const reasons = [];

  // Face detection confidence (critical)
  if (confidence > 95) score += 3;
  else if (confidence > 85) score += 2;
  else if (confidence > 70) score += 1;
  else reasons.push('Low face detection confidence');

  // Eyes open (helpful but not always reliable on phone cameras)
  if (eyesOpenValue && eyesOpenConf > 70) score += 2;
  else if (eyesOpenValue) score += 1;
  else if (eyesOpenConf < 50) score += 1; // Uncertain — don't penalize

  // Image quality
  if (qualitySharpness > 30) score += 2;
  else if (qualitySharpness > 10) score += 1;
  else reasons.push('Image too blurry');

  if (qualityBrightness > 30) score += 2;
  else if (qualityBrightness > 10) score += 1;
  else reasons.push('Image too dark');

  // Face size — must be reasonably large (not a tiny face in background)
  if (faceArea > 0.03) score += 1;

  // Threshold: need at least 5 out of 10 possible points
  const isLive = score >= 5;

  console.log(`Liveness score: ${score}/10, isLive: ${isLive}`);

  return {
    isLive,
    confidence,
    eyesOpen: eyesOpenValue,
    sharpness: qualitySharpness,
    brightness: qualityBrightness,
    score,
    message: isLive
      ? 'Liveness check passed'
      : `Liveness check failed: ${reasons.length > 0 ? reasons.join(', ') : 'Please ensure good lighting and face the camera directly'}`,
  };
}

// ---------------------------------------------------------------------------
// Passive two-frame liveness (#3 round 3 follow-up)
//
// The app silently captures a second frame ~1s after the first. A photo held
// up to the camera (printed, or shown on another phone that fills the whole
// frame — the case DetectLabels cannot see) is a RIGID plane: between the two
// frames its yaw/pitch cannot change, its eyes cannot move, and its landmark
// geometry relative to the face box stays frozen. A live face always shows
// small non-rigid changes across a second. Thresholds are deliberately tight
// so a very still real person is never rejected; tune via env if needed.
const STATIC_LANDMARK_EPS = parseFloat(process.env.STATIC_LANDMARK_EPS || '0.004');
const STATIC_POSE_EPS = parseFloat(process.env.STATIC_POSE_EPS || '0.9');
const STATIC_EXPR_EPS = parseFloat(process.env.STATIC_EXPR_EPS || '1.5');

async function detectStaticSpoof(imagePathA, imagePathB) {
  const bytesA = fs.readFileSync(imagePathA);
  const bytesB = fs.readFileSync(imagePathB);

  // Byte-identical frames can only come from a replayed file, never a camera.
  if (bytesA.equals(bytesB)) {
    return { spoof: true, reason: 'identical frames' };
  }

  const detect = (bytes) =>
    rekognitionClient.send(new DetectFacesCommand({ Image: { Bytes: bytes }, Attributes: ['ALL'] }));
  const [ra, rb] = await Promise.all([detect(bytesA), detect(bytesB)]);
  const fa = ra.FaceDetails && ra.FaceDetails[0];
  const fb = rb.FaceDetails && rb.FaceDetails[0];
  // Face missing in the control frame — don't block (main pipeline already
  // validated frame A); fail open.
  if (!fa || !fb) return { spoof: false };

  // Run the screen/print label check on the second frame too — the attacker
  // may reveal the device edge only in one of the frames.
  try {
    const sc = await detectScreenSpoof(bytesB, fb.BoundingBox || { Left: 0, Top: 0, Width: 1, Height: 1 });
    if (sc.spoof) return { spoof: true, reason: `device in control frame (${sc.device})` };
  } catch (e) {
    console.error('Control-frame screen check failed (continuing):', e.message);
  }

  // Landmark constellation normalized to the face box — cancels out global
  // motion of the camera/photo, leaving only non-rigid facial change.
  const norm = (f) => {
    const bb = f.BoundingBox;
    const map = {};
    for (const l of f.Landmarks || []) {
      map[l.Type] = { x: (l.X - bb.Left) / bb.Width, y: (l.Y - bb.Top) / bb.Height };
    }
    return map;
  };
  const la = norm(fa);
  const lb = norm(fb);
  const deltas = [];
  for (const t of Object.keys(la)) {
    if (lb[t]) deltas.push(Math.hypot(la[t].x - lb[t].x, la[t].y - lb[t].y));
  }
  if (deltas.length < 5) return { spoof: false };
  const meanDelta = deltas.reduce((s, d) => s + d, 0) / deltas.length;

  const poseDelta =
    Math.abs((fa.Pose?.Yaw ?? 0) - (fb.Pose?.Yaw ?? 0)) +
    Math.abs((fa.Pose?.Pitch ?? 0) - (fb.Pose?.Pitch ?? 0));
  const eyeDelta = Math.abs((fa.EyesOpen?.Confidence ?? 0) - (fb.EyesOpen?.Confidence ?? 0));
  const mouthDelta = Math.abs((fa.MouthOpen?.Confidence ?? 0) - (fb.MouthOpen?.Confidence ?? 0));

  console.log('Static-spoof check:', {
    meanLandmarkDelta: meanDelta.toFixed(5),
    poseDelta: poseDelta.toFixed(2),
    eyeDelta: eyeDelta.toFixed(2),
    mouthDelta: mouthDelta.toFixed(2),
  });

  const rigid =
    meanDelta < STATIC_LANDMARK_EPS &&
    poseDelta < STATIC_POSE_EPS &&
    eyeDelta < STATIC_EXPR_EPS &&
    mouthDelta < STATIC_EXPR_EPS;

  return rigid ? { spoof: true, reason: 'static image (no facial motion between frames)' } : { spoof: false };
}

// ---------------------------------------------------------------------------
// AWS Rekognition Face Liveness (#3 final escalation): the app streams a
// short selfie-video challenge to AWS, which decides server-side whether a
// LIVE person is in front of the camera. Photos, screens, and prints cannot
// pass. The session's audit ReferenceImage is what we face-match against, so
// the identity is cryptographically bound to the live scan.
const LIVENESS_MIN_CONFIDENCE = parseFloat(process.env.LIVENESS_MIN_CONFIDENCE || '75');

async function createLivenessSession() {
  const res = await rekognitionClient.send(new CreateFaceLivenessSessionCommand({}));
  return res.SessionId;
}

/**
 * Returns { live, confidence, referenceImageBytes } for a completed session.
 * Throws if the session doesn't exist / isn't finished.
 */
async function getLivenessResult(sessionId) {
  const res = await rekognitionClient.send(
    new GetFaceLivenessSessionResultsCommand({ SessionId: sessionId })
  );
  const live =
    res.Status === 'SUCCEEDED' && (res.Confidence ?? 0) >= LIVENESS_MIN_CONFIDENCE;
  return {
    live,
    status: res.Status,
    confidence: res.Confidence ?? 0,
    referenceImageBytes: res.ReferenceImage?.Bytes || null,
  };
}

/** CompareFaces with raw bytes as the source (liveness reference image). */
async function compareFacesBytes(sourceBytes, targetS3Bucket, targetS3Key) {
  const command = new CompareFacesCommand({
    SourceImage: { Bytes: sourceBytes },
    TargetImage: { S3Object: { Bucket: targetS3Bucket, Name: targetS3Key } },
    SimilarityThreshold: FACE_MATCH_THRESHOLD,
  });
  const response = await rekognitionClient.send(command);
  if (response.FaceMatches && response.FaceMatches.length > 0) {
    return { matched: true, confidence: response.FaceMatches[0].Similarity };
  }
  return { matched: false, confidence: 0 };
}

module.exports = {
  compareFaces,
  compareFacesBytes,
  detectLiveness,
  detectStaticSpoof,
  createLivenessSession,
  getLivenessResult,
};
