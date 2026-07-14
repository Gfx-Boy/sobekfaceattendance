/**
 * S3 Cleanup Script
 * Deletes ALL data from S3 except the Super Admin account (hasan@aenfinite.com)
 * — employee records, branches, attendance, tasks, requests, payslips,
 *   appraisals, notifications, settings, captured/profile/reference images, etc.
 *
 * SAFE BY DEFAULT: runs as a DRY RUN unless you pass --confirm.
 *
 * Usage:
 *   node cleanup_s3.js                       # dry run — lists what WOULD be deleted
 *   node cleanup_s3.js --confirm             # actually delete
 *   node cleanup_s3.js --bucket=NAME         # override bucket (else $S3_BUCKET_NAME)
 *
 * Auth: AWS SSO profile 'attendance' (run `aws sso login --profile attendance` first)
 *       or standard AWS_* env vars.
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

const argv = process.argv.slice(2);
const CONFIRM = argv.includes('--confirm');
const bucketArg = argv.find((a) => a.startsWith('--bucket='));

const s3ClientConfig = { region: process.env.AWS_REGION || 'us-east-1' };
if (!process.env.AWS_ACCESS_KEY_ID) {
  s3ClientConfig.credentials = fromSSO({ profile: process.env.AWS_PROFILE || 'attendance' });
}
const s3Client = new S3Client(s3ClientConfig);

// Bucket resolution: explicit flag > env var > the server's default (s3Service.js).
const BUCKET = (bucketArg ? bucketArg.split('=')[1] : process.env.S3_BUCKET_NAME) || 'face-attendance-images';
const SA_EMAIL = 'hasan@aenfinite.com';

// Roots that hold ALL application data.
// - data/             : all JSON records + profile images
// - reference-images/ : enrolled face photos
// - attendance-images/: captured face photos from each attendance punch
const ROOTS = ['data/', 'reference-images/', 'attendance-images/'];

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

// Group a key by its top-level data category, for a readable summary.
function categoryOf(key) {
  const m = key.match(/^(reference-images|data\/[^/]+)\//) || key.match(/^(data\/[^/]+\.json)$/);
  return m ? m[1] : key;
}

async function run() {
  console.log('=== S3 Cleanup Script ===');
  console.log(`Bucket:  ${BUCKET}`);
  console.log(`Keep:    Super Admin only (${SA_EMAIL})`);
  console.log(`Mode:    ${CONFIRM ? '*** LIVE — WILL DELETE ***' : 'DRY RUN (no changes; pass --confirm to delete)'}`);
  console.log('');

  // 1. Load the employees index and locate the SA — this also confirms we are
  //    pointed at the RIGHT bucket. Abort loudly if the SA is not present.
  const idx = await getJSON('data/employees-index.json');
  if (!idx) {
    console.error('ERROR: data/employees-index.json not found in this bucket.');
    console.error('       Wrong bucket, or empty bucket. Aborting to avoid touching the wrong data.');
    process.exit(1);
  }
  const saId = idx[SA_EMAIL];
  if (!saId) {
    console.error(`ERROR: Super Admin ${SA_EMAIL} not found in this bucket's index!`);
    console.error('       Refusing to run — this guards against wiping the wrong bucket.');
    console.error(`       Emails present: ${Object.keys(idx).join(', ')}`);
    process.exit(1);
  }
  console.log(`SA id:   ${saId}`);
  console.log(`Index:   ${Object.keys(idx).length} employee(s) currently`);
  console.log('');

  // 2. Build the keep-set: SA's own record + images. Everything else under the
  //    data roots gets removed. Images may have any extension, so match by id.
  const keepExact = new Set([
    `data/employees/employee-${saId}.json`,
    'data/employees-index.json', // rewritten below, never deleted
  ]);
  const isSaImage = (key) =>
    (key.startsWith('data/profile-images/') || key.startsWith('reference-images/')) &&
    key.includes(saId);

  // 3. Enumerate everything and partition into keep / delete.
  const allKeys = [];
  for (const root of ROOTS) allKeys.push(...await listAllKeys(root));

  const toDelete = [];
  const kept = [];
  for (const key of allKeys) {
    if (keepExact.has(key) || isSaImage(key)) kept.push(key);
    else toDelete.push(key);
  }

  // 4. Per-category summary.
  const byCat = {};
  for (const key of toDelete) byCat[categoryOf(key)] = (byCat[categoryOf(key)] || 0) + 1;
  console.log('--- Objects to delete (by category) ---');
  for (const cat of Object.keys(byCat).sort()) {
    console.log(`  ${String(byCat[cat]).padStart(6)}  ${cat}`);
  }
  console.log(`  ${'------'}`);
  console.log(`  ${String(toDelete.length).padStart(6)}  TOTAL to delete`);
  console.log('');
  console.log('--- Keeping ---');
  for (const key of kept) console.log(`  KEEP: ${key}`);
  console.log('');

  if (!CONFIRM) {
    console.log('DRY RUN complete. No changes made.');
    console.log('Re-run with --confirm to delete the above.');
    return;
  }

  // 5. Delete.
  let deleted = 0;
  for (const key of toDelete) {
    await deleteKey(key);
    deleted++;
    if (deleted % 50 === 0) console.log(`  ...deleted ${deleted}/${toDelete.length}`);
  }

  // 6. Rewrite the index to SA-only.
  await putJSON('data/employees-index.json', { [SA_EMAIL]: saId });

  console.log('');
  console.log('=== Cleanup Complete ===');
  console.log(`Deleted: ${deleted} object(s)`);
  console.log(`Remaining: SA record + SA images + SA-only index.`);
}

run().catch((err) => {
  const msg = err.message || String(err);
  if (/sso|token|expired|credential/i.test(msg)) {
    console.error('FATAL: AWS auth failed. Run:  aws sso login --profile attendance');
  }
  console.error('FATAL:', msg);
  process.exit(1);
});
