require('dotenv').config();
const express = require('express');
const cors = require('cors');
const { requireAuth } = require('./middleware/auth');
const employeeRoutes = require('./routes/employees');
const attendanceRoutes = require('./routes/attendance');
const requestRoutes = require('./routes/requests');
const notificationRoutes = require('./routes/notifications');
const taskRoutes = require('./routes/tasks');
const appraisalRoutes = require('./routes/appraisals');
const payslipRoutes = require('./routes/payslips');
const branchRoutes = require('./routes/branches');
const dashboardRoutes = require('./routes/dashboard');
const settingsRoutes = require('./routes/settings');

const app = express();
const PORT = process.env.PORT || 3000;

// Middleware
app.use(cors());
app.use(express.json());

// Public routes (no auth required)
app.use('/api/employees', employeeRoutes);

// Protected routes (require valid JWT)
app.use('/api/attendance', requireAuth, attendanceRoutes);
app.use('/api/requests', requireAuth, requestRoutes);
app.use('/api/notifications', requireAuth, notificationRoutes);
app.use('/api/tasks', requireAuth, taskRoutes);
app.use('/api/appraisals', requireAuth, appraisalRoutes);
app.use('/api/payslips', requireAuth, payslipRoutes);
app.use('/api/branches', requireAuth, branchRoutes);
app.use('/api/dashboard', requireAuth, dashboardRoutes);
app.use('/api/settings', requireAuth, settingsRoutes);

// Health check
app.get('/api/health', (req, res) => {
  res.json({ status: 'ok', timestamp: new Date().toISOString() });
});

app.listen(PORT, () => {
  console.log(`Face Attendance API running on port ${PORT}`);
});
