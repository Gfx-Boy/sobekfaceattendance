const express = require('express');
const { listKeys, getJSON, listJSON } = require('../services/s3Service');

const router = express.Router();

// GET /api/dashboard/stats — aggregate stats for admin
router.get('/stats', async (req, res) => {
  try {
    // Count employees
    const empKeys = await listKeys('data/employees/');
    const employeeCount = empKeys.filter(k => k.endsWith('.json') && !k.includes('index')).length;

    // Count branches
    const branchKeys = await listKeys('data/branches/');
    const branchCount = branchKeys.filter(k => k.endsWith('.json')).length;

    // Count today's attendance
    const today = new Date().toISOString().split('T')[0];
    const attendanceKeys = await listKeys('data/attendance/');
    let todayAttendance = 0;
    let totalAttendance = attendanceKeys.filter(k => k.endsWith('.json')).length;

    // Count open requests
    const requestKeys = await listKeys('data/requests/');
    let pendingRequests = 0;
    let totalRequests = 0;
    for (const key of requestKeys) {
      if (key.endsWith('.json')) {
        totalRequests++;
        try {
          const req = await getJSON(key);
          if (req && req.status === 'pending') pendingRequests++;
        } catch (_) {}
      }
    }

    // Count tasks
    const taskKeys = await listKeys('data/tasks/');
    const totalTasks = taskKeys.filter(k => k.endsWith('.json')).length;

    res.json({
      employee_count: employeeCount,
      branch_count: branchCount,
      today_attendance: todayAttendance,
      total_attendance: totalAttendance,
      pending_requests: pendingRequests,
      total_requests: totalRequests,
      total_tasks: totalTasks,
    });
  } catch (error) {
    console.error('Dashboard stats error:', error);
    res.status(500).json({ error: 'Failed to get dashboard stats' });
  }
});

// GET /api/dashboard/all-requests — all requests for admin/HR review
router.get('/all-requests', async (req, res) => {
  try {
    const branchFilter = req.query.branch_id;
    const keys = await listKeys('data/requests/');
    const requests = [];

    // If branch filter is set, get the branch's employees first
    let branchEmployeeIds = null;
    if (branchFilter) {
      const empKeys = await listKeys('data/employees/');
      branchEmployeeIds = new Set();
      for (const key of empKeys) {
        if (key.endsWith('.json') && !key.includes('index')) {
          const emp = await getJSON(key);
          if (emp && emp.branch_id === branchFilter) {
            branchEmployeeIds.add(emp.id);
          }
        }
      }
    }

    for (const key of keys) {
      if (key.endsWith('.json')) {
        const r = await getJSON(key);
        if (r) {
          // Filter by branch if requested
          if (branchEmployeeIds && !branchEmployeeIds.has(r.employee_id)) continue;
          requests.push(r);
        }
      }
    }
    requests.sort((a, b) => new Date(b.created_at) - new Date(a.created_at));
    res.json(requests);
  } catch (error) {
    console.error('All requests error:', error);
    res.status(500).json({ error: 'Failed to list all requests' });
  }
});

// GET /api/dashboard/all-attendance — all attendance records
router.get('/all-attendance', async (req, res) => {
  try {
    const empDirs = await listKeys('data/attendance/');
    const records = [];
    // attendance is stored per employee in sub-dirs
    const empKeys = new Set();
    for (const key of empDirs) {
      const parts = key.split('/');
      if (parts.length >= 3) empKeys.add(parts.slice(0, 3).join('/') + '/');
    }
    for (const prefix of empKeys) {
      const recs = await listKeys(prefix);
      for (const key of recs) {
        if (key.endsWith('.json')) {
          try {
            const rec = await getJSON(key);
            if (rec) records.push(rec);
          } catch (_) {}
        }
      }
    }
    records.sort((a, b) => new Date(b.timestamp || b.created_at || 0) - new Date(a.timestamp || a.created_at || 0));
    res.json(records.slice(0, 200)); // limit to 200 most recent
  } catch (error) {
    console.error('All attendance error:', error);
    res.status(500).json({ error: 'Failed to list attendance' });
  }
});

module.exports = router;
