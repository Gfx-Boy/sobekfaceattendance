require('dotenv').config();
const { v4: uuidv4 } = require('uuid');
const { fromSSO } = require('@aws-sdk/credential-providers');
const { S3Client, PutObjectCommand, GetObjectCommand } = require('@aws-sdk/client-s3');

const s3Client = new S3Client({
  region: process.env.AWS_REGION || 'us-east-1',
  credentials: fromSSO({ profile: 'attendance' }),
});
const BUCKET = process.env.S3_BUCKET_NAME || 'face-attendance-images';

async function putJSON(key, data) {
  await s3Client.send(new PutObjectCommand({
    Bucket: BUCKET, Key: key,
    Body: JSON.stringify(data), ContentType: 'application/json',
  }));
}
async function getJSON(key) {
  try {
    const r = await s3Client.send(new GetObjectCommand({ Bucket: BUCKET, Key: key }));
    const chunks = []; for await (const c of r.Body) chunks.push(c);
    return JSON.parse(Buffer.concat(chunks).toString('utf-8'));
  } catch (e) { if (e.name === 'NoSuchKey') return null; throw e; }
}

const adminId = uuidv4();

const admin = {
  id: adminId,
  name: 'Hasan',
  email: 'hasan@aenfinite.com',
  department: 'Management',
  role: 'superAdmin',
  employee_type: 'general',
  position: 'Super Administrator',
  branch_id: 'main',
  branch_name: 'Head Office',
  phone: '',
  address: '',
  profile_image_url: '',
  reference_image_key: '',
  reference_image_url: '',
  created_at: new Date().toISOString(),
};

async function run() {
  console.log('Creating admin user...');

  // Wait a moment for the S3 probe to finish
  await new Promise(r => setTimeout(r, 2000));

  // Save employee record
  await putJSON(`data/employees/employee-${adminId}.json`, admin);
  console.log('✓ Employee record saved. ID:', adminId);

  // Read existing index or start fresh
  let idx = (await getJSON('data/employees-index.json')) || {};
  console.log('Index has', Object.keys(idx).length, 'entries');

  idx['hasan@aenfinite.com'] = adminId;

  await putJSON('data/employees-index.json', idx);

  console.log('✓ Index updated');
  console.log('');
  console.log('=== ADMIN CREATED ===');
  console.log('Email   : hasan@aenfinite.com');
  console.log('Role    : superAdmin');
  console.log('ID      :', adminId);
  console.log('=====================');
}

run().catch(e => {
  console.error('FAILED:', e.message);
  process.exit(1);
});
