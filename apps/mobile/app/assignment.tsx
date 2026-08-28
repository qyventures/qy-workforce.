import { useCallback, useEffect, useState } from 'react';
import { ActivityIndicator, Pressable, RefreshControl, ScrollView, StyleSheet, Text, View } from 'react-native';
import { router, useLocalSearchParams } from 'expo-router';
import { supabase } from '../lib/supabase';

type AssignmentDetail = {
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

const demo: AssignmentDetail = {
  id: 'demo-assignment',
  accepted_at: new Date().toISOString(),
  cancelled_at: null,
  shifts: {
    id: 'demo-shift',
    starts_at: new Date(Date.now() + 86400000).toISOString(),
    ends_at: new Date(Date.now() + 86400000 + 8 * 3600000).toISOString(),
    status: 'assigned',
    worker_rate: 16,
    sites: { name: 'Demo Hotel', address: 'Singapore' },
    roles: { name: 'F&B Service Crew' },
  },
  timesheets: [],
};

export default function AssignmentScreen() {
  const params = useLocalSearchParams<{ assignmentId?: string }>();
  const assignmentId = typeof params.assignmentId === 'string' ? params.assignmentId : undefined;
  const [item, setItem] = useState<AssignmentDetail | null>(null);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async (asRefresh = false) => {
    if (asRefresh) setRefreshing(true); else setLoading(true);
    setError(null);

    if (!supabase) {
      setItem(demo);
      setLoading(false);
      setRefreshing(false);
      return;
    }

    if (!assignmentId) {
      setError('This assignment link is incomplete. Return to My Shifts and open it again.');
      setLoading(false);
      setRefreshing(false);
      return;
    }

    const { data: authData } = await supabase.auth.getUser();
    if (!authData.user) {
      setLoading(false);
      setRefreshing(false);
      router.replace('/sign-in');
      return;
    }

    const { data, error: queryError } = await supabase
      .from('shift_assignments')
      .select('id,accepted_at,cancelled_at,shifts(id,starts_at,ends_at,status,worker_rate,sites(name,address),roles(name)),timesheets(id,status,payable_minutes,worker_amount,rejection_reason)')
      .eq('id', assignmentId)
      .eq('worker_id', authData.user.id)
      .maybeSingle();

    if (queryError) setError('We could not load this assignment. Pull down to try again.');
    else if (!data) setError('This assignment is unavailable or no longer belongs to your account.');
    else setItem(data as unknown as AssignmentDetail);

    setLoading(false);
    setRefreshing(false);
  }, [assignmentId]);

  useEffect(() => { void load(); }, [load]);

  if (loading) {
    return <View style={styles.center} accessibilityRole="progressbar"><ActivityIndicator /><Text style={styles.muted}>Loading assignment…</Text></View>;
  }

  if (!item || !item.shifts) {
    return <View style={styles.center}><Text style={styles.errorTitle}>Assignment unavailable</Text><Text style={styles.muted}>{error ?? 'Please return to My Shifts.'}</Text><Pressable accessibilityRole="button" style={styles.primary} onPress={() => router.replace('/my-shifts')}><Text style={styles.primaryText}>Back to My Shifts</Text></Pressable></View>;
  }

  const shift = item.shifts;
  const timesheet = item.timesheets?.[0];
  const start = new Date(shift.starts_at);
  const end = new Date(shift.ends_at);
  const durationMinutes = Math.max(0, Math.round((end.getTime() - start.getTime()) / 60000));
  const estimatedScheduledPay = shift.worker_rate == null ? null : durationMinutes / 60 * Number(shift.worker_rate);
  const cancelled = item.cancelled_at !== null || shift.status === 'cancelled';

  return <ScrollView
    contentContainerStyle={styles.container}
    refreshControl={<RefreshControl refreshing={refreshing} onRefresh={() => void load(true)} />}
  >
    <Pressable accessibilityRole="button" accessibilityLabel="Back to My Shifts" onPress={() => router.back()}><Text style={styles.back}>‹ My Shifts</Text></Pressable>
    <Text style={styles.title}>{shift.roles?.name ?? 'Shift assignment'}</Text>
    <Text style={styles.site}>{shift.sites?.name ?? 'Work site'}</Text>

    {error && <View style={styles.warning} accessibilityRole="alert"><Text style={styles.warningText}>{error}</Text></View>}
    {cancelled && <View style={styles.cancelledNotice} accessibilityRole="alert"><Text style={styles.cancelledTitle}>Shift cancelled</Text><Text style={styles.cancelledText}>Operations cancelled this assignment. Do not travel to the site or attempt to clock in.</Text></View>}

    <View style={styles.card} accessible accessibilityLabel="Shift details">
      <Text style={styles.sectionTitle}>Shift details</Text>
      <Text style={styles.label}>Date & time</Text>
      <Text style={styles.value}>{start.toLocaleString()} – {end.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}</Text>
      <Text style={styles.label}>Location</Text>
      <Text style={styles.value}>{shift.sites?.address ?? 'Address will be provided by operations.'}</Text>
      <Text style={styles.label}>Rate</Text>
      <Text style={styles.value}>{shift.worker_rate == null ? 'Rate pending' : `S$${Number(shift.worker_rate).toFixed(2)} / hr`}</Text>
      {estimatedScheduledPay != null && <Text style={styles.helper}>Scheduled-shift estimate: S${estimatedScheduledPay.toFixed(2)}. Final pay follows approved payable time.</Text>}
    </View>

    <View style={styles.card} accessible accessibilityLabel="Attendance and timesheet status">
      <Text style={styles.sectionTitle}>Attendance & pay</Text>
      <View style={styles.row}><Text style={styles.label}>Shift status</Text><Text style={styles.badge}>{shift.status}</Text></View>
      <View style={styles.row}><Text style={styles.label}>Timesheet</Text><Text style={styles.badge}>{timesheet?.status ?? 'Not created'}</Text></View>
      {timesheet && <Text style={styles.value}>{Math.floor(timesheet.payable_minutes / 60)}h {timesheet.payable_minutes % 60}m · Est. S${Number(timesheet.worker_amount ?? 0).toFixed(2)}</Text>}
      {timesheet?.rejection_reason && <View style={styles.warning}><Text style={styles.warningText}>Action needed: {timesheet.rejection_reason}</Text></View>}
      <Text style={styles.helper}>Clock-in/out is validated by the server against your assignment, shift timing and site geofence.</Text>
    </View>

    {!cancelled && <Pressable
      accessibilityRole="button"
      accessibilityLabel="Open attendance for this shift"
      style={styles.primary}
      onPress={() => router.push({ pathname: '/attendance', params: { assignmentId: item.id } })}
    ><Text style={styles.primaryText}>Open attendance</Text></Pressable>}
  </ScrollView>;
}

const styles = StyleSheet.create({
  container: { padding: 20, gap: 14, paddingBottom: 48 },
  center: { flex: 1, padding: 24, alignItems: 'center', justifyContent: 'center', gap: 12 },
  back: { fontSize: 16, fontWeight: '700', marginBottom: 4 },
  title: { fontSize: 30, fontWeight: '800' },
  site: { fontSize: 18, color: '#5f6670', fontWeight: '600' },
  card: { borderWidth: 1, borderColor: '#e6e8eb', borderRadius: 18, padding: 16, gap: 8 },
  sectionTitle: { fontSize: 18, fontWeight: '800', marginBottom: 2 },
  label: { color: '#68707b', fontSize: 13, fontWeight: '700' },
  value: { fontSize: 16, fontWeight: '600' },
  helper: { color: '#68707b', lineHeight: 20 },
  row: { flexDirection: 'row', justifyContent: 'space-between', gap: 12, alignItems: 'center' },
  badge: { fontSize: 12, fontWeight: '800', textTransform: 'uppercase' },
  primary: { borderRadius: 14, padding: 15, backgroundColor: '#111', alignItems: 'center', minWidth: 180 },
  primaryText: { color: '#fff', fontWeight: '800' },
  muted: { color: '#68707b', textAlign: 'center' },
  errorTitle: { fontSize: 20, fontWeight: '800' },
  warning: { backgroundColor: '#fff7ed', borderRadius: 12, padding: 12 },
  warningText: { color: '#9a3412', fontWeight: '600' },
  cancelledNotice: { backgroundColor: '#fff1f0', borderRadius: 12, padding: 14, gap: 4 }, cancelledTitle: { color: '#b42318', fontSize: 17, fontWeight: '800' }, cancelledText: { color: '#912018', lineHeight: 20, fontWeight: '600' },
});
