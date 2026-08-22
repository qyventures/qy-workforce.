import { useCallback, useEffect, useMemo, useState } from 'react';
import { ActivityIndicator, Pressable, RefreshControl, ScrollView, StyleSheet, Text, View } from 'react-native';
import { router, useLocalSearchParams } from 'expo-router';
import { supabase } from '../lib/supabase';
import { isLikelyNetworkError, mobileErrorMessage } from '../lib/errors';

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

function formatShiftWindow(start: Date, end: Date): string {
  return `${start.toLocaleString()} – ${end.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}`;
}

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

    try {
      if (!supabase) {
        setItem(demo);
        return;
      }

      if (!assignmentId) {
        setItem(null);
        setError('This assignment link is incomplete. Return to My Shifts and open it again.');
        return;
      }

      const { data: sessionData, error: sessionError } = await supabase.auth.getSession();
      if (sessionError) throw sessionError;
      if (!sessionData.session?.user) {
        router.replace('/sign-in');
        return;
      }

      const { data, error: queryError } = await supabase
        .from('shift_assignments')
        .select('id,accepted_at,cancelled_at,shifts(id,starts_at,ends_at,status,worker_rate,sites(name,address),roles(name)),timesheets(id,status,payable_minutes,worker_amount,rejection_reason)')
        .eq('id', assignmentId)
        .eq('worker_id', sessionData.session.user.id)
        .maybeSingle();

      if (queryError) throw queryError;
      if (!data) {
        setItem(null);
        setError('This assignment is unavailable or no longer belongs to your account.');
        return;
      }

      setItem(data as unknown as AssignmentDetail);
    } catch (caught) {
      const message = isLikelyNetworkError(caught)
        ? 'You may be offline or on an unstable connection. Reconnect and pull down to refresh this assignment.'
        : mobileErrorMessage(caught, 'We could not load this assignment. Pull down to try again.');
      setError(message);
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
  }, [assignmentId]);

  useEffect(() => { void load(); }, [load]);

  const summary = useMemo(() => {
    if (!item?.shifts) return null;
    const start = new Date(item.shifts.starts_at);
    const end = new Date(item.shifts.ends_at);
    const durationMinutes = Math.max(0, Math.round((end.getTime() - start.getTime()) / 60000));
    const estimatedScheduledPay = item.shifts.worker_rate == null
      ? null
      : durationMinutes / 60 * Number(item.shifts.worker_rate);
    return { start, end, durationMinutes, estimatedScheduledPay };
  }, [item]);

  if (loading) {
    return <View style={styles.center} accessibilityRole="progressbar"><ActivityIndicator /><Text style={styles.muted}>Loading assignment…</Text></View>;
  }

  if (!item || !item.shifts || !summary) {
    return <View style={styles.center}>
      <Text style={styles.errorTitle} accessibilityRole="header">Assignment unavailable</Text>
      <Text style={styles.muted} accessibilityLiveRegion="polite">{error ?? 'Please return to My Shifts.'}</Text>
      <Pressable accessibilityRole="button" style={styles.primary} onPress={() => router.replace('/my-shifts')}>
        <Text style={styles.primaryText}>Back to My Shifts</Text>
      </Pressable>
    </View>;
  }

  const shift = item.shifts;
  const timesheet = item.timesheets?.[0];
  const assignmentCancelled = Boolean(item.cancelled_at) || shift.status === 'cancelled';
  const actionableTimesheet = timesheet?.status === 'rejected';

  return <ScrollView
    contentContainerStyle={styles.container}
    refreshControl={<RefreshControl refreshing={refreshing} onRefresh={() => void load(true)} />}
  >
    <Pressable accessibilityRole="button" accessibilityLabel="Back to My Shifts" onPress={() => router.back()} style={styles.backButton}>
      <Text style={styles.back}>‹ My Shifts</Text>
    </Pressable>
    <Text style={styles.title} accessibilityRole="header">{shift.roles?.name ?? 'Shift assignment'}</Text>
    <Text style={styles.site}>{shift.sites?.name ?? 'Work site'}</Text>

    {error && <View style={styles.warning} accessibilityRole="alert"><Text style={styles.warningText}>{error}</Text></View>}
    {assignmentCancelled && <View style={styles.cancelled} accessibilityRole="alert"><Text style={styles.cancelledText}>This assignment has been cancelled. Attendance actions are disabled.</Text></View>}

    <View style={styles.card} accessible accessibilityLabel="Shift details">
      <Text style={styles.sectionTitle}>Shift details</Text>
      <Text style={styles.label}>Date & time</Text>
      <Text style={styles.value}>{formatShiftWindow(summary.start, summary.end)}</Text>
      <Text style={styles.label}>Location</Text>
      <Text style={styles.value}>{shift.sites?.address ?? 'Address will be provided by operations.'}</Text>
      <Text style={styles.label}>Rate</Text>
      <Text style={styles.value}>{shift.worker_rate == null ? 'Rate pending' : `S$${Number(shift.worker_rate).toFixed(2)} / hr`}</Text>
      {summary.estimatedScheduledPay != null && <Text style={styles.helper}>Scheduled-shift estimate: S${summary.estimatedScheduledPay.toFixed(2)}. Final pay follows approved payable time.</Text>}
    </View>

    <View style={styles.card} accessible accessibilityLabel="Attendance and timesheet status">
      <Text style={styles.sectionTitle}>Attendance & pay</Text>
      <View style={styles.row}><Text style={styles.label}>Shift status</Text><Text style={styles.badge}>{shift.status}</Text></View>
      <View style={styles.row}><Text style={styles.label}>Timesheet</Text><Text style={styles.badge}>{timesheet?.status ?? 'Not created'}</Text></View>
      {timesheet && <Text style={styles.value}>{Math.floor(timesheet.payable_minutes / 60)}h {timesheet.payable_minutes % 60}m · Est. S${Number(timesheet.worker_amount ?? 0).toFixed(2)}</Text>}
      {timesheet?.rejection_reason && <View style={styles.warning}><Text style={styles.warningText}>Action needed: {timesheet.rejection_reason}</Text></View>}
      <Text style={styles.helper}>Clock-in/out is validated by the server against your assignment, shift timing and site geofence.</Text>
    </View>

    <View style={styles.actions}>
      <Pressable
        accessibilityRole="button"
        accessibilityLabel="Open attendance for this shift"
        accessibilityState={{ disabled: assignmentCancelled }}
        disabled={assignmentCancelled}
        style={[styles.primary, assignmentCancelled && styles.disabled]}
        onPress={() => router.push({ pathname: '/attendance', params: { assignmentId: item.id } })}
      ><Text style={styles.primaryText}>Open attendance</Text></Pressable>

      <Pressable
        accessibilityRole="button"
        accessibilityLabel={actionableTimesheet ? 'Open earnings and timesheet status requiring action' : 'Open earnings and timesheet status'}
        style={styles.secondary}
        onPress={() => router.push('/earnings')}
      ><Text style={styles.secondaryText}>{actionableTimesheet ? 'Review pay issue' : 'View earnings'}</Text></Pressable>
    </View>
  </ScrollView>;
}

const styles = StyleSheet.create({
  container: { padding: 20, gap: 14, paddingBottom: 48 },
  center: { flex: 1, padding: 24, alignItems: 'center', justifyContent: 'center', gap: 12 },
  backButton: { minHeight: 44, justifyContent: 'center', alignSelf: 'flex-start' },
  back: { fontSize: 16, fontWeight: '700' },
  title: { fontSize: 30, fontWeight: '800' },
  site: { fontSize: 18, color: '#5f6670', fontWeight: '600' },
  card: { borderWidth: 1, borderColor: '#e6e8eb', borderRadius: 18, padding: 16, gap: 8 },
  sectionTitle: { fontSize: 18, fontWeight: '800', marginBottom: 2 },
  label: { color: '#68707b', fontSize: 13, fontWeight: '700' },
  value: { fontSize: 16, fontWeight: '600' },
  helper: { color: '#68707b', lineHeight: 20 },
  row: { flexDirection: 'row', justifyContent: 'space-between', gap: 12, alignItems: 'center' },
  badge: { fontSize: 12, fontWeight: '800', textTransform: 'uppercase' },
  actions: { gap: 10 },
  primary: { borderRadius: 14, padding: 15, minHeight: 52, backgroundColor: '#111', alignItems: 'center', justifyContent: 'center', minWidth: 180 },
  primaryText: { color: '#fff', fontWeight: '800' },
  secondary: { borderRadius: 14, padding: 15, minHeight: 52, borderWidth: 1, borderColor: '#d8dbe0', alignItems: 'center', justifyContent: 'center' },
  secondaryText: { color: '#111', fontWeight: '800' },
  disabled: { opacity: 0.35 },
  muted: { color: '#68707b', textAlign: 'center' },
  errorTitle: { fontSize: 20, fontWeight: '800' },
  warning: { backgroundColor: '#fff7ed', borderRadius: 12, padding: 12 },
  warningText: { color: '#9a3412', fontWeight: '600' },
  cancelled: { backgroundColor: '#fef2f2', borderRadius: 12, padding: 12 },
  cancelledText: { color: '#991b1b', fontWeight: '700' },
});
