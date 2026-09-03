// Keep the Expo config environment aligned with the EAS profile that is
// resolving it. EAS injects EXPO_PUBLIC_APP_ENV while evaluating this file;
// local development falls back to the value retained in app.json.
module.exports = ({ config }) => ({
  ...config,
  extra: {
    ...config.extra,
    environment:
      process.env.EXPO_PUBLIC_APP_ENV || config.extra?.environment || 'development',
  },
});
