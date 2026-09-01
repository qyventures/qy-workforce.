import { useEffect } from 'react';
import { AppState, type AppStateStatus } from 'react-native';
import * as Linking from 'expo-linking';
import { Stack, useRouter } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import { supabase } from '../lib/supabase';
import { resolveAppRoute } from '../lib/navigation.mjs';

export default function RootLayout() {
  const router = useRouter();

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

  useEffect(() => {
    const client = supabase;
    if (!client) return;

    // Screens also verify their own data access, but this prevents a signed-out
    // worker from remaining on a stale authenticated screen after sign-out or
    // an expired session is cleared by the auth client.
    const { data: listener } = client.auth.onAuthStateChange((event) => {
      if (event === 'SIGNED_OUT') router.replace('/sign-in');
    });

    return () => listener.subscription.unsubscribe();
  }, [router]);

  useEffect(() => {
    let active = true;

    const openTrustedRoute = (url: string | null) => {
      if (!active || !url) return;
      const route = resolveAppRoute(url);
      if (route) router.replace(route as never);
    };

    void Linking.getInitialURL().then(openTrustedRoute).catch(() => undefined);
    const subscription = Linking.addEventListener('url', ({ url }) => openTrustedRoute(url));

    return () => {
      active = false;
      subscription.remove();
    };
  }, [router]);

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
