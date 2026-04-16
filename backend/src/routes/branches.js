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
        if (branch) branches.push(branch);
      }
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

    await putJSON(branchKey(req.params.id), branch);
    res.json(branch);
  } catch (error) {
    console.error('Update branch error:', error);
    res.status(500).json({ error: 'Failed to update branch' });
  }
});

// DELETE /api/branches/:id
router.delete('/:id', async (req, res) => {
  try {
    const branch = await getJSON(branchKey(req.params.id));
    if (!branch) return res.status(404).json({ error: 'Branch not found' });

    await deleteJSON(branchKey(req.params.id));
    res.json({ message: 'Branch deleted' });
  } catch (error) {
    console.error('Delete branch error:', error);
    res.status(500).json({ error: 'Failed to delete branch' });
  }
});

module.exports = router;
