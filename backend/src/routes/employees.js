const express = require('express');
const multer = require('multer');
const { v4: uuidv4 } = require('uuid');
const path = require('path');
const fs = require('fs');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const { uploadImage, putJSON, getJSON, listJSON, listKeys, BUCKET_NAME, awsErrorMessage } = require('../services/s3Service');
const notificationRoutes = require('./notifications');

const router = express.Router();

// Configure multer for file uploads
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
  limits: { fileSize: 10 * 1024 * 1024 }, // 10MB max
  fileFilter: (req, file, cb) => {
    const allowedTypes = ['image/jpeg', 'image/png', 'image/jpg', 'application/octet-stream'];
    if (allowedTypes.includes(file.mimetype) || file.mimetype.startsWith('image/')) {
      cb(null, true);
    } else {
      cb(new Error('Only JPEG and PNG images are allowed'));
    }
  },
});

// S3 key helpers
const employeeKey = (id) => `data/employees/employee-${id}.json`;
const indexKey = 'data/employees-index.json';

// Notify relevant admins when an employee is created
async function notifyAdminsOfNewEmployee(newEmployee) {
  try {
    const keys = await listKeys('data/employees/');
    for (const key of keys) {
      if (!key.endsWith('.json') || key.includes('index')) continue;
      const emp = await getJSON(key);
      if (!emp) continue;
      // Notify all superAdmins
      if (emp.role === 'superAdmin') {
        notificationRoutes.sendPushToEmployee(
          emp.id,
          'New Employee Created',
          `${newEmployee.name} (${newEmployee.role}) was added${newEmployee.branch_name ? ' to ' + newEmployee.branch_name : ''}`,
          { type: 'employee_created', employee_id: newEmployee.id }
        ).catch(e => console.error('Push failed:', e.message));
      }
      // Notify branchAdmin of the same branch (when HR creates an employee)
      if (emp.role === 'branchAdmin' && newEmployee.branch_id && emp.branch_id === newEmployee.branch_id) {
        notificationRoutes.sendPushToEmployee(
          emp.id,
          'New Employee in Your Branch',
          `${newEmployee.name} (${newEmployee.role}) was added to ${newEmployee.branch_name || 'your branch'}`,
          { type: 'employee_created', employee_id: newEmployee.id }
        ).catch(e => console.error('Push failed:', e.message));
      }
    }
  } catch (e) {
    console.error('Failed to notify admins of new employee:', e.message);
  }
}

// Read/write the email→id index with a short in-memory cache to reduce S3 calls.
const INDEX_CACHE_TTL_MS = parseInt(process.env.EMPLOYEE_INDEX_CACHE_TTL_MS || '30000', 10);
let cachedIndex = null;
let cachedIndexAt = 0;

async function getIndex({ force = false } = {}) {
  const now = Date.now();
  if (!force && cachedIndex && now - cachedIndexAt < INDEX_CACHE_TTL_MS) {
    return cachedIndex;
  }

  const indexData = (await getJSON(indexKey)) || {};
  cachedIndex = indexData;
  cachedIndexAt = now;
  return indexData;
}

async function saveIndex(indexData) {
  await putJSON(indexKey, indexData);
  cachedIndex = indexData;
  cachedIndexAt = Date.now();
}

const ACCESS_TOKEN_SECRET =
  process.env.ACCESS_TOKEN_SECRET || 'face-attendance-access-secret';
const REFRESH_TOKEN_SECRET =
  process.env.REFRESH_TOKEN_SECRET || 'face-attendance-refresh-secret';
const ACCESS_TOKEN_EXPIRES_IN =
  process.env.ACCESS_TOKEN_EXPIRES_IN || '1h';
const REFRESH_TOKEN_EXPIRES_IN =
  process.env.REFRESH_TOKEN_EXPIRES_IN || '30d';

function serializeEmployee(emp) {
  return {
    id: emp.id,
    name: emp.name,
    email: emp.email,
    department: emp.department,
    role: emp.role || 'employee',
    employee_type: emp.employee_type || 'general',
    branch_id: emp.branch_id,
    branch_name: emp.branch_name,
    address: emp.address,
    phone: emp.phone,
    position: emp.position,
    profile_image_url: emp.profile_image_url,
    reference_image_url: emp.reference_image_url,
    allowed_latitude: emp.allowed_latitude,
    allowed_longitude: emp.allowed_longitude,
    allowed_radius: emp.allowed_radius,
    is_on_hold: emp.is_on_hold || false,
  };
}

function tokenExpiresInSeconds(token) {
  const decoded = jwt.decode(token);
  if (!decoded || typeof decoded.exp !== 'number') {
    return null;
  }
  return Math.max(0, decoded.exp - Math.floor(Date.now() / 1000));
}

function issueAuthTokens(emp) {
  const sessionId = uuidv4();
  const payload = {
    sub: emp.id,
    email: emp.email,
    role: emp.role || 'employee',
    jti: sessionId,
  };

  const accessToken = jwt.sign(payload, ACCESS_TOKEN_SECRET, {
    expiresIn: ACCESS_TOKEN_EXPIRES_IN,
  });
  const refreshToken = jwt.sign(payload, REFRESH_TOKEN_SECRET, {
    expiresIn: REFRESH_TOKEN_EXPIRES_IN,
  });

  return {
    accessToken,
    refreshToken,
    accessExpiresIn: tokenExpiresInSeconds(accessToken),
    refreshExpiresIn: tokenExpiresInSeconds(refreshToken),
    sessionId,
  };
}

// POST /api/employees — create employee without face image (admin use)
router.post('/', async (req, res) => {
  try {
    const { name, email, department, role, employee_type, position, branch_id, branch_name, phone, address, password, allowed_latitude, allowed_longitude, allowed_radius } = req.body;

    if (!name || !email) {
      return res.status(400).json({ error: 'Name and email are required' });
    }

    // Check for duplicate email
    const idx = await getIndex();
    if (idx[email]) {
      return res.status(409).json({ error: 'Employee with this email already exists' });
    }

    const id = uuidv4();
    const employee = {
      id,
      name,
      email,
      department: department || '',
      role: role || 'employee',
      employee_type: employee_type || 'general',
      position: position || '',
      branch_id: branch_id || null,
      branch_name: branch_name || '',
      phone: phone || '',
      address: address || '',
      profile_image_url: '',
      reference_image_key: '',
      reference_image_url: '',
      created_at: new Date().toISOString(),
    };

    if (allowed_latitude) employee.allowed_latitude = parseFloat(allowed_latitude);
    if (allowed_longitude) employee.allowed_longitude = parseFloat(allowed_longitude);
    if (allowed_radius) employee.allowed_radius = parseFloat(allowed_radius);

    if (password && password.length >= 6) {
      employee.password_hash = await bcrypt.hash(password, 10);
    }

    await putJSON(employeeKey(id), employee);
    idx[email] = id;
    await saveIndex(idx);

    // If branchAdmin, update the branch record
    if (employee.role === 'branchAdmin' && employee.branch_id) {
      try {
        const branch = await getJSON(`data/branches/branch-${employee.branch_id}.json`);
        if (branch) {
          branch.admin_id = employee.id;
          branch.admin_name = employee.name;
          branch.updated_at = new Date().toISOString();
          await putJSON(`data/branches/branch-${employee.branch_id}.json`, branch);
        }
      } catch (e) {
        console.error('Failed to update branch admin:', e);
      }
    }

    res.status(201).json({ id: employee.id, name: employee.name, email: employee.email, role: employee.role, branch_id: employee.branch_id, branch_name: employee.branch_name });

    // Notify admins asynchronously (don't block response)
    notifyAdminsOfNewEmployee(employee);
  } catch (error) {
    console.error('Create employee error:', error);
    res.status(500).json({ error: awsErrorMessage(error) });
  }
});

// POST /api/employees/register
router.post('/register', upload.single('reference_image'), async (req, res) => {
  try {
    const { name, email, department } = req.body;

    if (!name || !email || !department) {
      return res.status(400).json({ error: 'Name, email, and department are required' });
    }

    if (!req.file) {
      return res.status(400).json({ error: 'Reference image is required' });
    }

    // Check for duplicate email via index
    const idx = await getIndex();
    if (idx[email]) {
      return res.status(409).json({ error: 'Employee with this email already exists' });
    }

    const id = uuidv4();
    const s3Key = `reference-images/${id}.jpg`;

    // Upload reference image to S3
    await uploadImage(req.file.path, s3Key);

    // Clean up local file
    fs.unlinkSync(req.file.path);

    const employee = {
      id,
      name,
      email,
      department,
      role: req.body.role || 'employee',
      employee_type: req.body.employee_type || 'general',
      reference_image_key: s3Key,
      reference_image_url: `s3://${BUCKET_NAME}/${s3Key}`,
      created_at: new Date().toISOString(),
    };

    // Optional fields
    if (req.body.phone) employee.phone = req.body.phone;
    if (req.body.position) employee.position = req.body.position;
    if (req.body.branch_id) employee.branch_id = req.body.branch_id;
    if (req.body.branch_name) employee.branch_name = req.body.branch_name;
    if (req.body.address) employee.address = req.body.address;

    // Geofence fields
    if (req.body.allowed_latitude) employee.allowed_latitude = parseFloat(req.body.allowed_latitude);
    if (req.body.allowed_longitude) employee.allowed_longitude = parseFloat(req.body.allowed_longitude);
    if (req.body.allowed_radius) employee.allowed_radius = parseFloat(req.body.allowed_radius);

    // Hash password if provided
    if (req.body.password && req.body.password.length >= 6) {
      employee.password_hash = await bcrypt.hash(req.body.password, 10);
    }

    // Save employee record & update index
    await putJSON(employeeKey(id), employee);
    idx[email] = id;
    await saveIndex(idx);

    // If this employee is a branchAdmin, update the branch record
    if (employee.role === 'branchAdmin' && employee.branch_id) {
      try {
        const branch = await getJSON(`data/branches/branch-${employee.branch_id}.json`);
        if (branch) {
          branch.admin_id = employee.id;
          branch.admin_name = employee.name;
          branch.updated_at = new Date().toISOString();
          await putJSON(`data/branches/branch-${employee.branch_id}.json`, branch);
        }
      } catch (e) {
        console.error('Failed to update branch admin:', e);
      }
    }

    res.status(201).json({
      id: employee.id,
      name: employee.name,
      email: employee.email,
      department: employee.department,
      role: employee.role,
      employee_type: employee.employee_type,
      phone: employee.phone,
      position: employee.position,
      reference_image_url: employee.reference_image_url,
      allowed_latitude: employee.allowed_latitude,
      allowed_longitude: employee.allowed_longitude,
      allowed_radius: employee.allowed_radius,
    });

    // Notify admins asynchronously
    notifyAdminsOfNewEmployee(employee);
  } catch (error) {
    console.error('Registration error:', error);
    if (req.file && fs.existsSync(req.file.path)) {
      fs.unlinkSync(req.file.path);
    }
    res.status(500).json({ error: awsErrorMessage(error) });
  }
});

// POST /api/employees/login
router.post('/login', async (req, res) => {
  try {
    const { email, password } = req.body;

    if (!email) {
      return res.status(400).json({ error: 'Email is required' });
    }

    const idx = await getIndex();
    const id = idx[email];
    if (!id) {
      return res.status(404).json({ error: 'Employee not found' });
    }

    const emp = await getJSON(employeeKey(id));
    if (!emp) {
      return res.status(404).json({ error: 'Employee not found' });
    }

    // If employee has a password set, validate it
    if (emp.password_hash && password) {
      const valid = await bcrypt.compare(password, emp.password_hash);
      if (!valid) {
        return res.status(401).json({ error: 'Invalid password' });
      }
    } else if (emp.password_hash && !password) {
      return res.status(401).json({ error: 'Password is required' });
    }
    // If no password_hash set, allow login (legacy/first-time)

    // Check if account is on hold
    if (emp.is_on_hold) {
      return res.status(403).json({ error: 'Your account is on hold. Please contact your administrator.' });
    }

    // Update last_online and active session
    const tokens = issueAuthTokens(emp);
    emp.last_online = new Date().toISOString();
    emp.active_session_id = tokens.sessionId;
    await putJSON(employeeKey(id), emp);

    res.json({
      employee: serializeEmployee(emp),
      access_token: tokens.accessToken,
      refresh_token: tokens.refreshToken,
      token_type: 'Bearer',
      expires_in: tokens.accessExpiresIn,
      refresh_expires_in: tokens.refreshExpiresIn,
    });
  } catch (error) {
    console.error('Login error:', error);
    res.status(500).json({ error: awsErrorMessage(error) });
  }
});

// POST /api/employees/refresh-token
router.post('/refresh-token', async (req, res) => {
  try {
    const { refresh_token: refreshToken } = req.body;

    if (!refreshToken) {
      return res.status(400).json({ error: 'Refresh token is required' });
    }

    let payload;
    try {
      payload = jwt.verify(refreshToken, REFRESH_TOKEN_SECRET);
    } catch (_) {
      return res.status(401).json({ error: 'Invalid or expired refresh token' });
    }

    const emp = await getJSON(employeeKey(payload.sub));
    if (!emp) {
      return res.status(404).json({ error: 'Employee not found' });
    }

    const tokens = issueAuthTokens(emp);
    emp.active_session_id = tokens.sessionId;
    emp.last_online = new Date().toISOString();
    await putJSON(employeeKey(payload.sub), emp);

    res.json({
      employee: serializeEmployee(emp),
      access_token: tokens.accessToken,
      refresh_token: tokens.refreshToken,
      token_type: 'Bearer',
      expires_in: tokens.accessExpiresIn,
      refresh_expires_in: tokens.refreshExpiresIn,
    });
  } catch (error) {
    console.error('Refresh token error:', error);
    res.status(500).json({ error: awsErrorMessage(error) });
  }
});

// GET /api/employees/:id
router.get('/:id', async (req, res) => {
  try {
    const emp = await getJSON(employeeKey(req.params.id));
    if (!emp) {
      return res.status(404).json({ error: 'Employee not found' });
    }

    res.json({
      id: emp.id,
      name: emp.name,
      email: emp.email,
      department: emp.department,
      role: emp.role || 'employee',
      employee_type: emp.employee_type || 'general',
      branch_id: emp.branch_id,
      branch_name: emp.branch_name,
      address: emp.address,
      phone: emp.phone,
      position: emp.position,
      profile_image_url: emp.profile_image_url,
      reference_image_url: emp.reference_image_url,
      allowed_latitude: emp.allowed_latitude,
      allowed_longitude: emp.allowed_longitude,
      allowed_radius: emp.allowed_radius,
      is_on_hold: emp.is_on_hold || false,
    });
  } catch (error) {
    console.error('Get employee error:', error);
    res.status(500).json({ error: awsErrorMessage(error) });
  }
});

// GET /api/employees — list all employees (for admin/HR)
router.get('/', async (req, res) => {
  try {
    const branchFilter = req.query.branch_id;
    const keys = await listKeys('data/employees/');
    const employees = [];
    for (const key of keys) {
      if (key.endsWith('.json') && !key.includes('index')) {
        const emp = await getJSON(key);
        if (emp) {
          // Filter by branch if requested
          if (branchFilter && emp.branch_id !== branchFilter) continue;
          employees.push({
            id: emp.id,
            name: emp.name,
            email: emp.email,
            department: emp.department,
            role: emp.role || 'employee',
            employee_type: emp.employee_type || 'general',
            branch_id: emp.branch_id,
            branch_name: emp.branch_name,
            position: emp.position,
            phone: emp.phone,
            last_online: emp.last_online,
            allowed_latitude: emp.allowed_latitude,
            allowed_longitude: emp.allowed_longitude,
            allowed_radius: emp.allowed_radius,
            is_on_hold: emp.is_on_hold || false,
          });
        }
      }
    }
    res.json(employees);
  } catch (error) {
    console.error('List employees error:', error);
    res.status(500).json({ error: awsErrorMessage(error) });
  }
});

// GET /api/employees/:id/profile-image — serve profile image from S3
router.get('/:id/profile-image', async (req, res) => {
  try {
    const emp = await getJSON(employeeKey(req.params.id));
    if (!emp || !emp.profile_image_key) {
      return res.status(404).json({ error: 'Profile image not found' });
    }
    const { getImageBuffer } = require('../services/s3Service');
    const buffer = await getImageBuffer(emp.profile_image_key);
    const ext = path.extname(emp.profile_image_key).toLowerCase();
    const ct = ext === '.png' ? 'image/png' : 'image/jpeg';
    res.set('Content-Type', ct);
    res.set('Cache-Control', 'public, max-age=3600');
    res.send(buffer);
  } catch (error) {
    console.error('Get profile image error:', error);
    res.status(404).json({ error: 'Profile image not found' });
  }
});

// POST /api/employees/:id/profile-image — upload profile photo
router.post('/:id/profile-image', upload.single('image'), async (req, res) => {
  try {
    const emp = await getJSON(employeeKey(req.params.id));
    if (!emp) {
      return res.status(404).json({ error: 'Employee not found' });
    }
    if (!req.file) {
      return res.status(400).json({ error: 'No image provided' });
    }

    const localPath = req.file.path;
    const s3Key = `data/profile-images/${req.params.id}${path.extname(req.file.originalname) || '.jpg'}`;
    await uploadImage(localPath, s3Key);
    fs.unlinkSync(localPath);

    // Store S3 key for proxy serving and a proxy URL for the client
    const baseUrl = `${req.protocol}://${req.get('host')}`;
    const imageUrl = `${baseUrl}/api/employees/${req.params.id}/profile-image`;
    emp.profile_image_url = imageUrl;
    emp.profile_image_key = s3Key;
    emp.updated_at = new Date().toISOString();
    await putJSON(employeeKey(req.params.id), emp);

    res.json({ profile_image_url: imageUrl });
  } catch (error) {
    console.error('Profile image upload error:', error);
    res.status(500).json({ error: awsErrorMessage(error) });
  }
});

// PUT /api/employees/:id — update employee
router.put('/:id', async (req, res) => {
  try {
    const emp = await getJSON(employeeKey(req.params.id));
    if (!emp) {
      return res.status(404).json({ error: 'Employee not found' });
    }

    const updates = req.body;
    const allowedFields = ['name', 'department', 'role', 'employee_type', 'branch_id', 'branch_name', 'address', 'phone', 'position', 'allowed_latitude', 'allowed_longitude', 'allowed_radius', 'is_on_hold'];
    for (const field of allowedFields) {
      if (updates[field] !== undefined) {
        emp[field] = updates[field];
      }
    }

    // Handle password update
    if (updates.password) {
      emp.password_hash = await bcrypt.hash(updates.password, 10);
    }

    emp.updated_at = new Date().toISOString();
    await putJSON(employeeKey(req.params.id), emp);

    res.json({
      id: emp.id,
      name: emp.name,
      email: emp.email,
      department: emp.department,
      role: emp.role,
      employee_type: emp.employee_type,
      branch_id: emp.branch_id,
      branch_name: emp.branch_name,
      address: emp.address,
      phone: emp.phone,
      position: emp.position,
    });
  } catch (error) {
    console.error('Update employee error:', error);
    res.status(500).json({ error: awsErrorMessage(error) });
  }
});

// DELETE /api/employees/:id
router.delete('/:id', async (req, res) => {
  try {
    const emp = await getJSON(employeeKey(req.params.id));
    if (!emp) {
      return res.status(404).json({ error: 'Employee not found' });
    }

    const { deleteJSON: delJSON } = require('../services/s3Service');
    await delJSON(employeeKey(req.params.id));

    // Remove from index
    const idx = await getIndex();
    delete idx[emp.email];
    await saveIndex(idx);

    res.json({ message: 'Employee deleted' });
  } catch (error) {
    console.error('Delete employee error:', error);
    res.status(500).json({ error: awsErrorMessage(error) });
  }
});

// POST /api/employees/:id/set-password
router.post('/:id/set-password', async (req, res) => {
  try {
    const { password } = req.body;
    if (!password || password.length < 6) {
      return res.status(400).json({ error: 'Password must be at least 6 characters' });
    }

    const emp = await getJSON(employeeKey(req.params.id));
    if (!emp) {
      return res.status(404).json({ error: 'Employee not found' });
    }

    emp.password_hash = await bcrypt.hash(password, 10);
    emp.updated_at = new Date().toISOString();
    await putJSON(employeeKey(req.params.id), emp);

    res.json({ message: 'Password set successfully' });
  } catch (error) {
    console.error('Set password error:', error);
    res.status(500).json({ error: awsErrorMessage(error) });
  }
});

// Helper for attendance route to look up an employee
async function getEmployee(id) {
  return await getJSON(employeeKey(id));
}

module.exports = router;
module.exports.getEmployee = getEmployee;
