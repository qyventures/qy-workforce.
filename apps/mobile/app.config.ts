import appJson from './app.json';

export default () => ({
  ...appJson.expo,
  extra: {
    ...(appJson.expo.extra ?? {}),
    // EAS supplies this per build profile; never infer production credentials here.
    environment: process.env.EXPO_PUBLIC_APP_ENV ?? 'development',
  },
});
