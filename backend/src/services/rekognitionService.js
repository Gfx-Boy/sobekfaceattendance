const {
  RekognitionClient,
  CompareFacesCommand,
  DetectFacesCommand,
  DetectLabelsCommand,
} = require('@aws-sdk/client-rekognition');
const fs = require('fs');

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
async function detectScreenSpoof(imageBytes, faceBox) {
  const response = await rekognitionClient.send(
    new DetectLabelsCommand({
      Image: { Bytes: imageBytes },
      MaxLabels: 35,
      MinConfidence: 60,
    })
  );

  for (const label of response.Labels || []) {
    if (!SPOOF_DEVICE_LABELS.has(label.Name)) continue;
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
  return { spoof: false };
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

module.exports = { compareFaces, detectLiveness };
