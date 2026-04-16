const jwt = require('jsonwebtoken');
const { getJSON } = require('../services/s3Service');

const ACCESS_TOKEN_SECRET =
  process.env.ACCESS_TOKEN_SECRET || 'face-attendance-access-secret';

const employeeKey = (id) => `data/employees/employee-${id}.json`;

/**
 * JWT authentication middleware.
 * Verifies the Bearer token and attaches req.user = { sub, email, role }.
 * Also enforces single-session: if the employee's stored active_session_id
 * doesn't match this token's jti, reject with 401.
 */
async function requireAuth(req, res, next) {
  try {
    const authHeader = req.headers.authorization;
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return res.status(401).json({ error: 'Authentication required' });
    }

    const token = authHeader.slice(7);
    let payload;
    try {
      payload = jwt.verify(token, ACCESS_TOKEN_SECRET);
    } catch (err) {
      return res.status(401).json({ error: 'Invalid or expired token' });
    }

    // Enforce single session
    const emp = await getJSON(employeeKey(payload.sub));
    if (!emp) {
      return res.status(401).json({ error: 'Employee not found' });
    }
    if (emp.is_on_hold) {
      return res.status(403).json({ error: 'Account is on hold' });
    }
    if (emp.active_session_id && payload.jti && emp.active_session_id !== payload.jti) {
      return res.status(401).json({ error: 'Session expired. This account is logged in on another device.' });
    }

    req.user = {
      sub: payload.sub,
      email: payload.email,
      role: payload.role,
      branch_id: emp.branch_id,
    };
    req.employee = emp;
    next();
  } catch (error) {
    console.error('Auth middleware error:', error);
    return res.status(500).json({ error: 'Authentication failed' });
  }
}

/**
 * Role-based authorization middleware factory.
 * Usage: requireRole('superAdmin', 'branchAdmin')
 */
function requireRole(...roles) {
  return (req, res, next) => {
    if (!req.user) {
      return res.status(401).json({ error: 'Authentication required' });
    }
    if (!roles.includes(req.user.role)) {
      return res.status(403).json({ error: 'Insufficient permissions' });
    }
    next();
  };
}

module.exports = { requireAuth, requireRole };
