require('dotenv').config();
const express = require('express');
const cors = require('cors');
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

// Routes
app.use('/api/employees', employeeRoutes);
app.use('/api/attendance', attendanceRoutes);
app.use('/api/requests', requestRoutes);
app.use('/api/notifications', notificationRoutes);
app.use('/api/tasks', taskRoutes);
app.use('/api/appraisals', appraisalRoutes);
app.use('/api/payslips', payslipRoutes);
app.use('/api/branches', branchRoutes);
app.use('/api/dashboard', dashboardRoutes);
app.use('/api/settings', settingsRoutes);

// Health check
app.get('/api/health', (req, res) => {
  res.json({ status: 'ok', timestamp: new Date().toISOString() });
});

app.listen(PORT, () => {
  console.log(`Face Attendance API running on port ${PORT}`);
});
