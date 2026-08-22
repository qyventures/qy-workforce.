import { useEffect, useState } from 'react';
import { ActivityIndicator, AppState, StyleSheet, Text, View, type AppStateStatus } from 'react-native';
import * as Linking from 'expo-linking';
import { Stack, useRouter, useSegments } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import { resolveAuthRedirect } from '../lib/auth-routing.mjs';
import { supabase } from '../lib/supabase';
import { resolveAppRoute } from '../lib/navigation.mjs';

export default function RootLayout() {
  const router = useRouter();
  const segments = useSegments();
  const [sessionResolved, setSessionResolved] = useState(!supabase);
  const [authenticated, setAuthenticated] = useState(false);

  useEffect(() => {
    const client = supabase;
    if (!client) return;

    let active = true;
    void client.auth.getSession().then(({ data }) => {
      if (!active) return;
      setAuthenticated(Boolean(data.session));
      setSessionResolved(true);
    }).catch(() => {
      if (!active) return;
      setAuthenticated(false);
      setSessionResolved(true);
    });

    const { data: authSubscription } = client.auth.onAuthStateChange((_event, session) => {
      if (!active) return;
      setAuthenticated(Boolean(session));
      setSessionResolved(true);
    });

    return () => {
      active = false;
      authSubscription.subscription.unsubscribe();
    };
  }, []);

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
    const redirect = resolveAuthRedirect({
      configured: Boolean(supabase),
      sessionResolved,
      authenticated,
      segment: segments[0],
    });
    if (redirect) router.replace(redirect as never);
  }, [authenticated, router, segments, sessionResolved]);

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

  if (supabase && !sessionResolved) {
    return (
      <View style={styles.loading} accessibilityRole="progressbar" accessibilityLabel="Checking secure sign in">
        <StatusBar style="light" />
        <ActivityIndicator size="large" color="#FFFFFF" />
        <Text style={styles.loadingText}>Checking secure sign in…</Text>
      </View>
    );
  }

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
        <Stack.Screen name="notifications" options={{ title: 'Updates' }} />
      </Stack>
    </>
  );
}

const styles = StyleSheet.create({
  loading: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    gap: 14,
    backgroundColor: '#0A0A0A',
    padding: 24,
  },
  loadingText: {
    color: '#D4D4D4',
    fontSize: 15,
  },
});
