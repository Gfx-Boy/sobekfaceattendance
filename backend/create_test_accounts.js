/**
 * Creates all test accounts for branches 1, 2, 3.
 * Run AFTER deploying the backend, using the HTTP API.
 *
 * Usage: node create_test_accounts.js
 * Requires: npm install node-fetch (or use built-in if Node 18+)
 */

const BASE_URL = 'https://evrw6qmfh7.us-east-1.awsapprunner.com/api';

const accounts = [
  // ── Branch 1 ──────────────────────────────────────────────────
  {
    name: 'Admin Branch 1', email: 'adminbranch1@outlook.com',
    password: 'adminbranch1', role: 'branchAdmin',
    department: 'Management', position: 'Branch Manager',
    branch_name: 'Branch1', employee_type: 'general',
  },
  {
    name: 'HR Branch 1', email: 'hrbranch1@outlook.com',
    password: 'hrbranch1', role: 'hr',
    department: 'HR', position: 'HR Officer',
    branch_name: 'Branch1', employee_type: 'general',
  },
  {
    name: 'Sales Branch 1', email: 'salesbranch1@outlook.com',
    password: 'salesbranch1', role: 'employee',
    department: 'sales', position: 'Sales Representative',
    branch_name: 'Branch1', employee_type: 'general',
  },
  {
    name: 'Accountant Branch 1', email: 'accountantbranch1@outlook.com',
    password: 'acountantbranch1', role: 'employee',
    department: 'accountant', position: 'Accountant',
    branch_name: 'Branch1', employee_type: 'general',
  },
  {
    name: 'Warehouse Branch 1', email: 'warebranch1@outlook.com',
    password: 'warebranch1', role: 'employee',
    department: 'warehouse', position: 'Warehouse Staff',
    branch_name: 'Branch1', employee_type: 'general',
  },

  // ── Branch 2 ──────────────────────────────────────────────────
  {
    name: 'Admin Branch 2', email: 'adminbranch2@outlook.com',
    password: 'adminbranch2', role: 'branchAdmin',
    department: 'Management', position: 'Branch Manager',
    branch_name: 'Branch2', employee_type: 'general',
  },
  {
    name: 'HR Branch 2', email: 'hrbranch2@outlook.com',
    password: 'hrbranch2', role: 'hr',
    department: 'HR', position: 'HR Officer',
    branch_name: 'Branch2', employee_type: 'general',
  },
  {
    name: 'Sales Branch 2', email: 'salesbranch2@outlook.com',
    password: 'salesbranch2', role: 'employee',
    department: 'sales', position: 'Sales Representative',
    branch_name: 'Branch2', employee_type: 'general',
  },
  {
    name: 'Accountant Branch 2', email: 'accountantbranch2@outlook.com',
    password: 'acountantbranch2', role: 'employee',
    department: 'accountant', position: 'Accountant',
    branch_name: 'Branch2', employee_type: 'general',
  },
  {
    name: 'Warehouse Branch 2', email: 'warebranch2@outlook.com',
    password: 'warebranch2', role: 'employee',
    department: 'warehouse', position: 'Warehouse Staff',
    branch_name: 'Branch2', employee_type: 'general',
  },

  // ── Branch 3 ──────────────────────────────────────────────────
  {
    name: 'Admin Branch 3', email: 'adminbranch3@outlook.com',
    password: 'adminbranch3', role: 'branchAdmin',
    department: 'Management', position: 'Branch Manager',
    branch_name: 'Branch3', employee_type: 'general',
  },
  {
    name: 'HR Branch 3', email: 'hrbranch3@outlook.com',
    password: 'hrbranch3', role: 'hr',
    department: 'HR', position: 'HR Officer',
    branch_name: 'Branch3', employee_type: 'general',
  },
  {
    name: 'Sales Branch 3', email: 'salesbranch3@outlook.com',
    password: 'salesbranch3', role: 'employee',
    department: 'sales', position: 'Sales Representative',
    branch_name: 'Branch3', employee_type: 'general',
  },
  {
    name: 'Accountant Branch 3', email: 'accountantbranch3@outlook.com',
    password: 'acountantbranch3', role: 'employee',
    department: 'accountant', position: 'Accountant',
    branch_name: 'Branch3', employee_type: 'general',
  },
  {
    name: 'Warehouse Branch 3', email: 'warebranch3@outlook.com',
    password: 'warebranch3', role: 'employee',
    department: 'warehouse', position: 'Warehouse Staff',
    branch_name: 'Branch3', employee_type: 'general',
  },
];

// Branch1: Cairo, On Hold, 3/28-4/28, 9:00-17:00, 60min break
// Branch2: Alexandria, On Hold, 3/28-4/28, 7:00-18:00, 30min break
// Branch3: no specific location
const branches = [
  {
    name: 'Branch1',
    address: 'Cairo',
    status: 'hold',
    validity_start: '2025-03-28T00:00:00.000Z',
    validity_end: '2025-04-28T00:00:00.000Z',
    working_hours_start: '09:00',
    working_hours_end: '17:00',
    break_duration_minutes: 60,
  },
  {
    name: 'Branch2',
    address: 'Alexandria',
    status: 'hold',
    validity_start: '2025-03-28T00:00:00.000Z',
    validity_end: '2025-04-28T00:00:00.000Z',
    working_hours_start: '07:00',
    working_hours_end: '18:00',
    break_duration_minutes: 30,
  },
  {
    name: 'Branch3',
    address: '',
    status: 'work',
    working_hours_start: '09:00',
    working_hours_end: '18:00',
    break_duration_minutes: 60,
  },
];

async function post(path, body) {
  const res = await fetch(`${BASE_URL}${path}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
  return { status: res.status, data: await res.json() };
}

async function run() {
  console.log('=== Creating Branches ===');
  const branchIdMap = {};

  for (const b of branches) {
    const r = await post('/branches', b);
    if (r.status === 201) {
      branchIdMap[b.name] = r.data.id;
      console.log(`✓ Branch created: ${b.name} (id: ${r.data.id})`);
    } else if (r.status === 409) {
      // Already exists - try to find it
      console.log(`⚠ Branch already exists: ${b.name} (${r.data.error})`);
      // Fetch all branches to find the ID
      const listRes = await fetch(`${BASE_URL}/branches`);
      const list = await listRes.json();
      const found = list.find(br => br.name === b.name);
      if (found) {
        branchIdMap[b.name] = found.id;
        console.log(`  → Found existing branch id: ${found.id}`);
      }
    } else {
      console.log(`✗ Failed to create branch ${b.name}: ${JSON.stringify(r.data)}`);
    }
  }

  console.log('\n=== Creating Employee Accounts ===');
  const results = [];

  for (const acc of accounts) {
    const branchId = branchIdMap[acc.branch_name];
    const payload = {
      name: acc.name,
      email: acc.email,
      password: acc.password,
      role: acc.role,
      department: acc.department,
      position: acc.position,
      branch_id: branchId || null,
      branch_name: acc.branch_name,
      employee_type: acc.employee_type,
    };

    const r = await post('/employees', payload);
    if (r.status === 201) {
      console.log(`✓ Created: ${acc.email} (${acc.role}, ${acc.branch_name})`);
      results.push({ email: acc.email, status: 'created', id: r.data.id });
    } else if (r.status === 409) {
      console.log(`⚠ Already exists: ${acc.email}`);
      results.push({ email: acc.email, status: 'already_exists' });
    } else {
      console.log(`✗ Failed: ${acc.email} — ${JSON.stringify(r.data)}`);
      results.push({ email: acc.email, status: 'failed', error: r.data });
    }
  }

  console.log('\n=== Summary ===');
  console.log(`Created : ${results.filter(r => r.status === 'created').length}`);
  console.log(`Existing: ${results.filter(r => r.status === 'already_exists').length}`);
  console.log(`Failed  : ${results.filter(r => r.status === 'failed').length}`);
  console.log('\n=== All Accounts ===');
  for (const acc of accounts) {
    console.log(`  ${acc.email.padEnd(40)} | ${acc.password.padEnd(20)} | ${acc.role.padEnd(12)} | ${acc.branch_name}`);
  }
}

run().catch(e => {
  console.error('Script failed:', e.message);
  process.exit(1);
});
