const express = require('express');
const { v4: uuidv4 } = require('uuid');
const { putJSON, getJSON, listJSON, listKeys } = require('../services/s3Service');
const notificationRoutes = require('./notifications');

const router = express.Router();

const appraisalKey = (id) => `data/appraisals/appraisal-${id}.json`;
const appraisalsByEmployeePrefix = (empId) => `data/appraisals-by-employee/${empId}/`;
const appraisalPointerKey = (empId, id) => `data/appraisals-by-employee/${empId}/appraisal-${id}.json`;
const cycleKey = (id) => `data/appraisal-cycles/cycle-${id}.json`;

// POST /api/appraisals/cycles — start an appraisal cycle (Branch Admin only)
router.post('/cycles', async (req, res) => {
  try {
    const { branch_id, branch_name, start_date, end_date, admin_weight, hr_weight, created_by, created_by_name } = req.body;
    if (!branch_id || !start_date || !end_date) {
      return res.status(400).json({ error: 'branch_id, start_date, and end_date are required' });
    }

    const id = uuidv4();
    const cycle = {
      id,
      branch_id,
      branch_name: branch_name || '',
      start_date,
      end_date,
      admin_weight: Number(admin_weight) || 70,
      hr_weight: Number(hr_weight) || 30,
      status: 'active',
      created_by: created_by || null,
      created_by_name: created_by_name || '',
      created_at: new Date().toISOString(),
    };

    await putJSON(cycleKey(id), cycle);

    // Notify all superAdmins about cycle start
    try {
      const keys = await listKeys('data/employees/');
      for (const key of keys) {
        if (!key.endsWith('.json') || key.includes('index')) continue;
        const emp = await getJSON(key);
        if (emp && emp.role === 'superAdmin') {
          notificationRoutes.sendPushToEmployee(
            emp.id,
            'Appraisal Cycle Started',
            `An appraisal cycle was started for ${branch_name || 'a branch'}`,
            { type: 'appraisal_started', cycle_id: id }
          ).catch(e => console.error('Push failed:', e.message));
        }
      }
    } catch (e) {
      console.error('Failed to notify about appraisal cycle:', e.message);
    }

    res.status(201).json(cycle);
  } catch (error) {
    console.error('Create cycle error:', error);
    res.status(500).json({ error: 'Failed to create appraisal cycle' });
  }
});

// GET /api/appraisals/cycles — list all cycles
router.get('/cycles', async (req, res) => {
  try {
    const cycles = await listJSON('data/appraisal-cycles/');
    cycles.sort((a, b) => new Date(b.created_at) - new Date(a.created_at));
    const branchFilter = req.query.branch_id;
    if (branchFilter) {
      return res.json(cycles.filter(c => c.branch_id === branchFilter));
    }
    res.json(cycles);
  } catch (error) {
    console.error('List cycles error:', error);
    res.status(500).json({ error: 'Failed to list cycles' });
  }
});

// POST /api/appraisals — create a new appraisal
router.post('/', async (req, res) => {
  try {
    const { employee_id, employee_name, evaluator_id, evaluator_name, evaluator_role, period, scores, comments, overall_score, cycle_id, branch_id } = req.body;

    if (!employee_id || !evaluator_id || !period) {
      return res.status(400).json({ error: 'employee_id, evaluator_id, and period are required' });
    }

    const id = uuidv4();
    const appraisal = {
      id,
      employee_id,
      employee_name: employee_name || '',
      evaluator_id,
      evaluator_name: evaluator_name || '',
      evaluator_role: evaluator_role || '',
      period,
      scores: scores || {},
      comments: comments || '',
      overall_score: overall_score || 0,
      cycle_id: cycle_id || null,
      branch_id: branch_id || null,
      status: 'submitted',
      created_at: new Date().toISOString(),
    };

    await putJSON(appraisalKey(id), appraisal);
    await putJSON(appraisalPointerKey(employee_id, id), { id });

    // Notify the employee about their appraisal
    notificationRoutes.sendPushToEmployee(
      employee_id,
      'Appraisal Submitted',
      `You have received a performance appraisal for ${period}`,
      { type: 'appraisal_submitted', appraisal_id: id }
    ).catch(e => console.error('Push failed:', e.message));

    res.status(201).json(appraisal);
  } catch (error) {
    console.error('Create appraisal error:', error);
    res.status(500).json({ error: 'Failed to create appraisal' });
  }
});

// GET /api/appraisals/all — all appraisals for SuperAdmin
router.get('/all', async (req, res) => {
  try {
    const appraisals = await listJSON('data/appraisals/');
    appraisals.sort((a, b) => new Date(b.created_at) - new Date(a.created_at));
    res.json(appraisals);
  } catch (error) {
    console.error('List all appraisals error:', error);
    res.status(500).json({ error: 'Failed to list all appraisals' });
  }
});

// GET /api/appraisals/employee/:employeeId
router.get('/employee/:employeeId', async (req, res) => {
  try {
    const pointers = await listJSON(appraisalsByEmployeePrefix(req.params.employeeId));
    const appraisals = [];
    for (const ptr of pointers) {
      const full = await getJSON(appraisalKey(ptr.id));
      if (full) appraisals.push(full);
    }
    appraisals.sort((a, b) => new Date(b.created_at) - new Date(a.created_at));
    res.json(appraisals);
  } catch (error) {
    console.error('List appraisals error:', error);
    res.status(500).json({ error: 'Failed to list appraisals' });
  }
});

// GET /api/appraisals/:id
router.get('/:id', async (req, res) => {
  try {
    const appraisal = await getJSON(appraisalKey(req.params.id));
    if (!appraisal) return res.status(404).json({ error: 'Appraisal not found' });
    res.json(appraisal);
  } catch (error) {
    console.error('Get appraisal error:', error);
    res.status(500).json({ error: 'Failed to get appraisal' });
  }
});

module.exports = router;
