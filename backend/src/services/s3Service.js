const {
  S3Client,
  PutObjectCommand,
  GetObjectCommand,
  ListObjectsV2Command,
  DeleteObjectCommand,
} = require('@aws-sdk/client-s3');
const fs = require('fs');

// In production (AWS EC2/EB), the instance IAM role is used automatically.
// Locally, use the SSO profile via AWS_PROFILE env var or default profile.
const s3ClientConfig = { region: process.env.AWS_REGION || 'us-east-1' };
if (process.env.NODE_ENV !== 'production' && !process.env.AWS_ACCESS_KEY_ID) {
  const { fromSSO } = require('@aws-sdk/credential-providers');
  s3ClientConfig.credentials = fromSSO({ profile: process.env.AWS_PROFILE || 'attendance' });
}
const s3Client = new S3Client(s3ClientConfig);

const BUCKET_NAME = process.env.S3_BUCKET_NAME || 'face-attendance-images';

// ─── Error translation ───
function awsErrorMessage(error) {
  const code = error.Code || error.name || error.code || '';
  if (code === 'ExpiredToken' || code === 'ExpiredTokenException') {
    return 'AWS credentials have expired. Run: aws sso login --profile attendance';
  }
  if (code === 'AccessDenied' || error.message === 'Access Denied') {
    return 'AWS Access Denied. Add AmazonS3FullAccess + AmazonRekognitionFullAccess to the AttendancePermission set in IAM Identity Center.';
  }
  if (code === 'InvalidClientTokenId' || code === 'InvalidToken') {
    return 'Invalid AWS credentials. Run: aws sso login --profile attendance';
  }
  if (code === 'NoSuchBucket') {
    return `S3 bucket '${BUCKET_NAME}' does not exist. Check S3_BUCKET_NAME in .env`;
  }
  return error.message || 'Unknown AWS error';
}

// ─── Image helpers ───

async function uploadImage(filePath, key) {
  const fileContent = fs.readFileSync(filePath);
  await s3Client.send(
    new PutObjectCommand({
      Bucket: BUCKET_NAME,
      Key: key,
      Body: fileContent,
      ContentType: 'image/jpeg',
    }),
  );
  return `s3://${BUCKET_NAME}/${key}`;
}

async function getImageBuffer(key) {
  const response = await s3Client.send(
    new GetObjectCommand({ Bucket: BUCKET_NAME, Key: key }),
  );
  const chunks = [];
  for await (const chunk of response.Body) {
    chunks.push(chunk);
  }
  return Buffer.concat(chunks);
}

// ─── JSON data helpers ───

async function putJSON(key, data) {
  await s3Client.send(
    new PutObjectCommand({
      Bucket: BUCKET_NAME,
      Key: key,
      Body: JSON.stringify(data),
      ContentType: 'application/json',
    }),
  );
}

async function getJSON(key) {
  try {
    const response = await s3Client.send(
      new GetObjectCommand({ Bucket: BUCKET_NAME, Key: key }),
    );
    const chunks = [];
    for await (const chunk of response.Body) {
      chunks.push(chunk);
    }
    return JSON.parse(Buffer.concat(chunks).toString('utf-8'));
  } catch (err) {
    if (err.name === 'NoSuchKey' || err.$metadata?.httpStatusCode === 404) {
      return null;
    }
    throw err;
  }
}

async function deleteJSON(key) {
  await s3Client.send(
    new DeleteObjectCommand({ Bucket: BUCKET_NAME, Key: key }),
  );
}

async function listKeys(prefix) {
  const keys = [];
  let continuationToken;
  do {
    const response = await s3Client.send(
      new ListObjectsV2Command({
        Bucket: BUCKET_NAME,
        Prefix: prefix,
        ContinuationToken: continuationToken,
      }),
    );
    if (response.Contents) {
      for (const obj of response.Contents) {
        keys.push(obj.Key);
      }
    }
    continuationToken = response.NextContinuationToken;
  } while (continuationToken);
  return keys;
}

async function listJSON(prefix) {
  const keys = await listKeys(prefix);
  const results = [];
  for (const key of keys) {
    if (key.endsWith('.json')) {
      const data = await getJSON(key);
      if (data) results.push(data);
    }
  }
  return results;
}

module.exports = {
  uploadImage,
  getImageBuffer,
  putJSON,
  getJSON,
  deleteJSON,
  listKeys,
  listJSON,
  BUCKET_NAME,
  awsErrorMessage,
};
