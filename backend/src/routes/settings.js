const express = require('express');
const { putJSON, getJSON } = require('../services/s3Service');

const router = express.Router();

const SETTINGS_KEY = 'data/system-settings.json';

// Default settings
const DEFAULT_SETTINGS = {
  timezone: 'Asia/Riyadh', // UTC+3
  utc_offset: 3,
  working_hours: {
    start: '09:00',
    end: '18:00',
  },
  break_duration_minutes: 60,
  weekend_days: [5, 6], // Friday, Saturday (0=Mon...6=Sun mapped to 5=Fri,6=Sat for Gulf)
  updated_at: null,
  updated_by: null,
};

// Helper: get settings (with defaults)
async function getSettings() {
  const stored = await getJSON(SETTINGS_KEY);
  return { ...DEFAULT_SETTINGS, ...stored };
}

// GET /api/settings — get current system settings
router.get('/', async (req, res) => {
  try {
    const settings = await getSettings();
    res.json(settings);
  } catch (error) {
    console.error('Get settings error:', error);
    res.status(500).json({ error: 'Failed to load settings' });
  }
});

// PUT /api/settings — update system settings (super admin only)
router.put('/', async (req, res) => {
  try {
    const current = await getSettings();
    const {
      timezone,
      utc_offset,
      working_hours,
      break_duration_minutes,
      weekend_days,
      updated_by,
    } = req.body;

    if (timezone !== undefined) current.timezone = timezone;
    if (utc_offset !== undefined) current.utc_offset = utc_offset;
    if (working_hours !== undefined) current.working_hours = working_hours;
    if (break_duration_minutes !== undefined) current.break_duration_minutes = break_duration_minutes;
    if (weekend_days !== undefined) current.weekend_days = weekend_days;
    if (updated_by !== undefined) current.updated_by = updated_by;
    current.updated_at = new Date().toISOString();

    await putJSON(SETTINGS_KEY, current);
    res.json(current);
  } catch (error) {
    console.error('Update settings error:', error);
    res.status(500).json({ error: 'Failed to update settings' });
  }
});

module.exports = router;
module.exports.getSettings = getSettings;
