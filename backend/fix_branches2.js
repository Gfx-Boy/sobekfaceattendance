const BASE = 'https://evrw6qmfh7.us-east-1.awsapprunner.com/api';

async function put(path, body) {
  const res = await fetch(`${BASE}${path}`, {
    method: 'PUT',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
  return { status: res.status, data: await res.json() };
}

async function run() {
  const res = await fetch(`${BASE}/branches`);
  const branches = await res.json();
  console.log('Current branches:');
  branches.forEach(b => console.log(`  ${b.id}  "${b.name}"  "${b.address}"  ${b.status}`));

  // Find by case-insensitive name
  const b1 = branches.find(b => b.name.toLowerCase() === 'branch1');
  const b2 = branches.find(b => b.name.toLowerCase() === 'branch2');
  const b3 = branches.find(b => b.name.toLowerCase() === 'branch3');

  console.log('\nUpdating branches...');

  if (b1) {
    const r = await put(`/branches/${b1.id}`, {
      name: 'Branch1',
      address: 'Cairo',
      status: 'hold',
      validity_start: '2025-03-28T00:00:00.000Z',
      validity_end: '2025-04-28T00:00:00.000Z',
      working_hours_start: '09:00',
      working_hours_end: '17:00',
      break_duration_minutes: 60,
    });
    console.log(`Branch1 (${b1.id}) update:`, r.status);
  }

  if (b2) {
    const r = await put(`/branches/${b2.id}`, {
      name: 'Branch2',
      address: 'Alexandria',
      status: 'hold',
      validity_start: '2025-03-28T00:00:00.000Z',
      validity_end: '2025-04-28T00:00:00.000Z',
      working_hours_start: '07:00',
      working_hours_end: '18:00',
      break_duration_minutes: 30,
    });
    console.log(`Branch2 (${b2.id}) update:`, r.status);
  }

  if (b3) {
    const r = await put(`/branches/${b3.id}`, {
      name: 'Branch3',
      address: '',
      status: 'work',
      working_hours_start: '09:00',
      working_hours_end: '18:00',
      break_duration_minutes: 60,
    });
    console.log(`Branch3 (${b3.id}) update:`, r.status);
  }

  // Fix employee branch assignments
  console.log('\nFixing employee branch assignments...');
  const empRes = await fetch(`${BASE}/employees`);
  const emps = await empRes.json();

  let fixed = 0;
  for (const emp of emps) {
    // Normalize branch name in employee to Title case
    const lbn = (emp.branch_name || '').toLowerCase();
    let targetBranch = null;
    if (lbn === 'branch1' && b1) targetBranch = { id: b1.id, name: 'Branch1' };
    else if (lbn === 'branch2' && b2) targetBranch = { id: b2.id, name: 'Branch2' };
    else if (lbn === 'branch3' && b3) targetBranch = { id: b3.id, name: 'Branch3' };

    if (targetBranch && (emp.branch_id !== targetBranch.id || emp.branch_name !== targetBranch.name)) {
      console.log(`  Fixing ${emp.email}: branch_id=${targetBranch.id}, name=${targetBranch.name}`);
      await put(`/employees/${emp.id}`, {
        branch_id: targetBranch.id,
        branch_name: targetBranch.name,
      });
      fixed++;
    }
  }
  console.log(`Fixed ${fixed} employees.`);
  console.log('\nDone!');
}

run().catch(e => { console.error(e.message); process.exit(1); });
