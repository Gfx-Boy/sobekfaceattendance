const express = require('express');
const { v4: uuidv4 } = require('uuid');
const { putJSON, getJSON, listJSON } = require('../services/s3Service');
const admin = require('firebase-admin');

const router = express.Router();

// S3 key helpers
const notifKey = (empId, id) => `data/notifications/${empId}/notif-${id}.json`;
const notifPrefix = (empId) => `data/notifications/${empId}/`;
const fcmTokensKey = (empId) => `data/fcm-tokens/${empId}.json`;

// ---------- Initialize Firebase Admin ----------
let firebaseInitialized = false;
(function initFirebase() {
  try {
    const serviceAccountJson = process.env.FIREBASE_SERVICE_ACCOUNT;
    if (serviceAccountJson) {
      const serviceAccount = JSON.parse(serviceAccountJson);
      admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
      firebaseInitialized = true;
      console.log('Firebase Admin initialized via service account');
    } else {
      console.log('FIREBASE_SERVICE_ACCOUNT not set — FCM push disabled');
    }
  } catch (e) {
    console.error('Firebase Admin init failed:', e.message);
  }
})();

// ---------- FCM Token Management ----------

// POST /api/notifications/register-token
router.post('/register-token', async (req, res) => {
  try {
    const { employee_id, token } = req.body;
    if (!employee_id || !token) {
      return res.status(400).json({ error: 'employee_id and token required' });
    }

    let record;
    try {
      record = await getJSON(fcmTokensKey(employee_id));
    } catch (_) {}
    if (!record) record = { employee_id, tokens: [] };

    if (!record.tokens.includes(token)) {
      record.tokens.push(token);
    }
    record.updated_at = new Date().toISOString();
    await putJSON(fcmTokensKey(employee_id), record);
    res.json({ success: true });
  } catch (error) {
    console.error('Register FCM token error:', error);
    res.status(500).json({ error: 'Failed to register token' });
  }
});

// POST /api/notifications/unregister-token
router.post('/unregister-token', async (req, res) => {
  try {
    const { employee_id, token } = req.body;
    if (!employee_id || !token) {
      return res.status(400).json({ error: 'employee_id and token required' });
    }

    let record;
    try {
      record = await getJSON(fcmTokensKey(employee_id));
    } catch (_) {}
    if (record && record.tokens) {
      record.tokens = record.tokens.filter(t => t !== token);
      record.updated_at = new Date().toISOString();
      await putJSON(fcmTokensKey(employee_id), record);
    }
    res.json({ success: true });
  } catch (error) {
    console.error('Unregister FCM token error:', error);
    res.status(500).json({ error: 'Failed to unregister token' });
  }
});

// ---------- Send FCM push utility ----------
// Uses firebase-admin SDK (FCM v1 API)
async function sendPushToEmployee(employeeId, title, body, data) {
  if (!firebaseInitialized) {
    console.log('FCM not initialized — push skipped for', employeeId);
    return;
  }

  let record;
  try {
    record = await getJSON(fcmTokensKey(employeeId));
  } catch (_) {}
  if (!record || !record.tokens || record.tokens.length === 0) return;

  const invalidTokens = [];
  for (const token of record.tokens) {
    try {
      await admin.messaging().send({
        token,
        notification: { title, body },
        data: Object.fromEntries(Object.entries(data || {}).map(([k, v]) => [k, String(v)])),
        android: { priority: 'high' },
      });
    } catch (e) {
      const code = e.code || '';
      if (code.includes('registration-token-not-registered') || code.includes('invalid-argument')) {
        invalidTokens.push(token);
      } else {
        console.error(`FCM send failed for token ${token.substring(0, 10)}...:`, e.message);
      }
    }
  }

  // Clean up invalid tokens
  if (invalidTokens.length > 0) {
    record.tokens = record.tokens.filter(t => !invalidTokens.includes(t));
    await putJSON(fcmTokensKey(employeeId), record);
  }
}

// Export the push utility for use in other routes
router.sendPushToEmployee = sendPushToEmployee;

// POST /api/notifications — create a notification for a user
router.post('/', async (req, res) => {
  try {
    const { employee_id, type, title, body } = req.body;

    if (!employee_id || !title) {
      return res.status(400).json({ error: 'employee_id and title are required' });
    }

    const id = uuidv4();
    const notification = {
      id,
      employee_id,
      type: type || 'general',
      title,
      body: body || '',
      is_read: false,
      created_at: new Date().toISOString(),
    };

    await putJSON(notifKey(employee_id, id), notification);
    res.status(201).json(notification);
  } catch (error) {
    console.error('Create notification error:', error);
    res.status(500).json({ error: 'Failed to create notification' });
  }
});

// GET /api/notifications/:employeeId — list notifications for an employee
router.get('/:employeeId', async (req, res) => {
  try {
    const notifications = await listJSON(notifPrefix(req.params.employeeId));
    notifications.sort((a, b) => new Date(b.created_at) - new Date(a.created_at));
    res.json(notifications);
  } catch (error) {
    console.error('List notifications error:', error);
    res.status(500).json({ error: 'Failed to list notifications' });
  }
});

// PATCH /api/notifications/:employeeId/:id/read — mark as read
router.patch('/:employeeId/:id/read', async (req, res) => {
  try {
    const { employeeId, id } = req.params;
    const notification = await getJSON(notifKey(employeeId, id));
    if (!notification) {
      return res.status(404).json({ error: 'Notification not found' });
    }

    notification.is_read = true;
    await putJSON(notifKey(employeeId, id), notification);
    res.json(notification);
  } catch (error) {
    console.error('Mark read error:', error);
    res.status(500).json({ error: 'Failed to update notification' });
  }
});

module.exports = router;
