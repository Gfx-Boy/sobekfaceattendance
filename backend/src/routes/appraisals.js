const express = require('express');
const { v4: uuidv4 } = require('uuid');
const { putJSON, getJSON, listJSON } = require('../services/s3Service');

const router = express.Router();

const appraisalKey = (id) => `data/appraisals/appraisal-${id}.json`;
const appraisalsByEmployeePrefix = (empId) => `data/appraisals-by-employee/${empId}/`;
const appraisalPointerKey = (empId, id) => `data/appraisals-by-employee/${empId}/appraisal-${id}.json`;

// POST /api/appraisals — create a new appraisal
router.post('/', async (req, res) => {
  try {
    const { employee_id, employee_name, evaluator_id, evaluator_name, period, scores, comments, overall_score } = req.body;

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
      period,
      scores: scores || {},
      comments: comments || '',
      overall_score: overall_score || 0,
      status: 'submitted',
      created_at: new Date().toISOString(),
    };

    await putJSON(appraisalKey(id), appraisal);
    await putJSON(appraisalPointerKey(employee_id, id), { id });

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
