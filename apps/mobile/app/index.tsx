import { useCallback, useEffect, useState } from 'react';
import { Link } from 'expo-router';
import { ActivityIndicator, Pressable, SafeAreaView, ScrollView, StyleSheet, Text, View } from 'react-native';
import { isLikelyNetworkError } from '../lib/errors';
import { HOME_ACTIONS } from '../lib/home-actions.mjs';
import { homeReadinessPresentation } from '../lib/home-readiness.mjs';
import { supabase } from '../lib/supabase';

export default function HomeScreen() {
  const [readiness, setReadiness] = useState<Record<string, unknown> | null>(null);
  const [loadingReadiness, setLoadingReadiness] = useState(Boolean(supabase));
  const [readinessError, setReadinessError] = useState<string | null>(null);

  const loadReadiness = useCallback(async () => {
    if (!supabase) {
      setLoadingReadiness(false);
      return;
    }

    setLoadingReadiness(true);
    setReadinessError(null);
    try {
      const { data: sessionData, error: sessionError } = await supabase.auth.getSession();
      if (sessionError) throw sessionError;
      if (!sessionData.session) return;

      const { data, error } = await supabase.rpc('get_worker_readiness');
      if (error) throw error;
      setReadiness((data?.[0] as Record<string, unknown> | undefined) ?? null);
    } catch (error) {
      setReadinessError(
        isLikelyNetworkError(error)
          ? 'Readiness is unavailable while offline.'
          : 'Readiness could not be refreshed.',
      );
    } finally {
      setLoadingReadiness(false);
    }
  }, []);

  useEffect(() => {
    void loadReadiness();
  }, [loadReadiness]);

  const readinessView = homeReadinessPresentation(readiness);

  return (
    <SafeAreaView style={styles.safe}>
      <ScrollView contentContainerStyle={styles.container}>
        <Text style={styles.eyebrow}>QY WORKFORCE</Text>
        <Text style={styles.title}>Work that fits your schedule.</Text>
        <Text style={styles.subtitle}>Verified shifts, clear pay, simple attendance and one worker profile.</Text>

        <View
          style={styles.statusCard}
          accessible
          accessibilityLabel={`Deployment readiness. ${readinessView.label}. ${readinessView.detail}`}
        >
          <Text style={styles.statusTitle}>Deployment readiness</Text>
          {loadingReadiness ? (
            <View style={styles.loadingRow} accessibilityLiveRegion="polite">
              <ActivityIndicator color="#FFFFFF" />
              <Text style={styles.loadingText}>Checking verified status…</Text>
            </View>
          ) : (
            <>
              <Text style={styles.statusValue}>{readinessView.label}</Text>
              <Text style={styles.statusDetail}>{readinessView.detail}</Text>
            </>
          )}
          {readinessError ? (
            <View style={styles.refreshRow} accessibilityLiveRegion="polite">
              <Text style={styles.statusError}>{readinessError}</Text>
              <Pressable
                accessibilityRole="button"
                accessibilityLabel="Retry worker readiness refresh"
                onPress={() => void loadReadiness()}
                disabled={loadingReadiness}
                style={({ pressed }) => [styles.retryButton, pressed && styles.retryPressed]}
              >
                <Text style={styles.retryText}>Retry</Text>
              </Pressable>
            </View>
          ) : null}
          <Link href="/readiness" style={styles.link} accessibilityRole="link">View readiness →</Link>
        </View>

        {HOME_ACTIONS.map((card) => (
          <Link key={card.title} href={card.href} style={styles.card} accessibilityLabel={`${card.title}. ${card.body}`}>
            <View>
              <Text style={styles.cardTitle}>{card.title}</Text>
              <Text style={styles.cardBody}>{card.body}</Text>
              <Text style={styles.cardLink}>Open →</Text>
            </View>
          </Link>
        ))}
      </ScrollView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  safe: { flex: 1, backgroundColor: '#0A0A0A' },
  container: { padding: 24, gap: 16, paddingBottom: 48 },
  eyebrow: { color: '#A3A3A3', fontSize: 12, letterSpacing: 2 },
  title: { color: '#FFFFFF', fontSize: 34, fontWeight: '700', lineHeight: 40 },
  subtitle: { color: '#D4D4D4', fontSize: 17, lineHeight: 25, marginBottom: 8 },
  statusCard: { backgroundColor: '#171717', borderRadius: 18, padding: 20, gap: 7 },
  statusTitle: { color: '#A3A3A3', fontSize: 13 },
  statusValue: { color: '#FFFFFF', fontSize: 20, fontWeight: '600' },
  statusDetail: { color: '#B3B3B3', fontSize: 14, lineHeight: 20 },
  statusError: { color: '#FDE68A', fontSize: 13, lineHeight: 18, flex: 1 },
  loadingRow: { flexDirection: 'row', alignItems: 'center', gap: 10, minHeight: 44 },
  loadingText: { color: '#D4D4D4', fontSize: 14 },
  refreshRow: { flexDirection: 'row', alignItems: 'center', gap: 12, marginTop: 4 },
  retryButton: { minHeight: 44, minWidth: 64, alignItems: 'center', justifyContent: 'center', borderWidth: 1, borderColor: '#525252', borderRadius: 12, paddingHorizontal: 12 },
  retryPressed: { opacity: 0.75 },
  retryText: { color: '#FFFFFF', fontSize: 14, fontWeight: '700' },
  link: { color: '#FFFFFF', fontSize: 15, marginTop: 4, minHeight: 44, paddingVertical: 11 },
  card: { backgroundColor: '#111111', borderWidth: 1, borderColor: '#262626', borderRadius: 18, padding: 20 },
  cardTitle: { color: '#FFFFFF', fontSize: 18, fontWeight: '600' },
  cardBody: { color: '#B3B3B3', fontSize: 15, lineHeight: 22, marginTop: 8 },
  cardLink: { color: '#FFFFFF', fontSize: 14, fontWeight: '700', marginTop: 12 },
});
