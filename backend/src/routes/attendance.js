const express = require('express');
const multer = require('multer');
const { v4: uuidv4 } = require('uuid');
const path = require('path');
const fs = require('fs');
const { uploadImage, putJSON, getJSON, listJSON, BUCKET_NAME } = require('../services/s3Service');
const {
  compareFaces,
  compareFacesBytes,
  detectLiveness,
  detectStaticSpoof,
  createLivenessSession,
  getLivenessResult,
} = require('../services/rekognitionService');
const { perceptualHash, hammingHex } = require('../services/imageForensics');
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

// ---------------------------------------------------------------------------
// AWS Face Liveness (the definitive anti-spoof): the app runs the oval
// face-scan against a session created here, then /mark verifies the session
// server-side and face-matches the session's own audit image.

// A liveness session may only ever authorize ONE attendance mark.
const usedLivenessSessions = new Map(); // sessionId -> timestamp
setInterval(() => {
  const cutoff = Date.now() - 15 * 60 * 1000;
  for (const [sid, t] of usedLivenessSessions) {
    if (t < cutoff) usedLivenessSessions.delete(sid);
  }
}, 60 * 1000).unref();

// POST /api/attendance/liveness/session — start a Face Liveness session
router.post('/liveness/session', async (req, res) => {
  try {
    const sessionId = await createLivenessSession();
    res.json({ session_id: sessionId });
  } catch (error) {
    console.error('Create liveness session error:', error);
    res.status(500).json({ error: 'Failed to create liveness session' });
  }
});

// POST /api/attendance/mark
// `image` is the capture shown to the user; `image_b` is a control frame the
// app takes silently ~1s later for the passive static-spoof check (optional,
// older APKs don't send it).
router.post('/mark', upload.fields([{ name: 'image', maxCount: 1 }, { name: 'image_b', maxCount: 1 }]), async (req, res) => {
  const primaryFile = req.files?.image?.[0];
  const controlFile = req.files?.image_b?.[0];
  const cleanup = () => {
    for (const f of [primaryFile, controlFile]) {
      if (f) { try { fs.unlinkSync(f.path); } catch (_) {} }
    }
  };
  try {
    const { employee_id, latitude, longitude, type } = req.body;
    const validTypes = ['sign_in', 'sign_out', 'break_start', 'break_end'];
    const attendanceType = validTypes.includes(type) ? type : 'sign_in';

    if (!employee_id || !latitude || !longitude) {
      cleanup();
      return res.status(400).json({
        is_verified: false,
        face_matched: false,
        liveness_detected: false,
        message: 'Employee ID, latitude, and longitude are required',
      });
    }

    // A face image is required unless a Face Liveness session provides the
    // audit image instead.
    if (!primaryFile && !req.body.liveness_session_id) {
      cleanup();
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
      cleanup();
      return res.status(404).json({
        is_verified: false,
        face_matched: false,
        liveness_detected: false,
        message: 'Employee not found',
      });
    }

    const capturedImagePath = primaryFile?.path;

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
        cleanup();
        return res.json({
          is_verified: false,
          face_matched: false,
          liveness_detected: false,
          message: `You are ${Math.round(distance)}m away from your allowed location`,
        });
      }
    }

    // Step 1: Upload captured image to S3 (when the app sent one; on the
    // Face Liveness path the session's audit image is stored instead).
    const capturedS3Key = `attendance-images/${employee_id}/${uuidv4()}.jpg`;
    if (capturedImagePath) {
      await uploadImage(capturedImagePath, capturedS3Key);
    }

    // Attendance REQUIRES a Face Liveness session — the legacy photo path is
    // the exact bypass a spoofer retried through (client video, round 4).
    // Set REQUIRE_LIVENESS=false only if old APKs must temporarily work.
    const requireLiveness = process.env.REQUIRE_LIVENESS !== 'false';
    if (requireLiveness && !req.body.liveness_session_id) {
      cleanup();
      return res.json({
        is_verified: false,
        face_matched: false,
        liveness_detected: false,
        message: 'Please update the app to the latest version to mark attendance.',
      });
    }

    // ── AWS Face Liveness path (new APKs) ─────────────────────────────────
    // The oval-scan session already proved a live person server-side; we
    // face-match against the SESSION'S OWN audit image so the identity is
    // bound to the live scan — a photo/screen can neither pass the scan nor
    // be substituted afterwards.
    const livenessSessionId = req.body.liveness_session_id;
    if (livenessSessionId) {
      if (usedLivenessSessions.has(livenessSessionId)) {
        cleanup();
        return res.json({
          is_verified: false, face_matched: false, liveness_detected: false,
          spoof: true, message: 'Alert: the image is not live',
        });
      }
      let session;
      try {
        session = await getLivenessResult(livenessSessionId);
      } catch (e) {
        console.error('Liveness result fetch failed:', e.message);
        cleanup();
        return res.json({
          is_verified: false, face_matched: false, liveness_detected: false,
          message: 'Liveness check could not be verified. Please try again.',
        });
      }
      usedLivenessSessions.set(livenessSessionId, Date.now());
      if (!session.live || !session.referenceImageBytes) {
        console.log(`Face Liveness rejected for ${employee_id}: status=${session.status} conf=${session.confidence?.toFixed?.(1)}`);
        cleanup();
        return res.json({
          is_verified: false, face_matched: false, liveness_detected: false,
          spoof: true, message: 'Alert: the image is not live',
        });
      }

      // No app-side photo on this path — store the session's audit image as
      // the attendance picture.
      if (!capturedImagePath) {
        const tmp = path.join(require('os').tmpdir(), `liveness-${uuidv4()}.jpg`);
        try {
          fs.writeFileSync(tmp, session.referenceImageBytes);
          await uploadImage(tmp, capturedS3Key);
        } finally {
          try { fs.unlinkSync(tmp); } catch (_) {}
        }
      }

      const faceResult = await compareFacesBytes(
        session.referenceImageBytes, BUCKET_NAME, employee.reference_image_key,
      );
      cleanup();
      if (!faceResult.matched) {
        return res.json({
          is_verified: false, face_matched: false, liveness_detected: true,
          face_match_confidence: faceResult.confidence,
          message: 'Face does not match the registered employee',
        });
      }

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
        liveness_confidence: session.confidence,
        geofence_verified: employee.allowed_radius != null,
        image_url: `s3://${BUCKET_NAME}/${capturedS3Key}`,
      };
      await putJSON(attendanceRecordKey(employee_id, attendanceId), record);
      return res.json({
        is_verified: true, face_matched: true, liveness_detected: true,
        face_match_confidence: faceResult.confidence,
        message: attendanceType === 'sign_in' ? 'Signed in successfully!'
          : attendanceType === 'sign_out' ? 'Signed out successfully!'
          : attendanceType === 'break_start' ? 'Break started!'
          : 'Break ended!',
        attendance_id: attendanceId,
        type: attendanceType,
      });
    }
    // ── Legacy path (older APKs without the oval scan) ────────────────────

    // Step 2: Liveness detection
    const livenessResult = await detectLiveness(capturedImagePath);
    if (!livenessResult.isLive) {
      cleanup();
      return res.json({
        is_verified: false,
        face_matched: false,
        liveness_detected: false,
        spoof: livenessResult.spoof === true,
        message: livenessResult.message,
      });
    }

    // Step 2b: passive static-spoof check against the silent control frame —
    // catches a photo/screen held to the camera even when it fills the whole
    // frame (no device edges for DetectLabels to see). Fails open on errors.
    if (controlFile) {
      try {
        const staticCheck = await detectStaticSpoof(capturedImagePath, controlFile.path);
        if (staticCheck.spoof) {
          console.log(`Static spoof rejected for ${employee_id}: ${staticCheck.reason}`);
          cleanup();
          return res.json({
            is_verified: false,
            face_matched: false,
            liveness_detected: false,
            spoof: true,
            message: 'Alert: the image is not live',
          });
        }
      } catch (e) {
        console.error('Static-spoof check failed (continuing):', e.message);
      }
    }

    // Step 2c: photo-reuse check — the same picture (screenshotted or
    // re-photographed) presented on different days hashes the same. A live
    // camera never produces a near-identical frame twice.
    let captureHash = null;
    try {
      captureHash = await perceptualHash(capturedImagePath);
      const recent = Array.isArray(employee.recent_capture_hashes)
        ? employee.recent_capture_hashes
        : [];
      const REPLAY_BITS = parseInt(process.env.REPLAY_HASH_MAX_BITS || '6', 10);
      const replay = recent.find((h) => hammingHex(h, captureHash) <= REPLAY_BITS);
      if (replay) {
        console.log(`Replay spoof rejected for ${employee_id}: capture matches a previous image`);
        cleanup();
        return res.json({
          is_verified: false,
          face_matched: false,
          liveness_detected: false,
          spoof: true,
          message: 'Alert: the image is not live',
        });
      }
    } catch (e) {
      console.error('Replay check failed (continuing):', e.message);
    }

    // Step 3: Face comparison with reference image
    const faceResult = await compareFaces(
      capturedImagePath,
      BUCKET_NAME,
      employee.reference_image_key,
    );

    cleanup();

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

    // Remember this capture's hash so the identical picture can never be
    // replayed on another day (rolling window of the last 15 captures).
    if (captureHash) {
      try {
        const hashes = Array.isArray(employee.recent_capture_hashes)
          ? employee.recent_capture_hashes
          : [];
        hashes.push(captureHash);
        employee.recent_capture_hashes = hashes.slice(-15);
        await putJSON(`data/employees/employee-${employee_id}.json`, employee);
      } catch (e) {
        console.error('Failed to store capture hash (continuing):', e.message);
      }
    }

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
    cleanup();
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

    // Keep in sync with branches.js branch-wide day-status: request approvals
    // also write permission/business_mission/sick records, so the per-employee
    // route must accept the same vocabulary.
    const validStatuses = ['attend', 'sign_out', 'attend_full', 'vacation', 'absent', 'holiday', 'permission', 'business_mission', 'sick'];
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
