import { useEffect, useMemo, useState } from 'react';
import { ActivityIndicator, Pressable, RefreshControl, ScrollView, StyleSheet, Text, View } from 'react-native';
import { router } from 'expo-router';
import { mobileErrorMessage } from '../lib/errors';
import { supabase } from '../lib/supabase';

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

function money(value: number) {
  return `S$${value.toFixed(2)}`;
}

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

    try {
      const { data: authData, error: authError } = await supabase.auth.getUser();
      if (authError) throw authError;
      if (!authData.user) {
        setItems([]);
        router.replace('/sign-in');
        return;
      }

      const { data, error: queryError } = await supabase
        .from('shift_assignments')
        .select('id,shifts(starts_at,roles(name),sites(name)),timesheets(id,status,payable_minutes,worker_amount,rejection_reason)')
        .eq('worker_id', authData.user.id)
        .is('cancelled_at', null);
      if (queryError) throw queryError;
      setItems((data as unknown as Assignment[]) ?? []);
    } catch (loadError) {
      setError(mobileErrorMessage(loadError, 'We could not refresh your earnings. Check your connection and try again.'));
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
  }

  useEffect(() => { void load(); }, []);

  const rows = useMemo(() => items.flatMap((assignment) =>
    (assignment.timesheets ?? []).map((timesheet) => ({ assignment, timesheet }))), [items]);

  const totals = useMemo(() => {
    let approved = 0;
    let pending = 0;
    for (const row of rows) {
      const amount = Number(row.timesheet.worker_amount ?? 0);
      if (row.timesheet.status === 'approved' || row.timesheet.status === 'payroll_ready' || row.timesheet.status === 'paid') approved += amount;
      else if (row.timesheet.status !== 'rejected') pending += amount;
    }
    return { approved, pending };
  }, [rows]);

  if (loading) return <View style={styles.center} accessibilityRole="progressbar"><ActivityIndicator /><Text style={styles.muted}>Loading earnings…</Text></View>;

  return (
    <ScrollView contentContainerStyle={styles.container} refreshControl={<RefreshControl refreshing={refreshing} onRefresh={() => void load(true)} />}>
      <Text style={styles.title}>Earnings</Text>
      <Text style={styles.subtitle}>Track estimated shift earnings and timesheet payment status.</Text>
      {error && <View style={styles.warning} accessibilityRole="alert"><Text style={styles.warningText}>{error}</Text><Pressable accessibilityRole="button" accessibilityState={{ disabled: refreshing }} disabled={refreshing} style={styles.retryButton} onPress={() => void load(true)}><Text style={styles.retryButtonText}>{refreshing ? 'Refreshing…' : 'Refresh earnings'}</Text></Pressable></View>}

      <View style={styles.summaryRow}>
        <View style={styles.summaryCard} accessible accessibilityLabel={`Approved earnings ${money(totals.approved)}`}>
          <Text style={styles.summaryLabel}>Approved</Text>
          <Text style={styles.summaryValue}>{money(totals.approved)}</Text>
        </View>
        <View style={styles.summaryCard} accessible accessibilityLabel={`Pending earnings ${money(totals.pending)}`}>
          <Text style={styles.summaryLabel}>Pending</Text>
          <Text style={styles.summaryValue}>{money(totals.pending)}</Text>
        </View>
      </View>

      {rows.length === 0 && <View style={styles.card}><Text style={styles.cardTitle}>No earnings yet</Text><Text style={styles.muted}>Completed shifts with a timesheet will appear here.</Text><Pressable accessibilityRole="button" style={styles.primary} onPress={() => router.push('/my-shifts')}><Text style={styles.primaryText}>View my shifts</Text></Pressable></View>}

      {rows.map(({ assignment, timesheet }) => {
        const shift = assignment.shifts;
        const hours = Math.floor(timesheet.payable_minutes / 60);
        const minutes = timesheet.payable_minutes % 60;
        return <View key={timesheet.id} style={styles.card}>
          <View style={styles.row}><Text style={styles.cardTitle}>{shift?.roles?.name ?? 'Shift'}</Text><Text style={styles.badge}>{timesheet.status.replaceAll('_', ' ')}</Text></View>
          <Text style={styles.site}>{shift?.sites?.name ?? 'Work site'}</Text>
          {shift?.starts_at && <Text style={styles.muted}>{new Date(shift.starts_at).toLocaleDateString()}</Text>}
          <Text style={styles.amount}>{money(Number(timesheet.worker_amount ?? 0))}</Text>
          <Text style={styles.muted}>{hours}h {minutes}m payable time</Text>
          {timesheet.rejection_reason && <Text style={styles.error}>Action needed: {timesheet.rejection_reason}</Text>}
          <Pressable accessibilityRole="button" style={styles.secondary} onPress={() => router.push({ pathname: '/assignment', params: { assignmentId: assignment.id } })}><Text style={styles.secondaryText}>View shift details</Text></Pressable>
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
  warning: { backgroundColor: '#fff7ed', borderRadius: 12, padding: 12 }, warningText: { color: '#9a3412', fontWeight: '600' }, retryButton: { borderWidth: 1, borderColor: '#fdba74', borderRadius: 10, paddingVertical: 10, minHeight: 44, alignItems: 'center', justifyContent: 'center', marginTop: 10 }, retryButtonText: { color: '#9a3412', fontWeight: '800' }, error: { color: '#9b2c2c', fontWeight: '600' },
});
