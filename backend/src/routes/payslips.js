const express = require('express');
const { v4: uuidv4 } = require('uuid');
const { putJSON, getJSON, listJSON } = require('../services/s3Service');

const router = express.Router();

const payslipKey = (id) => `data/payslips/payslip-${id}.json`;
const payslipsByEmployeePrefix = (empId) => `data/payslips-by-employee/${empId}/`;
const payslipPointerKey = (empId, id) => `data/payslips-by-employee/${empId}/payslip-${id}.json`;

// POST /api/payslips — create a payslip (admin/HR)
router.post('/', async (req, res) => {
  try {
    const { employee_id, employee_name, period, basic_salary, bonuses, deductions, overtime_pay, net_salary, payment_date, notes } = req.body;

    if (!employee_id || !period || basic_salary === undefined) {
      return res.status(400).json({ error: 'employee_id, period, and basic_salary are required' });
    }

    const id = uuidv4();
    const payslip = {
      id,
      employee_id,
      employee_name: employee_name || '',
      period,
      basic_salary: Number(basic_salary) || 0,
      bonuses: Number(bonuses) || 0,
      deductions: Number(deductions) || 0,
      overtime_pay: Number(overtime_pay) || 0,
      net_salary: Number(net_salary) || (Number(basic_salary) + Number(bonuses || 0) + Number(overtime_pay || 0) - Number(deductions || 0)),
      payment_date: payment_date || null,
      notes: notes || '',
      created_at: new Date().toISOString(),
    };

    await putJSON(payslipKey(id), payslip);
    await putJSON(payslipPointerKey(employee_id, id), { id });

    res.status(201).json(payslip);
  } catch (error) {
    console.error('Create payslip error:', error);
    res.status(500).json({ error: 'Failed to create payslip' });
  }
});

// GET /api/payslips/all — all payslips for SuperAdmin
router.get('/all', async (req, res) => {
  try {
    const payslips = await listJSON('data/payslips/');
    payslips.sort((a, b) => new Date(b.created_at) - new Date(a.created_at));
    res.json(payslips);
  } catch (error) {
    console.error('List all payslips error:', error);
    res.status(500).json({ error: 'Failed to list all payslips' });
  }
});

// GET /api/payslips/employee/:employeeId
router.get('/employee/:employeeId', async (req, res) => {
  try {
    const pointers = await listJSON(payslipsByEmployeePrefix(req.params.employeeId));
    const payslips = [];
    for (const ptr of pointers) {
      const full = await getJSON(payslipKey(ptr.id));
      if (full) payslips.push(full);
    }
    payslips.sort((a, b) => new Date(b.created_at) - new Date(a.created_at));
    res.json(payslips);
  } catch (error) {
    console.error('List payslips error:', error);
    res.status(500).json({ error: 'Failed to list payslips' });
  }
});

// GET /api/payslips/:id
router.get('/:id', async (req, res) => {
  try {
    const payslip = await getJSON(payslipKey(req.params.id));
    if (!payslip) return res.status(404).json({ error: 'Payslip not found' });
    res.json(payslip);
  } catch (error) {
    console.error('Get payslip error:', error);
    res.status(500).json({ error: 'Failed to get payslip' });
  }
});

module.exports = router;
