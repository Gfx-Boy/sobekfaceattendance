const express = require('express');
const { v4: uuidv4 } = require('uuid');
const { putJSON, getJSON, listJSON, listKeys, deleteJSON } = require('../services/s3Service');

const router = express.Router();

const branchKey = (id) => `data/branches/branch-${id}.json`;

// POST /api/branches — create a branch
router.post('/', async (req, res) => {
  try {
    const { name, address, admin_id, admin_name, is_active, status, validity_start, validity_end, working_hours_start, working_hours_end, break_duration_minutes, working_days, deduction_late, deduction_early_out, deduction_absent, weekend_days } = req.body;

    if (!name) {
      return res.status(400).json({ error: 'Branch name is required' });
    }

    // Uniqueness check
    const existingKeys = await listKeys('data/branches/');
    for (const key of existingKeys) {
      if (key.endsWith('.json')) {
        const existing = await getJSON(key);
        if (existing && existing.name && existing.name.toLowerCase() === name.toLowerCase()) {
          return res.status(409).json({ error: 'A branch with this name already exists' });
        }
      }
    }

    const id = uuidv4();
    const branch = {
      id,
      name,
      address: address || '',
      admin_id: admin_id || null,
      admin_name: admin_name || '',
      is_active: is_active !== false,
      status: status || 'work', // work | hold | closed
      validity_start: validity_start || null,
      validity_end: validity_end || null,
      working_hours_start: working_hours_start || '09:00',
      working_hours_end: working_hours_end || '18:00',
      break_duration_minutes: break_duration_minutes || 60,
      working_days: working_days || ['Monday','Tuesday','Wednesday','Thursday','Friday'],
      weekend_days: weekend_days || ['Friday', 'Saturday'],
      deduction_late: deduction_late || 0,
      deduction_early_out: deduction_early_out || 0,
      deduction_absent: deduction_absent || 0,
      employee_count: 0,
      created_at: new Date().toISOString(),
    };

    await putJSON(branchKey(id), branch);
    res.status(201).json(branch);
  } catch (error) {
    console.error('Create branch error:', error);
    res.status(500).json({ error: 'Failed to create branch' });
  }
});

// GET /api/branches — list all branches
router.get('/', async (req, res) => {
  try {
    const keys = await listKeys('data/branches/');
    const branches = [];
    for (const key of keys) {
      if (key.endsWith('.json')) {
        const branch = await getJSON(key);
        if (!branch) continue;
        // Ensure id is always set — derive from key as fallback for old records
        if (!branch.id) {
          branch.id = key.replace('data/branches/branch-', '').replace('.json', '');
        }
        branches.push(branch);
      }
    }

    // Compute employee_count dynamically from active employees
    try {
      const empKeys = await listKeys('data/employees/');
      const counts = {};
      let total = 0;
      let noBranch = 0;
      for (const k of empKeys) {
        if (!k.endsWith('.json')) continue;
        if (!k.includes('/employee-')) continue;
        let emp;
        try {
          emp = await getJSON(k);
        } catch (readErr) {
          console.warn(`[branches] skip corrupt employee file ${k}:`, readErr.message);
          continue;
        }
        if (!emp) continue;
        total += 1;
        const bId = emp.branch_id;
        if (!bId) { noBranch += 1; continue; }
        counts[bId] = (counts[bId] || 0) + 1;
      }
      const branchIds = branches.map(b => b.id);
      console.log(`[branches] total=${total} noBranch=${noBranch} countKeys=${JSON.stringify(Object.keys(counts))} branchIds=${JSON.stringify(branchIds)}`);
      for (const b of branches) {
        b.employee_count = counts[b.id] || 0;
      }
    } catch (e) {
      console.error('Employee count listKeys failed:', e);
    }

    res.json(branches);
  } catch (error) {
    console.error('List branches error:', error);
    res.status(500).json({ error: 'Failed to list branches' });
  }
});

// GET /api/branches/:id
router.get('/:id', async (req, res) => {
  try {
    const branch = await getJSON(branchKey(req.params.id));
    if (!branch) return res.status(404).json({ error: 'Branch not found' });
    res.json(branch);
  } catch (error) {
    console.error('Get branch error:', error);
    res.status(500).json({ error: 'Failed to get branch' });
  }
});

// PUT /api/branches/:id
router.put('/:id', async (req, res) => {
  try {
    const branch = await getJSON(branchKey(req.params.id));
    if (!branch) return res.status(404).json({ error: 'Branch not found' });

    const { name, address, admin_id, admin_name, is_active, status, validity_start, validity_end, working_hours_start, working_hours_end, break_duration_minutes, working_days, deduction_late, deduction_early_out, deduction_absent, weekend_days } = req.body;

    // If renaming, check uniqueness
    if (name !== undefined && name.toLowerCase() !== (branch.name || '').toLowerCase()) {
      const existingKeys = await listKeys('data/branches/');
      for (const key of existingKeys) {
        if (key.endsWith('.json')) {
          const existing = await getJSON(key);
          if (existing && existing.id !== req.params.id && existing.name && existing.name.toLowerCase() === name.toLowerCase()) {
            return res.status(409).json({ error: 'A branch with this name already exists' });
          }
        }
      }
    }

    if (name !== undefined) branch.name = name;
    if (address !== undefined) branch.address = address;
    if (admin_id !== undefined) branch.admin_id = admin_id;
    if (admin_name !== undefined) branch.admin_name = admin_name;
    if (is_active !== undefined) branch.is_active = is_active;
    if (status !== undefined) branch.status = status;
    if (validity_start !== undefined) branch.validity_start = validity_start;
    if (validity_end !== undefined) branch.validity_end = validity_end;
    if (working_hours_start !== undefined) branch.working_hours_start = working_hours_start;
    if (working_hours_end !== undefined) branch.working_hours_end = working_hours_end;
    if (break_duration_minutes !== undefined) branch.break_duration_minutes = break_duration_minutes;
    if (working_days !== undefined) branch.working_days = working_days;
    if (deduction_late !== undefined) branch.deduction_late = deduction_late;
    if (deduction_early_out !== undefined) branch.deduction_early_out = deduction_early_out;
    if (deduction_absent !== undefined) branch.deduction_absent = deduction_absent;
    if (weekend_days !== undefined) branch.weekend_days = weekend_days;
    branch.updated_at = new Date().toISOString();
    console.log(`[branches] PUT ${req.params.id} saved working_days=${JSON.stringify(branch.working_days)} deductions=${branch.deduction_late}/${branch.deduction_early_out}/${branch.deduction_absent}`);

    await putJSON(branchKey(req.params.id), branch);
    res.json(branch);
  } catch (error) {
    console.error('Update branch error:', error);
    res.status(500).json({ error: 'Failed to update branch' });
  }
});

// DELETE /api/branches/:id — cascade-delete employees in the branch
router.delete('/:id', async (req, res) => {
  try {
    const branch = await getJSON(branchKey(req.params.id));
    if (!branch) return res.status(404).json({ error: 'Branch not found' });

    // Cascade-delete employees belonging to this branch so they don't
    // become orphans visible under other branches.
    let removedEmployees = 0;
    const removedEmails = [];
    try {
      const empKeys = await listKeys('data/employees/');
      for (const k of empKeys) {
        if (!k.endsWith('.json')) continue;
        if (!k.includes('/employee-')) continue;
        const emp = await getJSON(k);
        if (!emp) continue;
        if (emp.branch_id === req.params.id) {
          await deleteJSON(k);
          removedEmployees += 1;
          if (emp.email) removedEmails.push(emp.email);
        }
      }
      // Purge deleted emails from the employees-index so logins can't resolve them
      if (removedEmails.length > 0) {
        try {
          const idx = (await getJSON('data/employees-index.json')) || {};
          for (const email of removedEmails) {
            delete idx[email];
          }
          await putJSON('data/employees-index.json', idx);
        } catch (e) {
          console.error('Failed to update employees-index after cascade:', e);
        }
      }
    } catch (e) {
      console.error('Cascade employee delete failed:', e);
    }

    await deleteJSON(branchKey(req.params.id));
    res.json({ message: 'Branch deleted', removed_employees: removedEmployees });
  } catch (error) {
    console.error('Delete branch error:', error);
    res.status(500).json({ error: 'Failed to delete branch' });
  }
});

// POST /api/branches/:id/day-status
// Apply a day status (vacation/holiday/absent/attend) to every active
// employee in the branch for a given date. Used by Branch Admin (#27).
router.post('/:id/day-status', async (req, res) => {
  try {
    const branch = await getJSON(branchKey(req.params.id));
    if (!branch) return res.status(404).json({ error: 'Branch not found' });

    const { date, status, applied_by } = req.body;
    if (!date || !status) {
      return res.status(400).json({ error: 'date and status are required' });
    }
    if (!['vacation', 'holiday', 'absent', 'attend', 'permission', 'business_mission'].includes(status)) {
      return res.status(400).json({ error: 'Invalid status' });
    }

    const empKeys = await listKeys('data/employees/');
    let count = 0;
    for (const k of empKeys) {
      if (!k.endsWith('.json')) continue;
      const emp = await getJSON(k);
      if (!emp || emp.branch_id !== req.params.id) continue;
      const recordId = `day-status-${date}`;
      const record = {
        id: recordId,
        employee_id: emp.id,
        type: 'day_status',
        day_status: status,
        date,
        timestamp: new Date().toISOString(),
        status: 'success',
        set_by_admin: true,
        applied_by: applied_by || null,
        scope: 'branch',
      };
      await putJSON(`data/attendance/${emp.id}/record-${recordId}.json`, record);
      count += 1;
    }

    res.json({ message: 'Branch day status applied', employees_updated: count });
  } catch (error) {
    console.error('Branch day-status error:', error);
    res.status(500).json({ error: 'Failed to set branch day status' });
  }
});

module.exports = router;
