import { useEffect, useState } from 'react';
import { ActivityIndicator, Alert, Pressable, StyleSheet, Text, View } from 'react-native';
import * as Location from 'expo-location';
import { router, useLocalSearchParams } from 'expo-router';
import { supabase } from '../lib/supabase';

type AttendanceState = 'idle' | 'locating' | 'clocked-in' | 'clocked-out';

type AttendanceDetails = {
  assignment_id: string;
  role_name: string;
  site_name: string;
  site_address: string | null;
  starts_at: string;
  ends_at: string;
  worker_rate: number | null;
  clock_in_at: string | null;
  clock_out_at: string | null;
  timesheet: {
    id: string;
    status: string;
    payable_minutes: number;
    worker_amount: number | null;
    submitted_at: string | null;
  } | null;
};

const demo: AttendanceDetails = {
  assignment_id: 'demo-assignment',
  role_name: 'Banquet Crew',
  site_name: 'Demo Hotel',
  site_address: 'Marina Bay, Singapore',
  starts_at: new Date().toISOString(),
  ends_at: new Date(Date.now() + 6 * 3600000).toISOString(),
  worker_rate: 16,
  clock_in_at: null,
  clock_out_at: null,
  timesheet: null,
};

export default function AttendanceScreen() {
  const params = useLocalSearchParams<{ assignmentId?: string }>();
  const assignmentId = Array.isArray(params.assignmentId) ? params.assignmentId[0] : params.assignmentId;
  const [details, setDetails] = useState<AttendanceDetails | null>(null);
  const [state, setState] = useState<AttendanceState>('idle');
  const [loading, setLoading] = useState(true);
  const [distanceM, setDistanceM] = useState<number | null>(null);

  async function load() {
    if (!supabase || !assignmentId || assignmentId === 'demo-assignment') {
      setDetails(demo);
      setState('idle');
      setLoading(false);
      return;
    }

    const { data: authData } = await supabase.auth.getUser();
    if (!authData.user) {
      setLoading(false);
      router.replace('/sign-in');
      return;
    }

    const { data, error } = await supabase.rpc('get_assignment_attendance_state', {
      p_assignment_id: assignmentId,
    });
    if (error || !data) {
      setLoading(false);
      Alert.alert('Attendance unavailable', error?.message ?? 'This assignment is not available.');
      return;
    }

    const next = data as AttendanceDetails;
    setDetails(next);
    setState(next.clock_out_at ? 'clocked-out' : next.clock_in_at ? 'clocked-in' : 'idle');
    setLoading(false);
  }

  useEffect(() => { void load(); }, [assignmentId]);

  const verifyAndRecord = async (action: 'in' | 'out') => {
    if (!details) return;
    if (!supabase || details.assignment_id === 'demo-assignment') {
      setState(action === 'in' ? 'clocked-in' : 'clocked-out');
      if (action === 'out') {
        setDetails((current) => current ? { ...current, timesheet: { id: 'demo-timesheet', status: 'draft', payable_minutes: 360, worker_amount: 96, submitted_at: null } } : current);
      }
      return;
    }

    setState('locating');
    const permission = await Location.requestForegroundPermissionsAsync();
    if (permission.status !== 'granted') {
      setState(details.clock_in_at ? 'clocked-in' : 'idle');
      Alert.alert('Location required', 'QY Workforce uses your foreground location only when you tap clock in or clock out.');
      return;
    }

    try {
      const position = await Location.getCurrentPositionAsync({ accuracy: Location.Accuracy.High });
      const mocked = (position as Location.LocationObject & { mocked?: boolean }).mocked ?? null;
      const { data, error } = await supabase.rpc('record_clock_event', {
        p_assignment_id: details.assignment_id,
        p_event_type: action === 'in' ? 'clock_in' : 'clock_out',
        p_latitude: position.coords.latitude,
        p_longitude: position.coords.longitude,
        p_accuracy_m: position.coords.accuracy,
        p_device_hash: null,
        p_is_mocked: mocked,
      });

      if (error) {
        setState(details.clock_in_at ? 'clocked-in' : 'idle');
        const message = error.message.includes('outside approved worksite geofence')
          ? 'You are outside the approved worksite area. Move closer to the worksite and try again.'
          : error.message.includes('location accuracy insufficient')
            ? 'Your location is not accurate enough yet. Move to an open area and try again.'
            : error.message;
        Alert.alert('Clock event not recorded', message);
        return;
      }

      const result = data as { distance_m?: number; payable_minutes?: number | null; worker_amount?: number | null } | null;
      setDistanceM(result?.distance_m ?? null);
      await load();
      if (action === 'out') {
        Alert.alert('Shift completed', 'Your attendance was recorded and a draft timesheet was created for review.');
      }
    } catch {
      setState(details.clock_in_at ? 'clocked-in' : 'idle');
      Alert.alert('Location unavailable', 'We could not verify your location. Please check location services and try again.');
    }
  };

  if (loading) {
    return <View style={styles.center}><ActivityIndicator /><Text style={styles.note}>Loading attendance…</Text></View>;
  }

  if (!details) {
    return <View style={styles.center}><Text style={styles.title}>Attendance unavailable</Text><Pressable style={styles.primaryButton} onPress={() => router.replace('/my-shifts')}><Text style={styles.primaryButtonText}>Back to My Shifts</Text></Pressable></View>;
  }

  const isWorking = state === 'clocked-in';
  const start = new Date(details.starts_at);
  const end = new Date(details.ends_at);
  const shiftDate = `${start.toLocaleDateString([], { day: 'numeric', month: 'short' })} · ${start.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}–${end.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}`;

  return (
    <View style={styles.page}>
      <Text style={styles.eyebrow}>SHIFT ATTENDANCE</Text>
      <Text style={styles.title}>{details.role_name}</Text>
      <Text style={styles.client}>{details.site_name}{details.site_address ? ` · ${details.site_address}` : ''}</Text>

      <View style={styles.timeCard}>
        <Text style={styles.date}>{shiftDate}</Text>
        <Text style={styles.status}>{isWorking ? 'You are clocked in' : state === 'clocked-out' ? 'Shift completed' : 'Ready to clock in'}</Text>
        {details.clock_in_at && <Text style={styles.distance}>Clocked in: {new Date(details.clock_in_at).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}</Text>}
        {details.clock_out_at && <Text style={styles.distance}>Clocked out: {new Date(details.clock_out_at).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}</Text>}
        {distanceM !== null && <Text style={styles.distance}>Last verified worksite distance: {distanceM}m</Text>}
      </View>

      <View style={styles.privacyCard}>
        <Text style={styles.privacyTitle}>Location privacy</Text>
        <Text style={styles.privacyBody}>Location is requested only when you tap clock in or clock out. QY Workforce does not continuously track your location in the background.</Text>
      </View>

      {state !== 'clocked-out' && (
        <Pressable
          disabled={state === 'locating'}
          style={[styles.primaryButton, isWorking && styles.outButton, state === 'locating' && styles.disabledButton]}
          onPress={() => verifyAndRecord(isWorking ? 'out' : 'in')}
        >
          <Text style={styles.primaryButtonText}>{state === 'locating' ? 'Verifying location…' : isWorking ? 'Verify location & clock out' : 'Verify location & clock in'}</Text>
        </Pressable>
      )}

      {state === 'clocked-out' && (
        <View style={styles.completeCard}>
          <Text style={styles.completeTitle}>Attendance captured</Text>
          <Text style={styles.completeBody}>{details.timesheet ? `${Math.floor(details.timesheet.payable_minutes / 60)}h ${details.timesheet.payable_minutes % 60}m recorded · Est. S$${Number(details.timesheet.worker_amount ?? 0).toFixed(2)} · ${details.timesheet.status}` : 'A draft timesheet is being prepared.'}</Text>
          <Pressable style={styles.secondaryButton} onPress={() => router.replace('/my-shifts')}><Text style={styles.secondaryButtonText}>View My Shifts</Text></Pressable>
        </View>
      )}

      <Text style={styles.note}>The server validates worksite geofence, GPS accuracy, event order and shift timing before accepting attendance. Supervisor approval is still required before payroll.</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  page: { flex: 1, padding: 24, paddingTop: 68, backgroundColor: '#F7F8FC' },
  center: { flex: 1, padding: 24, alignItems: 'center', justifyContent: 'center', gap: 14, backgroundColor: '#F7F8FC' },
  eyebrow: { fontSize: 12, fontWeight: '800', letterSpacing: 1.2, color: '#4D63FF' },
  title: { fontSize: 32, lineHeight: 38, fontWeight: '800', color: '#101828', marginTop: 5 },
  client: { fontSize: 16, color: '#667085', marginTop: 6 },
  timeCard: { backgroundColor: '#111827', borderRadius: 22, padding: 22, marginTop: 28 },
  date: { color: '#D0D5DD', fontSize: 15, fontWeight: '600' },
  status: { color: '#FFFFFF', fontSize: 24, lineHeight: 30, fontWeight: '800', marginTop: 12 },
  distance: { color: '#C7D2FE', fontSize: 13, marginTop: 10 },
  privacyCard: { backgroundColor: '#EEF4FF', borderRadius: 18, padding: 18, marginTop: 18 },
  privacyTitle: { color: '#3538CD', fontWeight: '800', fontSize: 16 },
  privacyBody: { color: '#475467', marginTop: 7, lineHeight: 20 },
  primaryButton: { backgroundColor: '#4D63FF', borderRadius: 16, paddingVertical: 17, paddingHorizontal: 18, alignItems: 'center', marginTop: 22 },
  outButton: { backgroundColor: '#B42318' },
  disabledButton: { opacity: 0.55 },
  primaryButtonText: { color: '#FFFFFF', fontSize: 16, fontWeight: '800' },
  completeCard: { backgroundColor: '#ECFDF3', borderRadius: 18, padding: 18, marginTop: 22 },
  completeTitle: { color: '#027A48', fontSize: 18, fontWeight: '800' },
  completeBody: { color: '#475467', lineHeight: 20, marginTop: 6 },
  secondaryButton: { borderWidth: 1, borderColor: '#A6F4C5', borderRadius: 12, paddingVertical: 12, alignItems: 'center', marginTop: 14 },
  secondaryButtonText: { color: '#027A48', fontWeight: '800' },
  note: { color: '#98A2B3', fontSize: 12, lineHeight: 18, marginTop: 18 },
});