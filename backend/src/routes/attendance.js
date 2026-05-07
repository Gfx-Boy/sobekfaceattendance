const express = require('express');
const multer = require('multer');
const { v4: uuidv4 } = require('uuid');
const path = require('path');
const fs = require('fs');
const { uploadImage, putJSON, getJSON, listJSON, BUCKET_NAME } = require('../services/s3Service');
const { compareFaces, detectLiveness } = require('../services/rekognitionService');
const { getEmployee } = require('./employees');

const router = express.Router();

// Configure multer
const storage = multer.diskStorage({
  destination: (req, file, cb) => {
    const uploadDir = path.join(__dirname, '../../uploads');
    if (!fs.existsSync(uploadDir)) {
      fs.mkdirSync(uploadDir, { recursive: true });
    }
    cb(null, uploadDir);
  },
  filename: (req, file, cb) => {
    const ext = path.extname(file.originalname) || '.jpg';
    cb(null, `${uuidv4()}${ext}`);
  },
});

const upload = multer({
  storage,
  limits: { fileSize: 10 * 1024 * 1024 },
  fileFilter: (req, file, cb) => {
    const allowedTypes = ['image/jpeg', 'image/png', 'image/jpg', 'application/octet-stream'];
    // Accept all image types and octet-stream (Flutter sometimes sends without explicit mime)
    if (allowedTypes.includes(file.mimetype) || file.mimetype.startsWith('image/')) {
      cb(null, true);
    } else {
      cb(new Error('Only JPEG and PNG images are allowed'));
    }
  },
});

// S3 key helpers
const attendanceRecordKey = (employeeId, recordId) =>
  `data/attendance/${employeeId}/record-${recordId}.json`;

// POST /api/attendance/mark
router.post('/mark', upload.single('image'), async (req, res) => {
  try {
    const { employee_id, latitude, longitude, type } = req.body;
    const validTypes = ['sign_in', 'sign_out', 'break_start', 'break_end'];
    const attendanceType = validTypes.includes(type) ? type : 'sign_in';

    if (!employee_id || !latitude || !longitude) {
      return res.status(400).json({
        is_verified: false,
        face_matched: false,
        liveness_detected: false,
        message: 'Employee ID, latitude, and longitude are required',
      });
    }

    if (!req.file) {
      return res.status(400).json({
        is_verified: false,
        face_matched: false,
        liveness_detected: false,
        message: 'Face image is required',
      });
    }

    // Find the employee from S3
    const employee = await getEmployee(employee_id);
    if (!employee) {
      return res.status(404).json({
        is_verified: false,
        face_matched: false,
        liveness_detected: false,
        message: 'Employee not found',
      });
    }

    const capturedImagePath = req.file.path;

    // Step 0: Geofence check — if employee has allowed location, verify they're within range
    if (employee.allowed_latitude != null && employee.allowed_longitude != null && employee.allowed_radius != null) {
      const lat1 = parseFloat(latitude);
      const lon1 = parseFloat(longitude);
      const lat2 = employee.allowed_latitude;
      const lon2 = employee.allowed_longitude;

      // Haversine formula for distance in meters
      const R = 6371000;
      const dLat = (lat2 - lat1) * Math.PI / 180;
      const dLon = (lon2 - lon1) * Math.PI / 180;
      const a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
        Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) *
        Math.sin(dLon / 2) * Math.sin(dLon / 2);
      const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
      const distance = R * c;

      if (distance > employee.allowed_radius) {
        fs.unlinkSync(capturedImagePath);
        return res.json({
          is_verified: false,
          face_matched: false,
          liveness_detected: false,
          message: `You are ${Math.round(distance)}m away from your allowed location`,
        });
      }
    }

    // Step 1: Upload captured image to S3
    const capturedS3Key = `attendance-images/${employee_id}/${uuidv4()}.jpg`;
    await uploadImage(capturedImagePath, capturedS3Key);

    // Step 2: Liveness detection
    const livenessResult = await detectLiveness(capturedImagePath);
    if (!livenessResult.isLive) {
      fs.unlinkSync(capturedImagePath);
      return res.json({
        is_verified: false,
        face_matched: false,
        liveness_detected: false,
        message: livenessResult.message,
      });
    }

    // Step 3: Face comparison with reference image
    const faceResult = await compareFaces(
      capturedImagePath,
      BUCKET_NAME,
      employee.reference_image_key,
    );

    fs.unlinkSync(capturedImagePath);

    if (!faceResult.matched) {
      return res.json({
        is_verified: false,
        face_matched: false,
        liveness_detected: true,
        face_match_confidence: faceResult.confidence,
        message: 'Face does not match the registered employee',
      });
    }

    // Step 4: Record attendance in S3
    const attendanceId = uuidv4();
    const record = {
      id: attendanceId,
      employee_id,
      employee_name: employee.name,
      type: attendanceType,
      timestamp: new Date().toISOString(),
      latitude: parseFloat(latitude),
      longitude: parseFloat(longitude),
      status: 'success',
      face_match_confidence: faceResult.confidence,
      liveness_verified: true,
      geofence_verified: employee.allowed_radius != null,
      image_url: `s3://${BUCKET_NAME}/${capturedS3Key}`,
    };

    await putJSON(attendanceRecordKey(employee_id, attendanceId), record);

    res.json({
      is_verified: true,
      face_matched: true,
      liveness_detected: true,
      face_match_confidence: faceResult.confidence,
      message: attendanceType === 'sign_in' ? 'Signed in successfully!'
        : attendanceType === 'sign_out' ? 'Signed out successfully!'
        : attendanceType === 'break_start' ? 'Break started!'
        : 'Break ended!',
      attendance_id: attendanceId,
      type: attendanceType,
    });
  } catch (error) {
    console.error('Attendance marking error:', error);

    if (req.file && fs.existsSync(req.file.path)) {
      fs.unlinkSync(req.file.path);
    }

    res.status(500).json({
      is_verified: false,
      face_matched: false,
      liveness_detected: false,
      message: 'Internal server error during verification',
    });
  }
});

// GET /api/attendance/today/:employeeId — get today's attendance records
router.get('/today/:employeeId', async (req, res) => {
  try {
    const { employeeId } = req.params;
    const prefix = `data/attendance/${employeeId}/`;
    const records = await listJSON(prefix);

    // Filter to today's records (UTC)
    const todayStr = new Date().toISOString().split('T')[0];
    const todayRecords = records.filter(
      (r) => r.timestamp && r.timestamp.startsWith(todayStr)
    );

    todayRecords.sort((a, b) => new Date(a.timestamp) - new Date(b.timestamp));

    // Compute summary
    const signIn = todayRecords.find((r) => r.type === 'sign_in');
    const signOut = [...todayRecords].reverse().find((r) => r.type === 'sign_out');
    const breaks = todayRecords.filter(
      (r) => r.type === 'break_start' || r.type === 'break_end'
    );

    // Calculate total break duration
    let totalBreakMs = 0;
    let onBreak = false;
    let breakStartTime = null;
    for (const b of breaks) {
      if (b.type === 'break_start') {
        onBreak = true;
        breakStartTime = new Date(b.timestamp);
      } else if (b.type === 'break_end' && breakStartTime) {
        totalBreakMs += new Date(b.timestamp) - breakStartTime;
        onBreak = false;
        breakStartTime = null;
      }
    }
    // If currently on break, count up to now
    if (onBreak && breakStartTime) {
      totalBreakMs += new Date() - breakStartTime;
    }

    res.json({
      records: todayRecords,
      summary: {
        signed_in: !!signIn,
        signed_out: !!signOut,
        on_break: onBreak,
        sign_in_time: signIn?.timestamp || null,
        sign_out_time: signOut?.timestamp || null,
        total_break_minutes: Math.round(totalBreakMs / 60000),
        break_count: breaks.filter((b) => b.type === 'break_start').length,
      },
    });
  } catch (error) {
    console.error('Today attendance error:', error);
    res.status(500).json({ error: 'Failed to retrieve today attendance' });
  }
});

// GET /api/attendance/history/:employeeId
router.get('/history/:employeeId', async (req, res) => {
  try {
    const { employeeId } = req.params;
    const prefix = `data/attendance/${employeeId}/`;
    const records = await listJSON(prefix);

    // Sort by timestamp descending
    records.sort((a, b) => new Date(b.timestamp) - new Date(a.timestamp));

    res.json(records);
  } catch (error) {
    console.error('Attendance history error:', error);
    res.status(500).json({ error: 'Failed to retrieve attendance history' });
  }
});

// PUT /api/attendance/day-status — Admin/HR set day status (vacation, absent, etc.)
router.put('/day-status', async (req, res) => {
  try {
    const { employee_id, date, status } = req.body;
    if (!employee_id || !date || !status) {
      return res.status(400).json({ error: 'employee_id, date, and status are required' });
    }

    const validStatuses = ['attend', 'vacation', 'absent', 'holiday'];
    if (!validStatuses.includes(status)) {
      return res.status(400).json({ error: `Invalid status. Must be one of: ${validStatuses.join(', ')}` });
    }

    const recordId = `day-status-${date}`;
    const record = {
      id: recordId,
      employee_id,
      type: 'day_status',
      day_status: status,
      date,
      timestamp: new Date().toISOString(),
      status: 'success',
      set_by_admin: true,
    };

    await putJSON(attendanceRecordKey(employee_id, recordId), record);
    res.json(record);
  } catch (error) {
    console.error('Set day status error:', error);
    res.status(500).json({ error: 'Failed to set day status' });
  }
});

module.exports = router;
