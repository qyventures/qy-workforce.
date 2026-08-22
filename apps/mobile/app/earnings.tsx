import { useEffect, useMemo, useState } from 'react';
import { ActivityIndicator, Pressable, RefreshControl, ScrollView, StyleSheet, Text, View } from 'react-native';
import { router } from 'expo-router';
import { supabase } from '../lib/supabase';
import { formatMoney, payableDuration, sumEarnings } from '../lib/earnings.mjs';

type Assignment = {
  id: string;
  shifts: {
    starts_at: string;
    roles: { name: string } | null;
    sites: { name: string } | null;
  } | null;
  timesheets?: Array<{
    id: string;
    status: string;
    payable_minutes: number;
    worker_amount: number | null;
    rejection_reason: string | null;
  }>;
};

const demo: Assignment[] = [
  {
    id: 'demo-earnings',
    shifts: { starts_at: new Date().toISOString(), roles: { name: 'F&B Service Crew' }, sites: { name: 'Demo Hotel' } },
    timesheets: [{ id: 'demo-timesheet', status: 'approved', payable_minutes: 480, worker_amount: 128, rejection_reason: null }],
  },
];

export default function EarningsScreen() {
  const [items, setItems] = useState<Assignment[]>([]);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function load(asRefresh = false) {
    if (asRefresh) setRefreshing(true); else setLoading(true);
    setError(null);
    if (!supabase) {
      setItems(demo);
      setLoading(false);
      setRefreshing(false);
      return;
    }
    const { data: authData } = await supabase.auth.getUser();
    if (!authData.user) {
      setItems([]);
      setLoading(false);
      setRefreshing(false);
      router.replace('/sign-in');
      return;
    }
    const { data, error: queryError } = await supabase
      .from('shift_assignments')
      .select('id,shifts(starts_at,roles(name),sites(name)),timesheets(id,status,payable_minutes,worker_amount,rejection_reason)')
      .eq('worker_id', authData.user.id)
      .is('cancelled_at', null);
    if (queryError) {
      setError(items.length > 0
        ? 'You are seeing your last loaded earnings. We could not refresh them; check your connection and try again.'
        : 'We could not load your earnings. Check your connection and try again.');
    } else {
      setItems((data as unknown as Assignment[]) ?? []);
    }
    setLoading(false);
    setRefreshing(false);
  }

  useEffect(() => { void load(); }, []);

  const rows = useMemo(() => items.flatMap((assignment) =>
    (assignment.timesheets ?? []).map((timesheet) => ({ assignment, timesheet }))), [items]);

  const totals = useMemo(() => sumEarnings(rows), [rows]);

  if (loading) return <View style={styles.center} accessibilityRole="progressbar"><ActivityIndicator /><Text style={styles.muted}>Loading earnings…</Text></View>;

  return (
    <ScrollView contentContainerStyle={styles.container} refreshControl={<RefreshControl refreshing={refreshing} onRefresh={() => void load(true)} />}>
      <Text style={styles.title} accessibilityRole="header">Earnings</Text>
      <Text style={styles.subtitle}>Track estimated shift earnings and timesheet payment status.</Text>
      {error && <View style={styles.warning} accessibilityRole="alert"><Text style={styles.warningText}>{error}</Text><Pressable accessibilityRole="button" accessibilityLabel="Retry loading earnings" style={styles.retry} onPress={() => void load(true)}><Text style={styles.retryText}>Retry</Text></Pressable></View>}

      <View style={styles.summaryRow}>
        <View style={styles.summaryCard} accessible accessibilityLabel={`Approved earnings ${formatMoney(totals.approved)}`}>
          <Text style={styles.summaryLabel}>Approved</Text>
          <Text style={styles.summaryValue}>{formatMoney(totals.approved)}</Text>
        </View>
        <View style={styles.summaryCard} accessible accessibilityLabel={`Pending earnings ${formatMoney(totals.pending)}`}>
          <Text style={styles.summaryLabel}>Pending</Text>
          <Text style={styles.summaryValue}>{formatMoney(totals.pending)}</Text>
        </View>
      </View>

      {rows.length === 0 && <View style={styles.card}><Text style={styles.cardTitle}>No earnings yet</Text><Text style={styles.muted}>Completed shifts with a timesheet will appear here.</Text><Pressable accessibilityRole="button" style={styles.primary} onPress={() => router.push('/my-shifts')}><Text style={styles.primaryText}>View my shifts</Text></Pressable></View>}

      {rows.map(({ assignment, timesheet }) => {
        const shift = assignment.shifts;
        return <View key={timesheet.id} style={styles.card} accessible accessibilityLabel={`${shift?.roles?.name ?? 'Shift'}, ${formatMoney(Number(timesheet.worker_amount ?? 0))}, ${timesheet.status.replaceAll('_', ' ')}`}>
          <View style={styles.row}><Text style={styles.cardTitle}>{shift?.roles?.name ?? 'Shift'}</Text><Text style={styles.badge}>{timesheet.status.replaceAll('_', ' ')}</Text></View>
          <Text style={styles.site}>{shift?.sites?.name ?? 'Work site'}</Text>
          {shift?.starts_at && <Text style={styles.muted}>{new Date(shift.starts_at).toLocaleDateString()}</Text>}
          <Text style={styles.amount}>{formatMoney(Number(timesheet.worker_amount ?? 0))}</Text>
          <Text style={styles.muted}>{payableDuration(timesheet.payable_minutes)} payable time</Text>
          {timesheet.rejection_reason && <Text style={styles.error}>Action needed: {timesheet.rejection_reason}</Text>}
          <Pressable accessibilityRole="button" accessibilityLabel="View shift details" style={styles.secondary} onPress={() => router.push({ pathname: '/assignment', params: { assignmentId: assignment.id } })}><Text style={styles.secondaryText}>View shift details</Text></Pressable>
        </View>;
      })}
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  container: { padding: 20, gap: 14, paddingBottom: 48 },
  center: { flex: 1, alignItems: 'center', justifyContent: 'center', gap: 10 },
  title: { fontSize: 30, fontWeight: '800' }, subtitle: { fontSize: 16, color: '#5f6670', marginBottom: 4 }, muted: { color: '#68707b' },
  summaryRow: { flexDirection: 'row', gap: 12 }, summaryCard: { flex: 1, borderRadius: 16, padding: 16, backgroundColor: '#111' }, summaryLabel: { color: '#b6bbc2', fontSize: 13 }, summaryValue: { color: '#fff', fontSize: 24, fontWeight: '800', marginTop: 5 },
  card: { borderWidth: 1, borderColor: '#e6e8eb', borderRadius: 18, padding: 16, gap: 8 }, row: { flexDirection: 'row', justifyContent: 'space-between', gap: 12 }, cardTitle: { flex: 1, fontSize: 18, fontWeight: '700' }, site: { fontSize: 16, fontWeight: '600' }, badge: { fontSize: 12, fontWeight: '700', textTransform: 'uppercase' }, amount: { fontSize: 24, fontWeight: '800', marginTop: 4 },
  primary: { marginTop: 6, borderRadius: 12, padding: 13, backgroundColor: '#111', alignItems: 'center' }, primaryText: { color: '#fff', fontWeight: '700' }, secondary: { marginTop: 6, borderRadius: 12, padding: 12, borderWidth: 1, borderColor: '#c9cdd2', alignItems: 'center' }, secondaryText: { fontWeight: '700' },
  warning: { backgroundColor: '#fff7ed', borderRadius: 12, padding: 12, gap: 10 }, warningText: { color: '#9a3412', fontWeight: '600' }, retry: { alignSelf: 'flex-start', borderRadius: 10, borderWidth: 1, borderColor: '#c2410c', paddingHorizontal: 12, paddingVertical: 8 }, retryText: { color: '#9a3412', fontWeight: '700' }, error: { color: '#9b2c2c', fontWeight: '600' },
});
