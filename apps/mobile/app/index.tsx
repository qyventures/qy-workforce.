import { useEffect, useState } from 'react';
import { Link, router } from 'expo-router';
import { ActivityIndicator, Alert, Pressable, SafeAreaView, ScrollView, StyleSheet, Text, View } from 'react-native';
import { supabase } from '../lib/supabase';

const cards = [
  { title: 'Find shifts', body: 'Browse eligible jobs matched to your verified roles and skills.', href: '/shifts' as const },
  { title: 'My shifts', body: 'See accepted work, attendance status and submitted timesheets.', href: '/my-shifts' as const },
  { title: 'Earnings', body: 'Track estimated earnings and timesheet payment status in one place.', href: '/earnings' as const },
  { title: 'Clock in / out', body: 'Open an accepted shift to verify attendance at its assigned site.', href: '/my-shifts' as const },
  { title: 'Readiness', body: 'See identity, eligibility, role, vetting, training and consent checks in one place.', href: '/readiness' as const },
  { title: 'Profile & training', body: 'Complete onboarding, verification, certificates and required training.', href: '/onboarding' as const },
];

export default function HomeScreen() {
  const [checkingSession, setCheckingSession] = useState(Boolean(supabase));
  const [signingOut, setSigningOut] = useState(false);
  const [sessionError, setSessionError] = useState<string | null>(null);

  useEffect(() => {
    if (!supabase) return;
    let mounted = true;

    void supabase.auth.getSession().then(({ data, error }) => {
      if (!mounted) return;
      if (error || !data.session) {
        router.replace('/sign-in');
        return;
      }
      setCheckingSession(false);
    });

    return () => { mounted = false; };
  }, []);

  function confirmSignOut() {
    if (!supabase || signingOut) return;
    Alert.alert('Sign out of this device?', 'Your secure session will be removed from this device.', [
      { text: 'Cancel', style: 'cancel' },
      {
        text: 'Sign out',
        style: 'destructive',
        onPress: () => void signOut(),
      },
    ]);
  }

  async function signOut() {
    if (!supabase) return;
    setSigningOut(true);
    setSessionError(null);
    try {
      // Local sign-out removes the session from this device even when the worker
      // has no connection; server-side authorisation remains unchanged.
      const { error } = await supabase.auth.signOut({ scope: 'local' });
      if (error) throw error;
      router.replace('/sign-in');
    } catch {
      setSessionError('We could not remove this session. Please try again.');
    } finally {
      setSigningOut(false);
    }
  }

  if (checkingSession) {
    return <SafeAreaView style={styles.safe}><View style={styles.loading} accessibilityRole="progressbar"><ActivityIndicator color="#FFFFFF" /><Text style={styles.loadingText}>Checking your secure session…</Text></View></SafeAreaView>;
  }

  return (
    <SafeAreaView style={styles.safe}>
      <ScrollView contentContainerStyle={styles.container}>
        <Text style={styles.eyebrow}>QY WORKFORCE</Text>
        <Text style={styles.title}>Work that fits your schedule.</Text>
        <Text style={styles.subtitle}>Verified shifts, clear pay, simple attendance and one worker profile.</Text>

        {sessionError ? <Text style={styles.error} accessibilityRole="alert">{sessionError}</Text> : null}

        <View style={styles.statusCard}>
          <Text style={styles.statusTitle}>Deployment readiness</Text>
          <Text style={styles.statusValue}>Check your verified status</Text>
          <Link href="/readiness" style={styles.link}>View readiness →</Link>
        </View>

        {cards.map((card) => (
          <Link key={card.title} href={card.href} style={styles.card} accessibilityLabel={`${card.title}. ${card.body}`}>
            <View>
              <Text style={styles.cardTitle}>{card.title}</Text>
              <Text style={styles.cardBody}>{card.body}</Text>
              <Text style={styles.cardLink}>Open →</Text>
            </View>
          </Link>
        ))}

        {supabase ? (
          <Pressable
            onPress={confirmSignOut}
            disabled={signingOut}
            style={[styles.signOut, signingOut && styles.disabled]}
            accessibilityRole="button"
            accessibilityState={{ disabled: signingOut, busy: signingOut }}
          >
            <Text style={styles.signOutText}>{signingOut ? 'Signing out…' : 'Sign out of this device'}</Text>
          </Pressable>
        ) : null}
      </ScrollView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  safe: { flex: 1, backgroundColor: '#0A0A0A' },
  loading: { flex: 1, alignItems: 'center', justifyContent: 'center', gap: 12, padding: 24 },
  loadingText: { color: '#D4D4D4', textAlign: 'center' },
  container: { padding: 24, gap: 16, paddingBottom: 48 },
  eyebrow: { color: '#A3A3A3', fontSize: 12, letterSpacing: 2 },
  title: { color: '#FFFFFF', fontSize: 34, fontWeight: '700', lineHeight: 40 },
  subtitle: { color: '#D4D4D4', fontSize: 17, lineHeight: 25, marginBottom: 8 },
  statusCard: { backgroundColor: '#171717', borderRadius: 18, padding: 20, gap: 7 },
  statusTitle: { color: '#A3A3A3', fontSize: 13 },
  statusValue: { color: '#FFFFFF', fontSize: 20, fontWeight: '600' },
  link: { color: '#FFFFFF', fontSize: 15, marginTop: 4 },
  card: { backgroundColor: '#111111', borderWidth: 1, borderColor: '#262626', borderRadius: 18, padding: 20 },
  cardTitle: { color: '#FFFFFF', fontSize: 18, fontWeight: '600' },
  cardBody: { color: '#B3B3B3', fontSize: 15, lineHeight: 22, marginTop: 8 },
  cardLink: { color: '#FFFFFF', fontSize: 14, fontWeight: '700', marginTop: 12 },
  signOut: { minHeight: 48, alignItems: 'center', justifyContent: 'center', padding: 12, marginTop: 4 },
  signOutText: { color: '#D4D4D4', fontSize: 15, fontWeight: '600' },
  disabled: { opacity: 0.55 },
  error: { color: '#FCA5A5', fontSize: 14, lineHeight: 20 },
});
