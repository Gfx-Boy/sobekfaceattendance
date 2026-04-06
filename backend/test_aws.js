require('dotenv').config();
const { S3Client, PutObjectCommand, ListObjectsV2Command } = require('@aws-sdk/client-s3');
const { RekognitionClient, DetectFacesCommand } = require('@aws-sdk/client-rekognition');

const creds = {
  accessKeyId: process.env.AWS_ACCESS_KEY_ID,
  secretAccessKey: process.env.AWS_SECRET_ACCESS_KEY,
};
if (process.env.AWS_SESSION_TOKEN) {
  creds.sessionToken = process.env.AWS_SESSION_TOKEN;
}

const region = 'us-east-1';
const s3 = new S3Client({ region, credentials: creds });
const rek = new RekognitionClient({ region, credentials: creds });
const bucket = process.env.S3_BUCKET_NAME;

(async () => {
  // Test S3 list
  try {
    const list = await s3.send(new ListObjectsV2Command({ Bucket: bucket, MaxKeys: 5 }));
    console.log('S3 ListObjects: OK, items:', list.KeyCount);
  } catch (e) {
    console.log('S3 List Error:', e.name, e.message);
  }

  // Test S3 upload
  try {
    await s3.send(new PutObjectCommand({
      Bucket: bucket,
      Key: 'test/connection-test.txt',
      Body: 'test',
      ContentType: 'text/plain',
    }));
    console.log('S3 Upload: OK');
  } catch (e) {
    console.log('S3 Upload Error:', e.name, e.message);
  }

  // Test Rekognition
  try {
    const buf = Buffer.from('/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRofHh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/2wBDAQkJCQwLDBgNDRgyIRwhMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjL/wAARCAABAAEDASIAAhEBAxEB/8QAFAABAAAAAAAAAAAAAAAAAAAAf/aAAwDAQACEQMRAD8AJQD/2Q==', 'base64');
    const res = await rek.send(new DetectFacesCommand({ Image: { Bytes: buf } }));
    console.log('Rekognition DetectFaces: OK (faces found:', res.FaceDetails?.length || 0, ')');
  } catch (e) {
    console.log('Rekognition Error:', e.name, '-', e.message?.substring(0, 100));
  }
})();
