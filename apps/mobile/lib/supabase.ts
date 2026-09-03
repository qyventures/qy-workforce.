import 'react-native-url-polyfill/auto';
import { createClient } from '@supabase/supabase-js';
import * as SecureStore from 'expo-secure-store';

const supabaseUrl = process.env.EXPO_PUBLIC_SUPABASE_URL;
const supabaseAnonKey = process.env.EXPO_PUBLIC_SUPABASE_ANON_KEY;
const appEnvironment = process.env.EXPO_PUBLIC_APP_ENV ?? 'development';
let pointsToProduction = false;
if (supabaseUrl) {
  try {
    pointsToProduction = /(^|[.-])prod(uction)?([.-]|$)/i.test(new URL(supabaseUrl).hostname);
  } catch {
    console.error('Supabase URL is invalid. Mobile app will remain in demo mode.');
  }
}

const secureStorage = {
  getItem: (key: string) => SecureStore.getItemAsync(key),
  setItem: (key: string, value: string) => SecureStore.setItemAsync(key, value),
  removeItem: (key: string) => SecureStore.deleteItemAsync(key),
};

if (!supabaseUrl || !supabaseAnonKey) {
  console.warn('Supabase staging environment variables are not configured. Mobile app will remain in demo mode.');
}

if (pointsToProduction && appEnvironment !== 'production') {
  console.error('Refusing to connect a non-production mobile build to a production Supabase project.');
}

export const supabase = supabaseUrl && supabaseAnonKey && (!pointsToProduction || appEnvironment === 'production')
  ? createClient(supabaseUrl, supabaseAnonKey, {
      auth: {
        storage: secureStorage,
        autoRefreshToken: true,
        persistSession: true,
        detectSessionInUrl: false,
      },
    })
  : null;
