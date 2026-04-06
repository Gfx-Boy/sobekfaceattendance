/**
 * Creates all test accounts by writing directly to S3 (bypasses HTTP API).
 * Same approach as create_admin.js script.
 * 
 * Usage: node create_test_accounts_direct.js
 * Requires: AWS SSO profile 'attendance' to be logged in
 */

require('dotenv').config();
const { v4: uuidv4 } = require('uuid');
const { fromSSO } = require('@aws-sdk/credential-providers');
const { S3Client, PutObjectCommand, GetObjectCommand, ListObjectsV2Command } = require('@aws-sdk/client-s3');
const bcrypt = require('bcryptjs');

const s3Client = new S3Client({
  region: process.env.AWS_REGION || 'us-east-1',
  credentials: fromSSO({ profile: 'attendance' }),
});
const BUCKET = process.env.S3_BUCKET_NAME || 'face-attendance-images-phase1';

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

// Branch definitions (with new IDs created by our previous API call)
const BRANCHES = [
  { id: 'b142615f-f013-4e40-acde-646688015cc7', name: 'Branch1', address: 'Branch 1 Office' },
  { id: '746ca038-3c19-42d7-8e40-9df3a0283967', name: 'Branch2', address: 'Branch 2 Office' },
  { id: 'ba91b4cb-089f-4a1e-87c9-7d048f730a76', name: 'Branch3', address: 'Branch 3 Office' },
];

// All 15 test accounts
const ACCOUNTS = [
  // Branch 1
  { name: 'Admin Branch 1', email: 'adminbranch1@outlook.com', password: 'adminbranch1', role: 'branchAdmin', department: 'Management', position: 'Branch Manager', branch_name: 'Branch1', employee_type: 'general' },
  { name: 'HR Branch 1', email: 'hrbranch1@outlook.com', password: 'hrbranch1', role: 'hr', department: 'Human Resources', position: 'HR Officer', branch_name: 'Branch1', employee_type: 'general' },
  { name: 'Sales Branch 1', email: 'salesbranch1@outlook.com', password: 'salesbranch1', role: 'employee', department: 'Sales', position: 'Sales Representative', branch_name: 'Branch1', employee_type: 'general' },
  { name: 'Accountant Branch 1', email: 'accountantbranch1@outlook.com', password: 'acountantbranch1', role: 'employee', department: 'Finance', position: 'Accountant', branch_name: 'Branch1', employee_type: 'general' },
  { name: 'Warehouse Branch 1', email: 'warebranch1@outlook.com', password: 'warebranch1', role: 'employee', department: 'Warehouse', position: 'Warehouse Staff', branch_name: 'Branch1', employee_type: 'warehouse' },
  // Branch 2
  { name: 'Admin Branch 2', email: 'adminbranch2@outlook.com', password: 'adminbranch2', role: 'branchAdmin', department: 'Management', position: 'Branch Manager', branch_name: 'Branch2', employee_type: 'general' },
  { name: 'HR Branch 2', email: 'hrbranch2@outlook.com', password: 'hrbranch2', role: 'hr', department: 'Human Resources', position: 'HR Officer', branch_name: 'Branch2', employee_type: 'general' },
  { name: 'Sales Branch 2', email: 'salesbranch2@outlook.com', password: 'salesbranch2', role: 'employee', department: 'Sales', position: 'Sales Representative', branch_name: 'Branch2', employee_type: 'general' },
  { name: 'Accountant Branch 2', email: 'accountantbranch2@outlook.com', password: 'acountantbranch2', role: 'employee', department: 'Finance', position: 'Accountant', branch_name: 'Branch2', employee_type: 'general' },
  { name: 'Warehouse Branch 2', email: 'warebranch2@outlook.com', password: 'warebranch2', role: 'employee', department: 'Warehouse', position: 'Warehouse Staff', branch_name: 'Branch2', employee_type: 'warehouse' },
  // Branch 3
  { name: 'Admin Branch 3', email: 'adminbranch3@outlook.com', password: 'adminbranch3', role: 'branchAdmin', department: 'Management', position: 'Branch Manager', branch_name: 'Branch3', employee_type: 'general' },
  { name: 'HR Branch 3', email: 'hrbranch3@outlook.com', password: 'hrbranch3', role: 'hr', department: 'Human Resources', position: 'HR Officer', branch_name: 'Branch3', employee_type: 'general' },
  { name: 'Sales Branch 3', email: 'salesbranch3@outlook.com', password: 'salesbranch3', role: 'employee', department: 'Sales', position: 'Sales Representative', branch_name: 'Branch3', employee_type: 'general' },
  { name: 'Accountant Branch 3', email: 'accountantbranch3@outlook.com', password: 'acountantbranch3', role: 'employee', department: 'Finance', position: 'Accountant', branch_name: 'Branch3', employee_type: 'general' },
  { name: 'Warehouse Branch 3', email: 'warebranch3@outlook.com', password: 'warebranch3', role: 'employee', department: 'Warehouse', position: 'Warehouse Staff', branch_name: 'Branch3', employee_type: 'warehouse' },
];

async function run() {
  console.log('Loading employee index...');
  let idx = (await getJSON('data/employees-index.json')) || {};
  console.log(`Current index: ${Object.keys(idx).length} entries`);

  // Ensure branch records exist in S3
  console.log('\n=== Verifying Branches in S3 ===');
  for (const b of BRANCHES) {
    const key = `data/branches/branch-${b.id}.json`;
    let existing = await getJSON(key);
    if (!existing) {
      existing = { id: b.id, name: b.name, address: b.address, admin_id: null, admin_name: '', is_active: true, employee_count: 0, created_at: new Date().toISOString() };
      await putJSON(key, existing);
      console.log(`✓ Branch created in S3: ${b.name} (${b.id})`);
    } else {
      console.log(`  Branch already in S3: ${b.name}`);
    }
  }

  const branchMap = {};
  for (const b of BRANCHES) branchMap[b.name] = b.id;

  console.log('\n=== Creating/Updating Employees ===');
  let created = 0, updated = 0, skipped = 0;

  for (const acc of ACCOUNTS) {
    const branchId = branchMap[acc.branch_name];
    const existingId = idx[acc.email];

    if (existingId) {
      // Employee exists - update their branch assignment and password
      const existing = await getJSON(`data/employees/employee-${existingId}.json`);
      if (existing) {
        let changed = false;
        if (!existing.branch_id || existing.branch_id !== branchId) {
          existing.branch_id = branchId;
          existing.branch_name = acc.branch_name;
          changed = true;
        }
        if (!existing.password_hash) {
          existing.password_hash = await bcrypt.hash(acc.password, 10);
          changed = true;
        }
        if (existing.role !== acc.role) {
          existing.role = acc.role;
          changed = true;
        }
        if (changed) {
          existing.updated_at = new Date().toISOString();
          await putJSON(`data/employees/employee-${existingId}.json`, existing);
          console.log(`↑ Updated: ${acc.email} → branch: ${acc.branch_name}, role: ${acc.role}`);
          updated++;
        } else {
          console.log(`  Unchanged: ${acc.email}`);
          skipped++;
        }
        // Update branch admin_id if this is a branchAdmin
        if (acc.role === 'branchAdmin' && branchId) {
          const branchData = await getJSON(`data/branches/branch-${branchId}.json`);
          if (branchData && branchData.admin_id !== existingId) {
            branchData.admin_id = existingId;
            branchData.admin_name = acc.name;
            branchData.updated_at = new Date().toISOString();
            await putJSON(`data/branches/branch-${branchId}.json`, branchData);
          }
        }
      }
    } else {
      // Create new employee
      const id = uuidv4();
      const employee = {
        id, name: acc.name, email: acc.email,
        department: acc.department, role: acc.role,
        employee_type: acc.employee_type, position: acc.position,
        branch_id: branchId, branch_name: acc.branch_name,
        phone: '', address: '',
        profile_image_url: '', reference_image_key: '', reference_image_url: '',
        password_hash: await bcrypt.hash(acc.password, 10),
        created_at: new Date().toISOString(),
      };

      await putJSON(`data/employees/employee-${id}.json`, employee);
      idx[acc.email] = id;
      console.log(`✓ Created: ${acc.email} (${acc.role}, ${acc.branch_name})`);
      created++;

      // Update branch admin_id if branchAdmin
      if (acc.role === 'branchAdmin' && branchId) {
        const branchData = await getJSON(`data/branches/branch-${branchId}.json`);
        if (branchData) {
          branchData.admin_id = id;
          branchData.admin_name = acc.name;
          branchData.updated_at = new Date().toISOString();
          await putJSON(`data/branches/branch-${branchId}.json`, branchData);
        }
      }
    }
  }

  // Save updated index
  await putJSON('data/employees-index.json', idx);
  console.log('\n✓ Employee index saved');

  console.log(`\n=== Result ===`);
  console.log(`Created : ${created}`);
  console.log(`Updated : ${updated}`);
  console.log(`Skipped : ${skipped}`);

  console.log('\n=== Account List ===');
  console.log('Email                                    | Password             | Role         | Branch');
  console.log('─'.repeat(95));
  console.log(`${'hasan@aenfinite.com'.padEnd(40)} | ${'admin123'.padEnd(20)} | ${'superAdmin'.padEnd(12)} | Head Office`);
  for (const acc of ACCOUNTS) {
    console.log(`${acc.email.padEnd(40)} | ${acc.password.padEnd(20)} | ${acc.role.padEnd(12)} | ${acc.branch_name}`);
  }
}

run().catch(e => {
  console.error('\n✗ Script failed:', e.message);
  process.exit(1);
});
