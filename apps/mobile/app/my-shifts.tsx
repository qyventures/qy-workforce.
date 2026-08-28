import { useEffect, useState } from 'react';
import { ActivityIndicator, Alert, Pressable, RefreshControl, ScrollView, StyleSheet, Text, View } from 'react-native';
import { router } from 'expo-router';
import { isLikelyNetworkError, mobileErrorMessage } from '../lib/errors';
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

const demo: Assignment[] = [{
  id: 'demo-assignment', accepted_at: new Date().toISOString(), cancelled_at: null,
  shifts: { id: 'demo-shift', starts_at: new Date(Date.now() + 86400000).toISOString(), ends_at: new Date(Date.now() + 86400000 + 8 * 3600000).toISOString(), status: 'assigned', worker_rate: 16, sites: { name: 'Demo Hotel', address: 'Singapore' }, roles: { name: 'F&B Service Crew' } }, timesheets: [],
}];

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
    try {
      const { data: authData, error: authError } = await supabase.auth.getUser();
      if (authError) throw authError;
      if (!authData.user) { setItems([]); router.replace('/sign-in'); return; }
      const { data, error: queryError } = await supabase
        .from('shift_assignments')
        .select('id,accepted_at,cancelled_at,shifts(id,starts_at,ends_at,status,worker_rate,sites(name,address),roles(name)),timesheets(id,status,payable_minutes,worker_amount,rejection_reason)')
        .eq('worker_id', authData.user.id)
        .order('accepted_at', { ascending: false });
      if (queryError) throw queryError;
      setItems((data as unknown as Assignment[]) ?? []);
    } catch (loadFailure) {
      setError(mobileErrorMessage(loadFailure, 'We could not refresh your shifts. Pull down to retry.'));
    } finally {
      setLoading(false); setRefreshing(false);
    }
  }

  useEffect(() => { void load(); }, []);

  async function submitTimesheet(assignmentId: string) {
    if (!supabase) { Alert.alert('Demo mode', 'Timesheet submission will be enabled after staging is connected.'); return; }
    setSubmitting(assignmentId); setError(null);
    try {
      const { error: rpcError } = await supabase.rpc('submit_timesheet', { p_assignment_id: assignmentId });
      if (rpcError) throw rpcError;
      Alert.alert('Submitted', 'Your timesheet is now awaiting supervisor approval.');
      await load();
    } catch (submitError) {
      if (isLikelyNetworkError(submitError)) {
        setError('Connection interrupted while submitting. Refresh My Shifts before retrying so you do not submit the same timesheet twice.');
        Alert.alert('Could not confirm submission', 'The connection dropped while saving your timesheet. Refresh My Shifts first to check whether it was submitted before trying again.');
      } else {
        Alert.alert('Cannot submit yet', mobileErrorMessage(submitError, 'The timesheet could not be submitted.'));
      }
    } finally { setSubmitting(null); }
  }

  if (loading) return <View style={styles.center} accessibilityRole="progressbar"><ActivityIndicator /><Text style={styles.muted}>Loading shifts…</Text></View>;

  return <ScrollView contentContainerStyle={styles.container} refreshControl={<RefreshControl refreshing={refreshing} onRefresh={() => void load(true)} />}>
    <Text style={styles.title}>My Shifts</Text>
    <Text style={styles.subtitle}>Your accepted work, attendance and payment status.</Text>
    {error && <View style={styles.warning} accessibilityRole="alert"><Text style={styles.warningText}>{error}</Text><Pressable accessibilityRole="button" accessibilityState={{ disabled: refreshing }} disabled={refreshing} style={styles.retryButton} onPress={() => void load(true)}><Text style={styles.retryButtonText}>{refreshing ? 'Refreshing…' : 'Refresh status'}</Text></Pressable></View>}
    {items.length === 0 && <View style={styles.card}><Text style={styles.cardTitle}>No accepted shifts yet</Text><Text style={styles.muted}>Find an open shift and accept it to see it here.</Text><Pressable accessibilityRole="button" style={styles.primary} onPress={() => router.push('/shifts')}><Text style={styles.primaryText}>Find a shift</Text></Pressable></View>}
    {items.map((a) => {
      const sh = a.shifts; const ts = a.timesheets?.[0]; if (!sh) return null;
      const cancelled = a.cancelled_at !== null || sh.status === 'cancelled';
      const start = new Date(sh.starts_at); const end = new Date(sh.ends_at);
      return <View key={a.id} style={styles.card} accessible accessibilityLabel={`${sh.roles?.name ?? 'Shift'} at ${sh.sites?.name ?? 'site'}`}>
        <View style={styles.row}><Text style={styles.cardTitle}>{sh.roles?.name ?? 'Shift'}</Text><Text style={[styles.badge, cancelled && styles.cancelledBadge]}>{cancelled ? 'Cancelled' : ts?.status ?? sh.status}</Text></View>
        <Text style={styles.site}>{sh.sites?.name ?? 'Site'}</Text>
        <Text style={styles.muted}>{start.toLocaleString()} – {end.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}</Text>
        {sh.sites?.address && <Text style={styles.muted}>{sh.sites.address}</Text>}
        {ts && <Text style={styles.pay}>{Math.floor(ts.payable_minutes / 60)}h {ts.payable_minutes % 60}m · Est. S${Number(ts.worker_amount ?? 0).toFixed(2)}</Text>}
        {ts?.rejection_reason && <Text style={styles.error}>Action needed: {ts.rejection_reason}</Text>}
        {cancelled && <Text style={styles.cancelledNotice}>Operations cancelled this shift. Do not travel to the site or clock attendance.</Text>}
        <View style={styles.actions}><Pressable accessibilityRole="button" style={styles.secondary} onPress={() => router.push({ pathname: '/assignment', params: { assignmentId: a.id } })}><Text style={styles.secondaryText}>Details</Text></Pressable>{!cancelled && <Pressable accessibilityRole="button" style={styles.secondary} onPress={() => router.push({ pathname: '/attendance', params: { assignmentId: a.id } })}><Text style={styles.secondaryText}>Attendance</Text></Pressable>}</View>
        {!cancelled && (!ts || ts.status === 'draft' || ts.status === 'rejected') && <Pressable accessibilityRole="button" accessibilityState={{ disabled: submitting === a.id }} style={[styles.primary, submitting === a.id && styles.disabled]} disabled={submitting === a.id} onPress={() => submitTimesheet(a.id)}><Text style={styles.primaryText}>{submitting === a.id ? 'Submitting…' : 'Submit timesheet'}</Text></Pressable>}
      </View>;
    })}
  </ScrollView>;
}

const styles = StyleSheet.create({
  container: { padding: 20, gap: 14, paddingBottom: 48 }, center: { flex: 1, alignItems: 'center', justifyContent: 'center', gap: 10 }, title: { fontSize: 30, fontWeight: '800' }, subtitle: { fontSize: 16, color: '#5f6670', marginBottom: 6 }, card: { borderWidth: 1, borderColor: '#e6e8eb', borderRadius: 18, padding: 16, gap: 9 }, row: { flexDirection: 'row', justifyContent: 'space-between', gap: 12 }, cardTitle: { fontSize: 18, fontWeight: '700', flex: 1 }, site: { fontSize: 16, fontWeight: '600' }, muted: { color: '#68707b' }, badge: { fontSize: 12, fontWeight: '700', textTransform: 'uppercase' }, pay: { marginTop: 4, fontWeight: '700' }, error: { color: '#9b2c2c', fontWeight: '600' }, actions: { flexDirection: 'row', gap: 10, marginTop: 6 }, primary: { borderRadius: 12, padding: 13, minHeight: 48, backgroundColor: '#111', alignItems: 'center', justifyContent: 'center' }, primaryText: { color: '#fff', fontWeight: '700' }, secondary: { flex: 1, borderRadius: 12, padding: 13, minHeight: 48, borderWidth: 1, borderColor: '#c9cdd2', alignItems: 'center', justifyContent: 'center' }, secondaryText: { fontWeight: '700' }, disabled: { opacity: 0.55 }, warning: { backgroundColor: '#fff7ed', borderRadius: 12, padding: 12 }, warningText: { color: '#9a3412', fontWeight: '600' }, retryButton: { borderWidth: 1, borderColor: '#fdba74', borderRadius: 10, paddingVertical: 10, paddingHorizontal: 12, minHeight: 44, alignItems: 'center', justifyContent: 'center', marginTop: 10 }, retryButtonText: { color: '#9a3412', fontWeight: '800' }, cancelledBadge: { color: '#b42318' }, cancelledNotice: { color: '#b42318', backgroundColor: '#fff1f0', borderRadius: 10, padding: 10, fontWeight: '700', lineHeight: 20 },
});
