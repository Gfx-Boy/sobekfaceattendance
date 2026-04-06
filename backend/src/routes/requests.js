const express = require('express');
const { v4: uuidv4 } = require('uuid');
const { putJSON, getJSON, listJSON, listKeys } = require('../services/s3Service');
const notificationRoutes = require('./notifications');

const router = express.Router();

// S3 key helpers
const requestKey = (id) => `data/requests/request-${id}.json`;
const requestsByEmployeePrefix = (empId) => `data/requests-by-employee/${empId}/`;
const requestPointerKey = (empId, id) => `data/requests-by-employee/${empId}/request-${id}.json`;

// POST /api/requests — create a new request
router.post('/', async (req, res) => {
  try {
    const {
      employee_id,
      employee_name,
      employee_email,
      branch_name,
      category,
      type,
      title,
      description,
      start_date,
      end_date,
    } = req.body;

    if (!employee_id || !category || !type || !title || !description) {
      return res.status(400).json({ error: 'employee_id, category, type, title, and description are required' });
    }

    const id = uuidv4();
    const request = {
      id,
      employee_id,
      employee_name: employee_name || '',
      employee_email: employee_email || '',
      branch_name: branch_name || '',
      category,
      type,
      status: 'pending',
      title,
      description,
      created_at: new Date().toISOString(),
      start_date: start_date || null,
      end_date: end_date || null,
      comment: null,
      reviewed_by: null,
      reviewed_at: null,
    };

    // Save the main request object
    await putJSON(requestKey(id), request);
    // Save a pointer under the employee's prefix for listing
    await putJSON(requestPointerKey(employee_id, id), { id });

    res.status(201).json(request);

    // Notify branch admin and superAdmins about the new request
    try {
      const emp = await getJSON(`data/employees/employee-${employee_id}.json`);
      if (emp && emp.branch_id) {
        const keys = await listKeys('data/employees/');
        for (const key of keys) {
          if (!key.endsWith('.json') || key.includes('index')) continue;
          const admin = await getJSON(key);
          if (!admin) continue;
          // Notify BA of same branch
          if (admin.role === 'branchAdmin' && admin.branch_id === emp.branch_id && admin.id !== employee_id) {
            notificationRoutes.sendPushToEmployee(
              admin.id,
              'New Request',
              `${employee_name || 'An employee'} submitted a ${type} request`,
              { type: 'new_request', request_id: id }
            ).catch(e => console.error('Push failed:', e.message));
          }
          // Notify SA
          if (admin.role === 'superAdmin') {
            notificationRoutes.sendPushToEmployee(
              admin.id,
              'New Request',
              `${employee_name || 'An employee'} submitted a ${type} request`,
              { type: 'new_request', request_id: id }
            ).catch(e => console.error('Push failed:', e.message));
          }
        }
      }
    } catch (e) {
      console.error('Failed to notify admins of new request:', e.message);
    }
  } catch (error) {
    console.error('Create request error:', error);
    res.status(500).json({ error: 'Failed to create request' });
  }
});

// GET /api/requests/employee/:employeeId — list requests for an employee
router.get('/employee/:employeeId', async (req, res) => {
  try {
    const prefix = requestsByEmployeePrefix(req.params.employeeId);
    const pointers = await listJSON(prefix);

    // Fetch full request objects
    const requests = [];
    for (const ptr of pointers) {
      const full = await getJSON(requestKey(ptr.id));
      if (full) requests.push(full);
    }

    requests.sort((a, b) => new Date(b.created_at) - new Date(a.created_at));
    res.json(requests);
  } catch (error) {
    console.error('List requests error:', error);
    res.status(500).json({ error: 'Failed to list requests' });
  }
});

// GET /api/requests/:id — get single request
router.get('/:id', async (req, res) => {
  try {
    const request = await getJSON(requestKey(req.params.id));
    if (!request) {
      return res.status(404).json({ error: 'Request not found' });
    }
    res.json(request);
  } catch (error) {
    console.error('Get request error:', error);
    res.status(500).json({ error: 'Failed to get request' });
  }
});

// PATCH /api/requests/:id/review — approve / reject / forward
router.patch('/:id/review', async (req, res) => {
  try {
    const { status, comment, reviewed_by } = req.body;

    if (!status || !['approved', 'rejected', 'forwarded'].includes(status)) {
      return res.status(400).json({ error: 'status must be approved, rejected, or forwarded' });
    }

    const request = await getJSON(requestKey(req.params.id));
    if (!request) {
      return res.status(404).json({ error: 'Request not found' });
    }

    request.status = status;
    request.comment = comment || request.comment;
    request.reviewed_by = reviewed_by || null;
    request.reviewed_at = new Date().toISOString();

    await putJSON(requestKey(req.params.id), request);

    // Send push notification to request owner
    if (request.employee_id) {
      const statusLabel = status.charAt(0).toUpperCase() + status.slice(1);
      notificationRoutes.sendPushToEmployee(
        request.employee_id,
        `Request ${statusLabel}`,
        `Your ${request.type || 'request'} has been ${status}`,
        { type: 'request_review', request_id: request.id }
      ).catch(e => console.error('Push send failed:', e.message));
    }

    res.json(request);
  } catch (error) {
    console.error('Review request error:', error);
    res.status(500).json({ error: 'Failed to review request' });
  }
});

module.exports = router;
