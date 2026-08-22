import { useEffect } from 'react';
import { AppState, type AppStateStatus } from 'react-native';
import { Stack } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import { supabase } from '../lib/supabase';

export default function RootLayout() {
  useEffect(() => {
    const client = supabase;
    if (!client) return;

    const syncAuthRefresh = (state: AppStateStatus) => {
      if (state === 'active') client.auth.startAutoRefresh();
      else client.auth.stopAutoRefresh();
    };

    syncAuthRefresh(AppState.currentState);
    const subscription = AppState.addEventListener('change', syncAuthRefresh);

    return () => {
      subscription.remove();
      client.auth.stopAutoRefresh();
    };
  }, []);

  return (
    <>
      <StatusBar style="auto" />
      <Stack
        screenOptions={{
          headerBackTitle: 'Back',
          headerTitleStyle: { fontWeight: '700' },
          contentStyle: { backgroundColor: '#FFFFFF' },
          animation: 'slide_from_right',
        }}
      >
        <Stack.Screen name="index" options={{ title: 'QY Workforce' }} />
        <Stack.Screen name="sign-in" options={{ title: 'Sign in', headerBackVisible: false }} />
        <Stack.Screen name="onboarding" options={{ title: 'Your profile' }} />
        <Stack.Screen name="readiness" options={{ title: 'Readiness' }} />
        <Stack.Screen name="shifts" options={{ title: 'Find shifts' }} />
        <Stack.Screen name="my-shifts" options={{ title: 'My shifts' }} />
        <Stack.Screen name="assignment" options={{ title: 'Shift details' }} />
        <Stack.Screen name="attendance" options={{ title: 'Attendance' }} />
        <Stack.Screen name="earnings" options={{ title: 'Earnings' }} />
      </Stack>
    </>
  );
}
