import { useEffect, useState } from 'react';
import { Link } from 'expo-router';
import { ActivityIndicator, SafeAreaView, ScrollView, StyleSheet, Text, View } from 'react-native';
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
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let active = true;
    async function load() {
      if (!supabase) return;
      const { data, error: rpcError } = await supabase.rpc('get_worker_readiness');
      if (!active) return;
      if (rpcError) setError('Unable to load live readiness status.');
      else if (data?.[0]) setState(data[0] as Readiness);
      setLoading(false);
    }
    load();
    return () => { active = false; };
  }, []);

  const checks = [
    ['Identity verified', state.identity_verified],
    ['Residency verified', state.residency_verified],
    ['Eligible to work', state.work_eligibility === 'eligible'],
    ['Approved role', state.approved_roles > 0],
    ['Required training complete', state.outstanding_training === 0],
    ['Vetting clear', state.failed_vetting === 0],
    ['Required consent recorded', state.required_consents_complete],
  ] as const;

  return (
    <SafeAreaView style={styles.safe}>
      <ScrollView contentContainerStyle={styles.container}>
        <Text style={styles.eyebrow}>WORKER READINESS</Text>
        <Text style={styles.title}>{state.deployable ? 'Ready for deployment' : 'Complete your readiness checks'}</Text>
        <Text style={styles.subtitle}>Your shift eligibility is calculated from verified records. Sensitive identity details are not shown here.</Text>

        {loading ? <ActivityIndicator /> : null}
        {error ? <Text style={styles.error}>{error}</Text> : null}

        <View style={styles.card}>
          <Text style={styles.cardTitle}>Current status</Text>
          <Text style={styles.status}>{state.deployable ? 'DEPLOYABLE' : state.worker_status.toUpperCase()}</Text>
          <Text style={styles.meta}>{state.approved_roles} approved role(s) · {state.verified_skills} verified skill(s)</Text>
        </View>

        <View style={styles.card}>
          <Text style={styles.cardTitle}>Readiness checklist</Text>
          {checks.map(([label, ok]) => (
            <View key={label} style={styles.row}>
              <Text style={styles.rowLabel}>{label}</Text>
              <Text style={ok ? styles.pass : styles.pending}>{ok ? 'Ready' : 'Pending'}</Text>
            </View>
          ))}
        </View>

        <Link href="/onboarding" style={styles.link}>Continue onboarding →</Link>
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
  card: { backgroundColor: '#111111', borderWidth: 1, borderColor: '#262626', borderRadius: 18, padding: 20, gap: 12 },
  cardTitle: { color: '#A3A3A3', fontSize: 13 },
  status: { color: '#FFFFFF', fontSize: 22, fontWeight: '700' },
  meta: { color: '#B3B3B3', fontSize: 14 },
  row: { flexDirection: 'row', justifyContent: 'space-between', gap: 16, paddingVertical: 6 },
  rowLabel: { color: '#E5E5E5', fontSize: 15, flex: 1 },
  pass: { color: '#FFFFFF', fontWeight: '700' },
  pending: { color: '#A3A3A3', fontWeight: '600' },
  error: { color: '#FCA5A5', fontSize: 14 },
  link: { color: '#FFFFFF', fontSize: 16, fontWeight: '700', paddingVertical: 8 },
});
