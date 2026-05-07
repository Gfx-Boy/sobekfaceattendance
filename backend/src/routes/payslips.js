const express = require('express');
const { v4: uuidv4 } = require('uuid');
const { putJSON, getJSON, listJSON } = require('../services/s3Service');
const notificationRoutes = require('./notifications');

const router = express.Router();

const payslipKey = (id) => `data/payslips/payslip-${id}.json`;
const payslipsByEmployeePrefix = (empId) => `data/payslips-by-employee/${empId}/`;
const payslipPointerKey = (empId, id) => `data/payslips-by-employee/${empId}/payslip-${id}.json`;

// POST /api/payslips — create a payslip (admin/HR)
router.post('/', async (req, res) => {
  try {
    const { employee_id, employee_name, period, basic_salary, bonuses, deductions, overtime_pay, net_salary, payment_date, notes, created_by, branch_id } = req.body;

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
      created_by: created_by || null,
      branch_id: branch_id || null,
      created_at: new Date().toISOString(),
    };

    await putJSON(payslipKey(id), payslip);
    await putJSON(payslipPointerKey(employee_id, id), { id });

    // Notify employee about new payslip
    notificationRoutes.sendPushToEmployee(
      employee_id,
      'New Payslip Available',
      `Your payslip for ${period} is now available`,
      { type: 'payslip_created', payslip_id: id }
    ).catch(e => console.error('Push failed:', e.message));

    res.status(201).json(payslip);
  } catch (error) {
    console.error('Create payslip error:', error);
    res.status(500).json({ error: 'Failed to create payslip' });
  }
});

// POST /api/payslips/generate — auto-compute payslip from attendance for a period
// body: { employee_id, period: 'YYYY-MM', created_by, save? }
router.post('/generate', async (req, res) => {
  try {
    const { employee_id, period, created_by, save } = req.body;
    if (!employee_id || !period || !/^\d{4}-\d{2}$/.test(period)) {
      return res.status(400).json({ error: 'employee_id and period (YYYY-MM) required' });
    }

    const emp = await getJSON(`data/employees/employee-${employee_id}.json`);
    if (!emp) return res.status(404).json({ error: 'Employee not found' });

    const branch = emp.branch_id
      ? await getJSON(`data/branches/branch-${emp.branch_id}.json`)
      : null;
    const dedLate = Number(branch?.deduction_late || 0);
    const dedEarly = Number(branch?.deduction_early_out || 0);
    const dedAbsent = Number(branch?.deduction_absent || 0);
    const workStart = branch?.working_hours_start || '09:00';
    const workEnd = branch?.working_hours_end || '18:00';
    const workingDays = branch?.working_days ||
      ['Monday','Tuesday','Wednesday','Thursday','Friday'];

    const records = await listJSON(`data/attendance/${employee_id}/`);
    const [py, pm] = period.split('-').map(Number);
    const inPeriod = records.filter(r => {
      const t = r.timestamp || r.date;
      if (!t) return false;
      const d = new Date(t);
      return d.getFullYear() === py && d.getMonth() + 1 === pm;
    });

    // Bucket by date
    const byDate = {};
    for (const r of inPeriod) {
      const d = (r.date || (r.timestamp || '').slice(0, 10));
      if (!d) continue;
      (byDate[d] = byDate[d] || []).push(r);
    }

    const dayNames = ['Sunday','Monday','Tuesday','Wednesday','Thursday','Friday','Saturday'];
    const daysInMonth = new Date(py, pm, 0).getDate();
    const toMin = (hhmm) => {
      const [h, m] = hhmm.split(':').map(Number);
      return h * 60 + m;
    };
    const startMin = toMin(workStart);
    const endMin = toMin(workEnd);

    let lateCount = 0, earlyCount = 0, absentCount = 0,
        vacationCount = 0, holidayCount = 0, presentCount = 0,
        overtimeMinutes = 0;

    for (let day = 1; day <= daysInMonth; day++) {
      const dateStr = `${py}-${String(pm).padStart(2,'0')}-${String(day).padStart(2,'0')}`;
      const dayName = dayNames[new Date(py, pm - 1, day).getDay()];
      const isWorkDay = workingDays.includes(dayName);
      const recs = byDate[dateStr] || [];
      const dayStatusRec = recs.find(r => r.type === 'day_status');
      if (dayStatusRec) {
        const s = dayStatusRec.day_status;
        if (s === 'vacation') vacationCount++;
        else if (s === 'holiday') holidayCount++;
        else if (s === 'absent') absentCount++;
        else if (s === 'attend') presentCount++;
        continue;
      }
      if (!isWorkDay) { holidayCount++; continue; }

      const checkIn = recs.find(r => r.type === 'check_in');
      const checkOut = recs.find(r => r.type === 'check_out');
      if (!checkIn) { absentCount++; continue; }
      presentCount++;

      const ci = new Date(checkIn.timestamp);
      const ciMin = ci.getHours() * 60 + ci.getMinutes();
      if (ciMin > startMin) lateCount++;

      if (checkOut) {
        const co = new Date(checkOut.timestamp);
        const coMin = co.getHours() * 60 + co.getMinutes();
        if (coMin < endMin) earlyCount++;
        else if (coMin > endMin) overtimeMinutes += (coMin - endMin);
      }
    }

    const basic = Number(emp.basic_salary || 0);
    const deductions =
      lateCount * dedLate + earlyCount * dedEarly + absentCount * dedAbsent;
    // Hourly rate based on standard 22 working days * 8 hours
    const hourlyRate = basic > 0 ? basic / (22 * 8) : 0;
    const overtimePay = (overtimeMinutes / 60) * hourlyRate * 1.5;
    const bonuses = 0;
    const net = basic + bonuses + overtimePay - deductions;

    const breakdown = {
      present_days: presentCount,
      absent_days: absentCount,
      late_count: lateCount,
      early_out_count: earlyCount,
      vacation_days: vacationCount,
      holiday_days: holidayCount,
      overtime_minutes: overtimeMinutes,
      deduction_late: dedLate,
      deduction_early_out: dedEarly,
      deduction_absent: dedAbsent,
    };

    if (!save) {
      return res.json({
        preview: true,
        employee_id,
        employee_name: emp.name,
        period,
        basic_salary: basic,
        bonuses,
        deductions,
        overtime_pay: Number(overtimePay.toFixed(2)),
        net_salary: Number(net.toFixed(2)),
        branch_id: emp.branch_id || null,
        breakdown,
      });
    }

    const id = uuidv4();
    const payslip = {
      id,
      employee_id,
      employee_name: emp.name,
      period,
      basic_salary: basic,
      bonuses,
      deductions,
      overtime_pay: Number(overtimePay.toFixed(2)),
      net_salary: Number(net.toFixed(2)),
      payment_date: null,
      notes: 'Auto-generated from attendance',
      created_by: created_by || null,
      branch_id: emp.branch_id || null,
      breakdown,
      created_at: new Date().toISOString(),
    };
    await putJSON(payslipKey(id), payslip);
    await putJSON(payslipPointerKey(employee_id, id), { id });
    notificationRoutes.sendPushToEmployee(
      employee_id,
      'New Payslip Available',
      `Your payslip for ${period} is now available`,
      { type: 'payslip_created', payslip_id: id }
    ).catch(e => console.error('Push failed:', e.message));
    res.status(201).json(payslip);
  } catch (error) {
    console.error('Generate payslip error:', error);
    res.status(500).json({ error: 'Failed to generate payslip' });
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
