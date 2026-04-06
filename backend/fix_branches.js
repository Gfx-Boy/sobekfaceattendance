const BASE = 'https://evrw6qmfh7.us-east-1.awsapprunner.com/api';

async function put(path, body) {
  const res = await fetch(`${BASE}${path}`, {
    method: 'PUT',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
  return res.status;
}

async function run() {
  const res = await fetch(`${BASE}/branches`);
  const branches = await res.json();
  console.log('Existing branches:');
  branches.forEach(b => console.log(`  ${b.id}  ${b.name}  ${b.address}  ${b.status}`));

  const b1 = branches.find(b => b.name === 'Branch1');
  const b2 = branches.find(b => b.name === 'Branch2');

  if (b1) {
    const status = await put(`/branches/${b1.id}`, {
      address: 'Cairo',
      status: 'hold',
      validity_start: '2025-03-28T00:00:00.000Z',
      validity_end: '2025-04-28T00:00:00.000Z',
      working_hours_start: '09:00',
      working_hours_end: '17:00',
      break_duration_minutes: 60,
    });
    console.log('Branch1 update:', status);
  }

  if (b2) {
    const status = await put(`/branches/${b2.id}`, {
      address: 'Alexandria',
      status: 'hold',
      validity_start: '2025-03-28T00:00:00.000Z',
      validity_end: '2025-04-28T00:00:00.000Z',
      working_hours_start: '07:00',
      working_hours_end: '18:00',
      break_duration_minutes: 30,
    });
    console.log('Branch2 update:', status);
  }

  // Fix employees whose branch_id might be wrong
  const empRes = await fetch(`${BASE}/employees`);
  const emps = await empRes.json();

  for (const emp of emps) {
    if (emp.branch_name === 'Branch1' && b1 && emp.branch_id !== b1.id) {
      console.log(`Fixing branch_id for ${emp.email}`);
      await put(`/employees/${emp.id}`, { branch_id: b1.id, branch_name: 'Branch1' });
    }
    if (emp.branch_name === 'Branch2' && b2 && emp.branch_id !== b2.id) {
      console.log(`Fixing branch_id for ${emp.email}`);
      await put(`/employees/${emp.id}`, { branch_id: b2.id, branch_name: 'Branch2' });
    }
  }

  console.log('Done!');
}

run().catch(e => { console.error(e.message); process.exit(1); });
