const express = require('express');
const { v4: uuidv4 } = require('uuid');
const { putJSON, getJSON, listJSON } = require('../services/s3Service');
const notificationRoutes = require('./notifications');

const router = express.Router();

const payslipKey = (id) => `data/payslips/payslip-${id}.json`;
const payslipsByEmployeePrefix = (empId) => `data/payslips-by-employee/${empId}/`;
const payslipPointerKey = (empId, id) => `data/payslips-by-employee/${empId}/payslip-${id}.json`;
const appraisalsByEmployeePrefix = (empId) => `data/appraisals-by-employee/${empId}/`;

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

    // Mirror the appraisal access rule: nobody issues a payslip to a super admin
    // or to themselves, and HR cannot issue a payslip to a branch admin.
    const requesterRole = (req.user?.role || '').toLowerCase();
    const targetRole = (emp.role || '').toLowerCase();
    if (
      targetRole === 'superadmin' ||
      employee_id === req.user?.sub ||
      (requesterRole === 'hr' && targetRole === 'branchadmin')
    ) {
      return res
        .status(403)
        .json({ error: 'Not allowed to create a payslip for this employee' });
    }

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

    // Branch working hours are wall-clock local time, but timestamps are
    // stored in UTC and this server usually runs in UTC — comparing
    // `getHours()` directly flags late/early against the wrong clock (#22).
    // PAYROLL_TZ_OFFSET_MINUTES (e.g. 180 for UTC+3) wins; otherwise fall
    // back to the system settings' utc_offset; otherwise UTC.
    let tzOffsetMin = parseInt(process.env.PAYROLL_TZ_OFFSET_MINUTES || '', 10);
    if (!Number.isFinite(tzOffsetMin)) {
      try {
        const sysSettings = await getJSON('data/system-settings.json');
        const off = Number(sysSettings?.utc_offset);
        tzOffsetMin = Number.isFinite(off) ? off * 60 : 180;
      } catch (_) {
        tzOffsetMin = 180; // sensible default for the client's region (UTC+3)
      }
    }
    const shiftedDate = (iso) => new Date(new Date(iso).getTime() + tzOffsetMin * 60000);
    const localMinutesOfDay = (iso) => {
      const s = shiftedDate(iso);
      return s.getUTCHours() * 60 + s.getUTCMinutes();
    };
    // Local calendar date of a UTC timestamp — an evening punch in UTC+3
    // belongs to the local day, not the UTC one.
    const localDateStr = (iso) => shiftedDate(iso).toISOString().slice(0, 10);

    const records = await listJSON(`data/attendance/${employee_id}/`);
    const inPeriod = records.filter(r => {
      // A day_status record applies to its `date`, not to the moment it was
      // created — a vacation approved in May for June days must land in June,
      // otherwise those days read as absent and get deducted (#16/#22).
      if (r.type === 'day_status' && r.date) return r.date.startsWith(period);
      const t = r.timestamp || r.date;
      if (!t) return false;
      return localDateStr(t).startsWith(period);
    });
    // S3 listing order is lexicographic over random uuids — sort punches
    // chronologically or "first sign-in / last sign-out" picks random ones.
    inPeriod.sort((a, b) => String(a.timestamp || '').localeCompare(String(b.timestamp || '')));

    // Bucket by (local) date
    const byDate = {};
    for (const r of inPeriod) {
      const d = r.type === 'day_status'
        ? (r.date || '')
        : (r.timestamp ? localDateStr(r.timestamp) : (r.date || ''));
      if (!d) continue;
      (byDate[d] = byDate[d] || []).push(r);
    }

    const [py, pm] = period.split('-').map(Number);
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
        excusedCount = 0, incompleteCount = 0, overtimeMinutes = 0,
        lateMinutes = 0, earlyMinutes = 0, workingDayCount = 0;
    const todayStr = localDateStr(new Date().toISOString());

    for (let day = 1; day <= daysInMonth; day++) {
      const dateStr = `${py}-${String(pm).padStart(2,'0')}-${String(day).padStart(2,'0')}`;
      const dayName = dayNames[new Date(py, pm - 1, day).getDay()];
      const isWorkDay = workingDays.includes(dayName);
      if (isWorkDay) workingDayCount++;
      // Days that haven't happened yet are nobody's absence — generating a
      // payslip mid-month must not deduct the rest of the calendar (#5 r3).
      if (dateStr > todayStr) continue;
      const recs = byDate[dateStr] || [];
      const dayStatusRec = [...recs].reverse().find(r => r.type === 'day_status');
      if (dayStatusRec) {
        const s = dayStatusRec.day_status;
        if (s === 'vacation') { vacationCount++; continue; }
        if (s === 'holiday') { holidayCount++; continue; }
        if (s === 'absent') { absentCount++; continue; }
        // attend / sign_out / attend_full are all admin-set presence (#1B r5)
        if (s === 'attend' || s === 'sign_out' || s === 'attend_full') { presentCount++; continue; }
        // permission / business_mission / sick: approved & excused — paid,
        // never deducted. (They used to fall through and count as absent.)
        if (s === 'permission' || s === 'business_mission' || s === 'sick') {
          excusedCount++;
          continue;
        }
      }
      if (!isWorkDay) { holidayCount++; continue; }

      // Attendance is recorded as sign_in/sign_out (also accept the legacy
      // check_in/check_out spelling) — otherwise every day reads as absent.
      const checkIn = recs.find(r => r.type === 'sign_in' || r.type === 'check_in');
      const checkOut = [...recs].reverse()
          .find(r => r.type === 'sign_out' || r.type === 'check_out');
      if (!checkIn) { absentCount++; continue; }
      presentCount++;

      const ciMin = localMinutesOfDay(checkIn.timestamp);
      if (ciMin > startMin) { lateCount++; lateMinutes += ciMin - startMin; }

      if (checkOut) {
        const coMin = localMinutesOfDay(checkOut.timestamp);
        if (coMin < endMin) { earlyCount++; earlyMinutes += endMin - coMin; }
        else if (coMin > endMin) overtimeMinutes += (coMin - endMin);
      } else if (dateStr < todayStr) {
        // Checked in but never checked out on a past day: an "incomplete"
        // day (#22). Today is exempt — the employee may still be at work.
        incompleteCount++;
      }
    }

    const basic = Number(emp.basic_salary || 0);
    // Pro-rata fallbacks so lateness/absence always costs something even when
    // the branch's flat deduction rates were never configured (they default
    // to 0, which silently made every payslip equal the basic salary — #5 r3).
    const dayRate = workingDayCount > 0 ? basic / workingDayCount : 0;
    const workdayMinutes = Math.max(endMin - startMin, 1);
    const minuteRate = dayRate / workdayMinutes;
    const lateDeduction = dedLate > 0 ? lateCount * dedLate : lateMinutes * minuteRate;
    const earlyDeduction = dedEarly > 0 ? earlyCount * dedEarly : earlyMinutes * minuteRate;
    // No check-out means the afternoon is unproven: flat rate if configured,
    // otherwise half a day.
    const incompleteDeduction =
      dedEarly > 0 ? incompleteCount * dedEarly : incompleteCount * dayRate * 0.5;
    const absentDeduction = dedAbsent > 0 ? absentCount * dedAbsent : absentCount * dayRate;
    const deductions = lateDeduction + earlyDeduction + incompleteDeduction + absentDeduction;
    // Hourly rate based on standard 22 working days * 8 hours
    const hourlyRate = basic > 0 ? basic / (22 * 8) : 0;
    const overtimePay = (overtimeMinutes / 60) * hourlyRate * 1.5;

    // Appraisal-linked bonus (#6 r3): average this period's appraisal scores
    // (admin/HR weighted when both exist) and scale the branch bonus rate.
    // bonus = basic × bonus_rate% × score/100. bonus_rate defaults to 10%.
    const bonusRate = Number(branch?.bonus_rate ?? 10);
    let appraisalScore = null;
    try {
      const pointers = await listJSON(appraisalsByEmployeePrefix(employee_id));
      const appraisals = [];
      for (const ptr of pointers) {
        if (!ptr?.id) continue;
        const a = await getJSON(`data/appraisals/appraisal-${ptr.id}.json`);
        if (a && String(a.created_at || '').startsWith(period)) appraisals.push(a);
      }
      if (appraisals.length > 0) {
        const admin = appraisals.filter(a => (a.evaluator_role || '').toLowerCase() !== 'hr');
        const hr = appraisals.filter(a => (a.evaluator_role || '').toLowerCase() === 'hr');
        const avg = (list) =>
          list.reduce((s, a) => s + Number(a.overall_score || 0), 0) / list.length;
        if (admin.length > 0 && hr.length > 0) {
          let adminW = 70, hrW = 30;
          const cycleId = appraisals.find(a => a.cycle_id)?.cycle_id;
          if (cycleId) {
            const cycle = await getJSON(`data/appraisal-cycles/cycle-${cycleId}.json`);
            if (cycle) {
              adminW = Number(cycle.admin_weight ?? 70);
              hrW = Number(cycle.hr_weight ?? 30);
            }
          }
          appraisalScore = (avg(admin) * adminW + avg(hr) * hrW) / (adminW + hrW);
        } else {
          appraisalScore = avg(appraisals);
        }
      }
    } catch (e) {
      console.error('Appraisal bonus lookup failed:', e.message);
    }
    const bonuses = appraisalScore != null && bonusRate > 0
      ? Number((basic * (bonusRate / 100) * (appraisalScore / 100)).toFixed(2))
      : 0;

    const net = basic + bonuses + overtimePay - deductions;

    const breakdown = {
      present_days: presentCount,
      absent_days: absentCount,
      late_count: lateCount,
      late_minutes: lateMinutes,
      early_out_count: earlyCount,
      early_out_minutes: earlyMinutes,
      incomplete_count: incompleteCount,
      vacation_days: vacationCount,
      excused_days: excusedCount,
      holiday_days: holidayCount,
      overtime_minutes: overtimeMinutes,
      deduction_late: Number(lateDeduction.toFixed(2)),
      deduction_early_out: Number(earlyDeduction.toFixed(2)),
      deduction_incomplete: Number(incompleteDeduction.toFixed(2)),
      deduction_absent: Number(absentDeduction.toFixed(2)),
      appraisal_score: appraisalScore != null ? Number(appraisalScore.toFixed(1)) : null,
      bonus_rate: bonusRate,
    };

    if (!save) {
      return res.json({
        preview: true,
        employee_id,
        employee_name: emp.name,
        period,
        basic_salary: basic,
        bonuses,
        deductions: Number(deductions.toFixed(2)),
        overtime_pay: Number(overtimePay.toFixed(2)),
        net_salary: Number(net.toFixed(2)),
        branch_id: emp.branch_id || null,
        breakdown,
      });
    }

    // Regenerating a period UPDATES the existing payslip instead of piling up
    // duplicates — a saved slip previously froze forever, so late punches or
    // fixed statuses never changed it and the client saw a stale payslip (#5 r3).
    let existing = null;
    try {
      const pointers = await listJSON(payslipsByEmployeePrefix(employee_id));
      for (const ptr of pointers) {
        if (!ptr?.id) continue;
        const p = await getJSON(payslipKey(ptr.id));
        if (p && p.period === period) { existing = p; break; }
      }
    } catch (_) {}

    const id = existing ? existing.id : uuidv4();
    const payslip = {
      id,
      employee_id,
      employee_name: emp.name,
      period,
      basic_salary: basic,
      bonuses,
      deductions: Number(deductions.toFixed(2)),
      overtime_pay: Number(overtimePay.toFixed(2)),
      net_salary: Number(net.toFixed(2)),
      payment_date: existing?.payment_date || null,
      notes: 'Auto-generated from attendance',
      created_by: created_by || existing?.created_by || null,
      branch_id: emp.branch_id || null,
      breakdown,
      created_at: existing?.created_at || new Date().toISOString(),
      updated_at: existing ? new Date().toISOString() : undefined,
    };
    await putJSON(payslipKey(id), payslip);
    await putJSON(payslipPointerKey(employee_id, id), { id });
    notificationRoutes.sendPushToEmployee(
      employee_id,
      existing ? 'Payslip Updated' : 'New Payslip Available',
      existing
        ? `Your payslip for ${period} was recalculated`
        : `Your payslip for ${period} is now available`,
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
