import { useEffect, useState } from 'react';
import { ActivityIndicator, Alert, Pressable, RefreshControl, ScrollView, StyleSheet, Text, View } from 'react-native';
import { router } from 'expo-router';
import { supabase } from '../lib/supabase';

type Assignment = {
  id: string;
  accepted_at: string | null;
  cancelled_at: string | null;
  shifts: {
    id: string;
    starts_at: string;
    ends_at: string;
    status: string;
    worker_rate: number | null;
    sites: { name: string; address: string | null } | null;
    roles: { name: string } | null;
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
    id: 'demo-assignment', accepted_at: new Date().toISOString(), cancelled_at: null,
    shifts: {
      id: 'demo-shift', starts_at: new Date(Date.now() + 86400000).toISOString(),
      ends_at: new Date(Date.now() + 86400000 + 8 * 3600000).toISOString(), status: 'assigned', worker_rate: 16,
      sites: { name: 'Demo Hotel', address: 'Singapore' }, roles: { name: 'F&B Service Crew' },
    }, timesheets: [],
  },
];

export default function MyShiftsScreen() {
  const [items, setItems] = useState<Assignment[]>([]);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState<string | null>(null);

  async function load(asRefresh = false) {
    if (asRefresh) setRefreshing(true); else setLoading(true);
    setError(null);
    if (!supabase) { setItems(demo); setLoading(false); setRefreshing(false); return; }
    const { data: authData } = await supabase.auth.getUser();
    if (!authData.user) { setItems([]); setLoading(false); setRefreshing(false); router.replace('/sign-in'); return; }
    const { data, error: queryError } = await supabase
      .from('shift_assignments')
      .select('id,accepted_at,cancelled_at,shifts(id,starts_at,ends_at,status,worker_rate,sites(name,address),roles(name)),timesheets(id,status,payable_minutes,worker_amount,rejection_reason)')
      .eq('worker_id', authData.user.id)
      .is('cancelled_at', null)
      .order('accepted_at', { ascending: false });
    if (queryError) setError('We could not refresh your shifts. Check your connection and pull down to retry.');
    else setItems((data as unknown as Assignment[]) ?? []);
    setLoading(false);
    setRefreshing(false);
  }

  useEffect(() => { void load(); }, []);

  async function submitTimesheet(assignmentId: string) {
    if (!supabase) { Alert.alert('Demo mode', 'Timesheet submission will be enabled after staging is connected.'); return; }
    setSubmitting(assignmentId);
    const { error: rpcError } = await supabase.rpc('submit_timesheet', { p_assignment_id: assignmentId });
    setSubmitting(null);
    if (rpcError) { Alert.alert('Cannot submit yet', rpcError.message); return; }
    Alert.alert('Submitted', 'Your timesheet is now awaiting supervisor approval.');
    await load();
  }

  if (loading) return <View style={styles.center} accessibilityRole="progressbar"><ActivityIndicator /><Text style={styles.muted}>Loading shifts…</Text></View>;

  return <ScrollView
    contentContainerStyle={styles.container}
    refreshControl={<RefreshControl refreshing={refreshing} onRefresh={() => void load(true)} />}
  >
    <Text style={styles.title}>My Shifts</Text>
    <Text style={styles.subtitle}>Your accepted work, attendance and payment status.</Text>
    {error && <View style={styles.warning} accessibilityRole="alert"><Text style={styles.warningText}>{error}</Text></View>}
    {items.length === 0 && <View style={styles.card}><Text style={styles.cardTitle}>No accepted shifts yet</Text><Text style={styles.muted}>Find an open shift and accept it to see it here.</Text><Pressable accessibilityRole="button" style={styles.primary} onPress={() => router.push('/shifts')}><Text style={styles.primaryText}>Find a shift</Text></Pressable></View>}
    {items.map((a) => {
      const sh = a.shifts; const ts = a.timesheets?.[0];
      if (!sh) return null;
      const start = new Date(sh.starts_at); const end = new Date(sh.ends_at);
      return <View key={a.id} style={styles.card} accessible accessibilityLabel={`${sh.roles?.name ?? 'Shift'} at ${sh.sites?.name ?? 'site'}`}>
        <View style={styles.row}><Text style={styles.cardTitle}>{sh.roles?.name ?? 'Shift'}</Text><Text style={styles.badge}>{ts?.status ?? sh.status}</Text></View>
        <Text style={styles.site}>{sh.sites?.name ?? 'Site'}</Text>
        <Text style={styles.muted}>{start.toLocaleString()} – {end.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}</Text>
        {sh.sites?.address && <Text style={styles.muted}>{sh.sites.address}</Text>}
        {ts && <Text style={styles.pay}>{Math.floor(ts.payable_minutes / 60)}h {ts.payable_minutes % 60}m · Est. S${Number(ts.worker_amount ?? 0).toFixed(2)}</Text>}
        {ts?.rejection_reason && <Text style={styles.error}>Action needed: {ts.rejection_reason}</Text>}
        <View style={styles.actions}>
          <Pressable accessibilityRole="button" style={styles.secondary} onPress={() => router.push({ pathname: '/assignment', params: { assignmentId: a.id } })}><Text style={styles.secondaryText}>Details</Text></Pressable>
          <Pressable accessibilityRole="button" style={styles.secondary} onPress={() => router.push({ pathname: '/attendance', params: { assignmentId: a.id } })}><Text style={styles.secondaryText}>Attendance</Text></Pressable>
        </View>
        {(!ts || ts.status === 'draft' || ts.status === 'rejected') && <Pressable accessibilityRole="button" accessibilityState={{ disabled: submitting === a.id }} style={[styles.primary, submitting === a.id && styles.disabled]} disabled={submitting === a.id} onPress={() => submitTimesheet(a.id)}><Text style={styles.primaryText}>{submitting === a.id ? 'Submitting…' : 'Submit timesheet'}</Text></Pressable>}
      </View>;
    })}
  </ScrollView>;
}

const styles = StyleSheet.create({
  container: { padding: 20, gap: 14, paddingBottom: 48 }, center: { flex: 1, alignItems: 'center', justifyContent: 'center', gap: 10 },
  title: { fontSize: 30, fontWeight: '800' }, subtitle: { fontSize: 16, color: '#5f6670', marginBottom: 6 },
  card: { borderWidth: 1, borderColor: '#e6e8eb', borderRadius: 18, padding: 16, gap: 9 }, row: { flexDirection: 'row', justifyContent: 'space-between', gap: 12 },
  cardTitle: { fontSize: 18, fontWeight: '700', flex: 1 }, site: { fontSize: 16, fontWeight: '600' }, muted: { color: '#68707b' },
  badge: { fontSize: 12, fontWeight: '700', textTransform: 'uppercase' }, pay: { marginTop: 4, fontWeight: '700' }, error: { color: '#9b2c2c', fontWeight: '600' },
  actions: { flexDirection: 'row', gap: 10, marginTop: 6 }, primary: { borderRadius: 12, padding: 13, backgroundColor: '#111', alignItems: 'center' }, primaryText: { color: '#fff', fontWeight: '700' },
  secondary: { flex: 1, borderRadius: 12, padding: 13, borderWidth: 1, borderColor: '#c9cdd2', alignItems: 'center' }, secondaryText: { fontWeight: '700' },
  disabled: { opacity: 0.55 }, warning: { backgroundColor: '#fff7ed', borderRadius: 12, padding: 12 }, warningText: { color: '#9a3412', fontWeight: '600' },
});
