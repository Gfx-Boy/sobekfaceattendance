/**
 * S3 Cleanup Script
 * Deletes ALL data from S3 except the Super Admin account (hasan@aenfinite.com)
 *
 * Usage: node cleanup_s3.js
 */
require('dotenv').config();
const {
  S3Client,
  ListObjectsV2Command,
  DeleteObjectCommand,
  GetObjectCommand,
  PutObjectCommand,
} = require('@aws-sdk/client-s3');
const { fromSSO } = require('@aws-sdk/credential-providers');

const s3Client = new S3Client({
  region: process.env.AWS_REGION || 'us-east-1',
  credentials: fromSSO({ profile: 'attendance' }),
});
const BUCKET = process.env.S3_BUCKET_NAME || 'face-attendance-images-phase1';
const SA_EMAIL = 'hasan@aenfinite.com';

async function getJSON(key) {
  try {
    const r = await s3Client.send(new GetObjectCommand({ Bucket: BUCKET, Key: key }));
    const chunks = [];
    for await (const c of r.Body) chunks.push(c);
    return JSON.parse(Buffer.concat(chunks).toString('utf-8'));
  } catch (e) {
    if (e.name === 'NoSuchKey') return null;
    throw e;
  }
}

async function putJSON(key, data) {
  await s3Client.send(new PutObjectCommand({
    Bucket: BUCKET, Key: key,
    Body: JSON.stringify(data), ContentType: 'application/json',
  }));
}

async function deleteKey(key) {
  await s3Client.send(new DeleteObjectCommand({ Bucket: BUCKET, Key: key }));
}

async function listAllKeys(prefix) {
  const keys = [];
  let token;
  do {
    const res = await s3Client.send(new ListObjectsV2Command({
      Bucket: BUCKET, Prefix: prefix, ContinuationToken: token,
    }));
    for (const obj of res.Contents || []) keys.push(obj.Key);
    token = res.IsTruncated ? res.NextContinuationToken : undefined;
  } while (token);
  return keys;
}

async function run() {
  console.log('=== S3 Cleanup Script ===');
  console.log(`Bucket: ${BUCKET}`);
  console.log(`Keeping only SA: ${SA_EMAIL}`);
  console.log('');

  // 1. Get current employees index
  const idx = await getJSON('data/employees-index.json');
  if (!idx) {
    console.error('ERROR: employees-index.json not found!');
    process.exit(1);
  }

  const saId = idx[SA_EMAIL];
  if (!saId) {
    console.error(`ERROR: SA account ${SA_EMAIL} not found in index!`);
    process.exit(1);
  }

  console.log(`SA ID: ${saId}`);
  const totalEmployees = Object.keys(idx).length;
  console.log(`Total employees in index: ${totalEmployees}`);
  console.log('');

  let deleted = 0;

  // 2. Delete all employee JSON files except SA
  console.log('--- Deleting employee records (except SA) ---');
  const empKeys = await listAllKeys('data/employees/');
  for (const key of empKeys) {
    if (key.includes(`employee-${saId}.json`)) {
      console.log(`  KEEPING: ${key}`);
      continue;
    }
    await deleteKey(key);
    console.log(`  Deleted: ${key}`);
    deleted++;
  }

  // 3. Rewrite the index with only SA
  console.log('\n--- Rewriting employees-index.json (SA only) ---');
  await putJSON('data/employees-index.json', { [SA_EMAIL]: saId });
  console.log('  Done');

  // 4. Delete all branches
  console.log('\n--- Deleting all branches ---');
  const branchKeys = await listAllKeys('data/branches/');
  for (const key of branchKeys) {
    await deleteKey(key);
    console.log(`  Deleted: ${key}`);
    deleted++;
  }

  // 5. Delete branch index
  console.log('\n--- Deleting branches-index.json ---');
  try {
    await deleteKey('data/branches-index.json');
    console.log('  Deleted: data/branches-index.json');
    deleted++;
  } catch (e) { console.log('  (not found, skipping)'); }

  // 6. Delete all tasks
  console.log('\n--- Deleting all tasks ---');
  for (const prefix of ['data/tasks/', 'data/tasks-by-employee/', 'data/tasks-by-assigner/']) {
    const keys = await listAllKeys(prefix);
    for (const key of keys) {
      await deleteKey(key);
      console.log(`  Deleted: ${key}`);
      deleted++;
    }
  }

  // 7. Delete all attendance records
  console.log('\n--- Deleting all attendance records ---');
  const attendKeys = await listAllKeys('data/attendance/');
  for (const key of attendKeys) {
    await deleteKey(key);
    console.log(`  Deleted: ${key}`);
    deleted++;
  }

  // 8. Delete all requests
  console.log('\n--- Deleting all requests ---');
  const requestKeys = await listAllKeys('data/requests/');
  for (const key of requestKeys) {
    await deleteKey(key);
    console.log(`  Deleted: ${key}`);
    deleted++;
  }

  // 9. Delete all payslips
  console.log('\n--- Deleting all payslips ---');
  const payslipKeys = await listAllKeys('data/payslips/');
  for (const key of payslipKeys) {
    await deleteKey(key);
    console.log(`  Deleted: ${key}`);
    deleted++;
  }

  // 10. Delete all appraisals
  console.log('\n--- Deleting all appraisals ---');
  const appraisalKeys = await listAllKeys('data/appraisals/');
  for (const key of appraisalKeys) {
    await deleteKey(key);
    console.log(`  Deleted: ${key}`);
    deleted++;
  }

  // 11. Delete all notifications
  console.log('\n--- Deleting all notifications ---');
  const notifKeys = await listAllKeys('data/notifications/');
  for (const key of notifKeys) {
    await deleteKey(key);
    console.log(`  Deleted: ${key}`);
    deleted++;
  }

  // 12. Delete all profile images (except SA's if any)
  console.log('\n--- Deleting all profile images ---');
  const profileImgKeys = await listAllKeys('data/profile-images/');
  for (const key of profileImgKeys) {
    if (key.includes(saId)) {
      console.log(`  KEEPING: ${key}`);
      continue;
    }
    await deleteKey(key);
    console.log(`  Deleted: ${key}`);
    deleted++;
  }

  // 13. Delete all reference images (except SA's if any)
  console.log('\n--- Deleting all reference images ---');
  const refImgKeys = await listAllKeys('reference-images/');
  for (const key of refImgKeys) {
    if (key.includes(saId)) {
      console.log(`  KEEPING: ${key}`);
      continue;
    }
    await deleteKey(key);
    console.log(`  Deleted: ${key}`);
    deleted++;
  }

  // 14. Also check and delete Rekognition face index data if stored in S3
  console.log('\n--- Checking for any other data folders ---');
  const allKeys = await listAllKeys('data/');
  const knownPrefixes = [
    'data/employees/', 'data/employees-index.json',
    'data/branches/', 'data/branches-index.json',
    'data/tasks/', 'data/tasks-by-employee/', 'data/tasks-by-assigner/',
    'data/attendance/', 'data/requests/', 'data/payslips/',
    'data/appraisals/', 'data/notifications/', 'data/profile-images/',
    'data/settings', 'data/dashboard',
  ];
  for (const key of allKeys) {
    const known = knownPrefixes.some(p => key.startsWith(p));
    if (!known) {
      console.log(`  Found unknown: ${key}`);
    }
  }

  console.log('\n=== Cleanup Complete ===');
  console.log(`Total objects deleted: ${deleted}`);
  console.log(`\nRemaining:`);
  console.log(`  SA employee: data/employees/employee-${saId}.json`);
  console.log(`  Index: data/employees-index.json (SA only)`);
  console.log('\nDone!');
}

run().catch(err => {
  console.error('FATAL:', err.message || err);
  process.exit(1);
});
