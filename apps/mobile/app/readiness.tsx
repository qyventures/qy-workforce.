import { useCallback, useEffect, useState } from 'react';
import { Link, router } from 'expo-router';
import {
  ActivityIndicator,
  RefreshControl,
  SafeAreaView,
  ScrollView,
  StyleSheet,
  Text,
  View,
} from 'react-native';
import { isLikelyNetworkError } from '../lib/errors';
import { supabase } from '../lib/supabase';

type Readiness = {
  worker_status: string;
  identity_verified: boolean;
  residency_verified: boolean;
  work_eligibility: string;
  approved_roles: number;
  verified_skills: number;
  outstanding_training: number;
  failed_vetting: number;
  required_consents_complete: boolean;
  deployable: boolean;
};

const demo: Readiness = {
  worker_status: 'pending',
  identity_verified: false,
  residency_verified: false,
  work_eligibility: 'unknown',
  approved_roles: 0,
  verified_skills: 0,
  outstanding_training: 0,
  failed_vetting: 0,
  required_consents_complete: false,
  deployable: false,
};

export default function ReadinessScreen() {
  const [state, setState] = useState<Readiness>(demo);
  const [loading, setLoading] = useState(Boolean(supabase));
  const [refreshing, setRefreshing] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [offline, setOffline] = useState(false);

  const load = useCallback(async (manual = false) => {
    if (!supabase) {
      setLoading(false);
      return;
    }

    if (manual) setRefreshing(true);
    else setLoading(true);
    setError(null);
    setOffline(false);

    try {
      const { data: sessionData, error: sessionError } = await supabase.auth.getSession();
      if (sessionError) throw sessionError;
      if (!sessionData.session) {
        router.replace('/sign-in');
        return;
      }

      const { data, error: rpcError } = await supabase.rpc('get_worker_readiness');
      if (rpcError) throw rpcError;

      if (data?.[0]) {
        setState(data[0] as Readiness);
      } else {
        setError('Your readiness status is not available yet. Complete onboarding or try again shortly.');
      }
    } catch (loadError) {
      const networkError = isLikelyNetworkError(loadError);
      setOffline(networkError);
      setError(
        networkError
          ? 'You may be offline or on an unstable connection. Reconnect, then refresh your readiness status.'
          : 'Unable to load your readiness status right now. Please try again.',
      );
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  const checks = [
    ['Identity verified', state.identity_verified],
    ['Residency verified', state.residency_verified],
    ['Eligible to work', state.work_eligibility === 'eligible'],
    ['Approved role', state.approved_roles > 0],
    ['Required training complete', state.outstanding_training === 0],
    ['Vetting clear', state.failed_vetting === 0],
    ['Required consent recorded', state.required_consents_complete],
  ] as const;

  const readyCount = checks.filter(([, ok]) => ok).length;

  return (
    <SafeAreaView style={styles.safe}>
      <ScrollView
        contentContainerStyle={styles.container}
        refreshControl={(
          <RefreshControl
            refreshing={refreshing}
            onRefresh={() => void load(true)}
            tintColor="#FFFFFF"
            accessibilityLabel="Refresh worker readiness status"
          />
        )}
      >
        <Text style={styles.eyebrow}>WORKER READINESS</Text>
        <Text style={styles.title}>{state.deployable ? 'Ready for deployment' : 'Complete your readiness checks'}</Text>
        <Text style={styles.subtitle}>
          Your shift eligibility is calculated from verified server records. Sensitive identity details are not shown here.
        </Text>

        {loading ? (
          <View style={styles.loadingRow} accessibilityLiveRegion="polite">
            <ActivityIndicator color="#FFFFFF" />
            <Text style={styles.loadingText}>Checking readiness…</Text>
          </View>
        ) : null}

        {error ? (
          <View style={offline ? styles.warningBox : styles.errorBox} accessibilityLiveRegion="assertive">
            <Text style={offline ? styles.warningText : styles.error}>{error}</Text>
            <Text style={styles.helper}>Pull down to refresh.</Text>
          </View>
        ) : null}

        <View style={styles.card} accessible accessibilityLabel={`Worker status ${state.deployable ? 'deployable' : state.worker_status}. ${readyCount} of ${checks.length} readiness checks complete.`}>
          <Text style={styles.cardTitle}>Current status</Text>
          <Text style={styles.status}>{state.deployable ? 'DEPLOYABLE' : state.worker_status.toUpperCase()}</Text>
          <Text style={styles.meta}>{state.approved_roles} approved role(s) · {state.verified_skills} verified skill(s)</Text>
          <Text style={styles.progress}>{readyCount} of {checks.length} readiness checks complete</Text>
        </View>

        <View style={styles.card}>
          <Text style={styles.cardTitle}>Readiness checklist</Text>
          {checks.map(([label, ok]) => (
            <View key={label} style={styles.row} accessible accessibilityLabel={`${label}: ${ok ? 'Ready' : 'Pending'}`}>
              <Text style={styles.rowLabel}>{label}</Text>
              <Text style={ok ? styles.pass : styles.pending}>{ok ? 'Ready' : 'Pending'}</Text>
            </View>
          ))}
        </View>

        {state.deployable ? (
          <Link href="/shifts" style={styles.primaryLink} accessibilityRole="link" accessibilityLabel="Find available shifts">
            Find available shifts →
          </Link>
        ) : (
          <Link href="/onboarding" style={styles.primaryLink} accessibilityRole="link" accessibilityLabel="Continue worker onboarding">
            Continue onboarding →
          </Link>
        )}
        <Link href="/my-shifts" style={styles.secondaryLink} accessibilityRole="link" accessibilityLabel="View my shifts">
          View my shifts
        </Link>
      </ScrollView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  safe: { flex: 1, backgroundColor: '#0A0A0A' },
  container: { padding: 24, gap: 16 },
  eyebrow: { color: '#A3A3A3', fontSize: 12, letterSpacing: 2 },
  title: { color: '#FFFFFF', fontSize: 30, fontWeight: '700', lineHeight: 36 },
  subtitle: { color: '#B3B3B3', fontSize: 15, lineHeight: 22 },
  loadingRow: { flexDirection: 'row', alignItems: 'center', gap: 10, minHeight: 44 },
  loadingText: { color: '#D4D4D4', fontSize: 14 },
  card: { backgroundColor: '#111111', borderWidth: 1, borderColor: '#262626', borderRadius: 18, padding: 20, gap: 12 },
  cardTitle: { color: '#A3A3A3', fontSize: 13 },
  status: { color: '#FFFFFF', fontSize: 22, fontWeight: '700' },
  meta: { color: '#B3B3B3', fontSize: 14 },
  progress: { color: '#E5E5E5', fontSize: 14, fontWeight: '600' },
  row: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', gap: 16, minHeight: 44, paddingVertical: 6 },
  rowLabel: { color: '#E5E5E5', fontSize: 15, flex: 1 },
  pass: { color: '#FFFFFF', fontWeight: '700' },
  pending: { color: '#A3A3A3', fontWeight: '600' },
  errorBox: { borderWidth: 1, borderColor: '#7F1D1D', borderRadius: 14, padding: 14, gap: 6 },
  warningBox: { borderWidth: 1, borderColor: '#854D0E', borderRadius: 14, padding: 14, gap: 6 },
  error: { color: '#FCA5A5', fontSize: 14, lineHeight: 20 },
  warningText: { color: '#FDE68A', fontSize: 14, lineHeight: 20 },
  helper: { color: '#A3A3A3', fontSize: 13 },
  primaryLink: { color: '#FFFFFF', fontSize: 16, fontWeight: '700', paddingVertical: 14, minHeight: 44 },
  secondaryLink: { color: '#D4D4D4', fontSize: 15, fontWeight: '600', paddingVertical: 14, minHeight: 44 },
});
