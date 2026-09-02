import { useEffect, useState } from 'react';
import { ActivityIndicator, Alert, Pressable, StyleSheet, Text, TextInput, View } from 'react-native';
import * as Location from 'expo-location';
import { router, useLocalSearchParams } from 'expo-router';
import { isLikelyNetworkError, mobileErrorMessage } from '../lib/errors';
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
  correction?: {
    id: string;
    status: string;
    reason: string;
    requested_clock_in: string | null;
    requested_clock_out: string | null;
  } | null;
};

const demo: AttendanceDetails = {
  assignment_id: 'demo-assignment', role_name: 'Banquet Crew', site_name: 'Demo Hotel', site_address: 'Marina Bay, Singapore',
  starts_at: new Date().toISOString(), ends_at: new Date(Date.now() + 6 * 3600000).toISOString(), worker_rate: 16,
  clock_in_at: null, clock_out_at: null, timesheet: null,
};

export default function AttendanceScreen() {
  const params = useLocalSearchParams<{ assignmentId?: string }>();
  const assignmentId = Array.isArray(params.assignmentId) ? params.assignmentId[0] : params.assignmentId;
  const [details, setDetails] = useState<AttendanceDetails | null>(null);
  const [state, setState] = useState<AttendanceState>('idle');
  const [loading, setLoading] = useState(true);
  const [refreshingState, setRefreshingState] = useState(false);
  const [distanceM, setDistanceM] = useState<number | null>(null);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [correctionReason, setCorrectionReason] = useState('');
  const [correctionIn, setCorrectionIn] = useState('');
  const [correctionOut, setCorrectionOut] = useState('');
  const [showCorrection, setShowCorrection] = useState(false);
  const [submittingCorrection, setSubmittingCorrection] = useState(false);

  async function load(asRefresh = false) {
    if (asRefresh) setRefreshingState(true); else setLoading(true);
    setLoadError(null);
    if (!supabase || !assignmentId || assignmentId === 'demo-assignment') {
      setDetails(demo); setState('idle'); setLoading(false); setRefreshingState(false); return;
    }
    try {
      const { data: authData, error: authError } = await supabase.auth.getUser();
      if (authError) throw authError;
      if (!authData.user) { setLoading(false); setRefreshingState(false); router.replace('/sign-in'); return; }
      const { data, error } = await supabase.rpc('get_assignment_attendance_state', { p_assignment_id: assignmentId });
      if (error) throw error;
      if (!data) throw new Error('This assignment is not available.');
      const next = data as AttendanceDetails;
      const { data: correction } = await supabase
        .from('attendance_correction_requests')
        .select('id,status,reason,requested_clock_in,requested_clock_out')
        .eq('assignment_id', assignmentId)
        .order('requested_at', { ascending: false })
        .limit(1)
        .maybeSingle();
      next.correction = correction as AttendanceDetails['correction'];
      setDetails(next);
      setState(next.clock_out_at ? 'clocked-out' : next.clock_in_at ? 'clocked-in' : 'idle');
    } catch (error) {
      setLoadError(mobileErrorMessage(error, 'This assignment is not available.'));
    } finally {
      setLoading(false); setRefreshingState(false);
    }
  }

  useEffect(() => { void load(); }, [assignmentId]);

  async function submitCorrection() {
    if (!supabase || !details || submittingCorrection) return;
    if (correctionReason.trim().length < 5) {
      Alert.alert('Reason required', 'Tell operations what was wrong with the attendance record (at least 5 characters).');
      return;
    }
    if (!correctionIn.trim() && !correctionOut.trim()) {
      Alert.alert('Timestamp required', 'Enter at least one corrected clock-in or clock-out time.');
      return;
    }
    const parsedIn = correctionIn.trim() ? new Date(correctionIn.trim()) : null;
    const parsedOut = correctionOut.trim() ? new Date(correctionOut.trim()) : null;
    if ((parsedIn && Number.isNaN(parsedIn.getTime())) || (parsedOut && Number.isNaN(parsedOut.getTime()))) {
      Alert.alert('Invalid timestamp', 'Use an ISO date/time such as 2026-09-02T09:00:00+08:00.');
      return;
    }
    setSubmittingCorrection(true); setLoadError(null);
    const { error } = await supabase.rpc('request_attendance_correction', {
      p_assignment_id: details.assignment_id,
      p_requested_clock_in: parsedIn ? parsedIn.toISOString() : null,
      p_requested_clock_out: parsedOut ? parsedOut.toISOString() : null,
      p_reason: correctionReason.trim(),
    });
    if (error) {
      setLoadError(error.message);
    } else {
      setShowCorrection(false); setCorrectionReason(''); setCorrectionIn(''); setCorrectionOut('');
      Alert.alert('Request submitted', 'Operations will review your attendance correction before payroll.');
      await load(true);
    }
    setSubmittingCorrection(false);
  }

  const verifyAndRecord = async (action: 'in' | 'out') => {
    if (!details) return;
    if (!supabase || details.assignment_id === 'demo-assignment') {
      setState(action === 'in' ? 'clocked-in' : 'clocked-out');
      if (action === 'out') setDetails((current) => current ? { ...current, timesheet: { id: 'demo-timesheet', status: 'draft', payable_minutes: 360, worker_amount: 96, submitted_at: null } } : current);
      return;
    }

    setState('locating'); setLoadError(null);
    try {
      const providerStatus = await Location.getProviderStatusAsync();
      if (!providerStatus.locationServicesEnabled) {
        setState(details.clock_in_at ? 'clocked-in' : 'idle');
        Alert.alert('Turn on Location Services', 'Location Services are turned off. Turn them on in device settings, then refresh attendance status before trying again.');
        return;
      }

      const permission = await Location.requestForegroundPermissionsAsync();
      if (permission.status !== 'granted') {
        setState(details.clock_in_at ? 'clocked-in' : 'idle');
        Alert.alert('Location required', 'QY Workforce uses your foreground location only when you tap clock in or clock out.');
        return;
      }
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
        if (isLikelyNetworkError(error)) {
          setLoadError('Connection interrupted. Refresh attendance status before trying the clock action again.');
          Alert.alert('Could not confirm attendance', 'The connection dropped while saving your clock event. Do not retry immediately. Refresh this screen first to check whether the server recorded it.');
          return;
        }
        const message = error.message.includes('outside approved worksite geofence')
          ? 'You are outside the approved worksite area. Move closer to the worksite and try again.'
          : error.message.includes('location accuracy insufficient')
            ? 'Your location is not accurate enough yet. Move to an open area and try again.'
            : mobileErrorMessage(error, 'The clock event could not be recorded.');
        Alert.alert('Clock event not recorded', message);
        return;
      }

      const result = data as { distance_m?: number; payable_minutes?: number | null; worker_amount?: number | null } | null;
      setDistanceM(result?.distance_m ?? null);
      await load(true);
      if (action === 'out') Alert.alert('Shift completed', 'Your attendance was recorded and a draft timesheet was created for review.');
    } catch (error) {
      setState(details.clock_in_at ? 'clocked-in' : 'idle');
      if (isLikelyNetworkError(error)) {
        setLoadError('You may be offline. Reconnect and refresh attendance status before trying again.');
        Alert.alert('Connection interrupted', 'We could not confirm whether the clock event reached the server. Reconnect and refresh this screen before retrying.');
      } else {
        Alert.alert('Location unavailable', mobileErrorMessage(error, 'We could not verify your location. Please check location services and try again.'));
      }
    }
  };

  if (loading) return <View style={styles.center} accessibilityRole="progressbar"><ActivityIndicator /><Text style={styles.note}>Loading attendance…</Text></View>;

  if (!details) {
    return <View style={styles.center}>
      <Text style={styles.title}>Attendance unavailable</Text>
      {loadError && <Text style={styles.errorText} accessibilityRole="alert">{loadError}</Text>}
      <Pressable accessibilityRole="button" style={styles.primaryButton} disabled={refreshingState} onPress={() => void load(true)}><Text style={styles.primaryButtonText}>{refreshingState ? 'Refreshing…' : 'Retry'}</Text></Pressable>
      <Pressable accessibilityRole="button" style={styles.secondaryNeutralButton} onPress={() => router.replace('/my-shifts')}><Text style={styles.secondaryNeutralButtonText}>Back to My Shifts</Text></Pressable>
    </View>;
  }

  const isWorking = state === 'clocked-in';
  const start = new Date(details.starts_at); const end = new Date(details.ends_at);
  const shiftDate = `${start.toLocaleDateString([], { day: 'numeric', month: 'short' })} · ${start.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}–${end.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}`;

  return <View style={styles.page}>
    <Text style={styles.eyebrow}>SHIFT ATTENDANCE</Text>
    <Text style={styles.title}>{details.role_name}</Text>
    <Text style={styles.client}>{details.site_name}{details.site_address ? ` · ${details.site_address}` : ''}</Text>
    {loadError && <View style={styles.warningCard} accessibilityRole="alert"><Text style={styles.warningTitle}>Check server status before retrying</Text><Text style={styles.warningBody}>{loadError}</Text><Pressable accessibilityRole="button" accessibilityState={{ disabled: refreshingState }} style={[styles.warningButton, refreshingState && styles.disabledButton]} disabled={refreshingState} onPress={() => void load(true)}><Text style={styles.warningButtonText}>{refreshingState ? 'Refreshing status…' : 'Refresh attendance status'}</Text></Pressable></View>}
    <View style={styles.timeCard}><Text style={styles.date}>{shiftDate}</Text><Text style={styles.status}>{isWorking ? 'You are clocked in' : state === 'clocked-out' ? 'Shift completed' : 'Ready to clock in'}</Text>{details.clock_in_at && <Text style={styles.distance}>Clocked in: {new Date(details.clock_in_at).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}</Text>}{details.clock_out_at && <Text style={styles.distance}>Clocked out: {new Date(details.clock_out_at).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}</Text>}{distanceM !== null && <Text style={styles.distance}>Last verified worksite distance: {distanceM}m</Text>}</View>
    <View style={styles.privacyCard}><Text style={styles.privacyTitle}>Location privacy</Text><Text style={styles.privacyBody}>Location is requested only when you tap clock in or clock out. QY Workforce does not continuously track your location in the background.</Text></View>
    {details.correction?.status === 'pending' && <View style={styles.pendingCard}><Text style={styles.pendingTitle}>Correction request pending</Text><Text style={styles.pendingBody}>Operations is reviewing: {details.correction.reason}</Text></View>}
    {!details.correction || details.correction.status !== 'pending' ? <Pressable accessibilityRole="button" style={styles.secondaryNeutralButton} onPress={() => { setCorrectionIn(details.clock_in_at ?? ''); setCorrectionOut(details.clock_out_at ?? ''); setShowCorrection(true); }}><Text style={styles.secondaryNeutralButtonText}>Report an attendance issue</Text></Pressable> : null}
    {showCorrection && <View style={styles.correctionCard}>
      <Text style={styles.correctionTitle}>Request attendance correction</Text>
      <Text style={styles.correctionHelp}>Use ISO date/time, for example 2026-09-02T09:00:00+08:00. Leave a field blank if that timestamp is correct or was not recorded.</Text>
      <TextInput accessibilityLabel="Corrected clock-in time" value={correctionIn} onChangeText={setCorrectionIn} placeholder="Corrected clock-in (optional)" style={styles.input} autoCapitalize="none" />
      <TextInput accessibilityLabel="Corrected clock-out time" value={correctionOut} onChangeText={setCorrectionOut} placeholder="Corrected clock-out (optional)" style={styles.input} autoCapitalize="none" />
      <TextInput accessibilityLabel="Attendance issue reason" value={correctionReason} onChangeText={setCorrectionReason} placeholder="What went wrong?" style={[styles.input, styles.reasonInput]} multiline maxLength={1000} />
      <View style={styles.correctionActions}><Pressable accessibilityRole="button" style={styles.secondaryNeutralButton} onPress={() => setShowCorrection(false)}><Text style={styles.secondaryNeutralButtonText}>Cancel</Text></Pressable><Pressable accessibilityRole="button" style={[styles.primaryButton, submittingCorrection && styles.disabledButton]} disabled={submittingCorrection} onPress={() => void submitCorrection()}><Text style={styles.primaryButtonText}>{submittingCorrection ? 'Submitting…' : 'Submit request'}</Text></Pressable></View>
    </View>}
    {state !== 'clocked-out' && <Pressable accessibilityRole="button" accessibilityLabel={isWorking ? 'Verify location and clock out' : 'Verify location and clock in'} accessibilityState={{ disabled: state === 'locating' || refreshingState || Boolean(loadError) }} disabled={state === 'locating' || refreshingState || Boolean(loadError)} style={[styles.primaryButton, isWorking && styles.outButton, (state === 'locating' || refreshingState || Boolean(loadError)) && styles.disabledButton]} onPress={() => verifyAndRecord(isWorking ? 'out' : 'in')}><Text style={styles.primaryButtonText}>{state === 'locating' ? 'Verifying location…' : isWorking ? 'Verify location & clock out' : 'Verify location & clock in'}</Text></Pressable>}
    {state === 'clocked-out' && <View style={styles.completeCard}><Text style={styles.completeTitle}>Attendance captured</Text><Text style={styles.completeBody}>{details.timesheet ? `${Math.floor(details.timesheet.payable_minutes / 60)}h ${details.timesheet.payable_minutes % 60}m recorded · Est. S$${Number(details.timesheet.worker_amount ?? 0).toFixed(2)} · ${details.timesheet.status}` : 'A draft timesheet is being prepared.'}</Text><Pressable accessibilityRole="button" style={styles.secondaryButton} onPress={() => router.replace('/my-shifts')}><Text style={styles.secondaryButtonText}>View My Shifts</Text></Pressable></View>}
    <Text style={styles.note}>The server validates worksite geofence, GPS accuracy, event order and shift timing before accepting attendance. Supervisor approval is still required before payroll.</Text>
  </View>;
}

const styles = StyleSheet.create({
  page: { flex: 1, padding: 24, paddingTop: 68, backgroundColor: '#F7F8FC' }, center: { flex: 1, padding: 24, alignItems: 'center', justifyContent: 'center', gap: 14, backgroundColor: '#F7F8FC' }, eyebrow: { fontSize: 12, fontWeight: '800', letterSpacing: 1.2, color: '#4D63FF' }, title: { fontSize: 32, lineHeight: 38, fontWeight: '800', color: '#101828', marginTop: 5 }, client: { fontSize: 16, color: '#667085', marginTop: 6 }, timeCard: { backgroundColor: '#111827', borderRadius: 22, padding: 22, marginTop: 28 }, date: { color: '#D0D5DD', fontSize: 15, fontWeight: '600' }, status: { color: '#FFFFFF', fontSize: 24, lineHeight: 30, fontWeight: '800', marginTop: 12 }, distance: { color: '#C7D2FE', fontSize: 13, marginTop: 10 }, privacyCard: { backgroundColor: '#EEF4FF', borderRadius: 18, padding: 18, marginTop: 18 }, privacyTitle: { color: '#3538CD', fontWeight: '800', fontSize: 16 }, privacyBody: { color: '#475467', marginTop: 7, lineHeight: 20 }, pendingCard: { backgroundColor: '#FFF7ED', borderRadius: 18, padding: 18, marginTop: 18 }, pendingTitle: { color: '#9A3412', fontWeight: '800', fontSize: 16 }, pendingBody: { color: '#7C2D12', lineHeight: 20, marginTop: 6 }, correctionCard: { backgroundColor: '#FFFFFF', borderRadius: 18, padding: 18, marginTop: 18, borderWidth: 1, borderColor: '#D0D5DD', gap: 10 }, correctionTitle: { fontSize: 18, fontWeight: '800' }, correctionHelp: { color: '#68707B', lineHeight: 19, fontSize: 13 }, input: { borderWidth: 1, borderColor: '#D0D5DD', borderRadius: 10, padding: 12, minHeight: 46, backgroundColor: '#FFFFFF' }, reasonInput: { minHeight: 84, textAlignVertical: 'top' }, correctionActions: { flexDirection: 'row', gap: 10, alignItems: 'center' }, warningCard: { backgroundColor: '#FFF7ED', borderRadius: 18, padding: 16, marginTop: 18, borderWidth: 1, borderColor: '#FED7AA' }, warningTitle: { color: '#9A3412', fontWeight: '800', fontSize: 15 }, warningBody: { color: '#7C2D12', marginTop: 6, lineHeight: 20 }, warningButton: { borderWidth: 1, borderColor: '#FDBA74', borderRadius: 12, paddingVertical: 12, alignItems: 'center', marginTop: 12 }, warningButtonText: { color: '#9A3412', fontWeight: '800' }, primaryButton: { backgroundColor: '#4D63FF', borderRadius: 16, paddingVertical: 17, paddingHorizontal: 18, alignItems: 'center', marginTop: 22, minHeight: 52, justifyContent: 'center' }, outButton: { backgroundColor: '#B42318' }, disabledButton: { opacity: 0.55 }, primaryButtonText: { color: '#FFFFFF', fontSize: 16, fontWeight: '800' }, completeCard: { backgroundColor: '#ECFDF3', borderRadius: 18, padding: 18, marginTop: 22 }, completeTitle: { color: '#027A48', fontSize: 18, fontWeight: '800' }, completeBody: { color: '#475467', lineHeight: 20, marginTop: 6 }, secondaryButton: { borderWidth: 1, borderColor: '#A6F4C5', borderRadius: 12, paddingVertical: 12, alignItems: 'center', marginTop: 14, minHeight: 48, justifyContent: 'center' }, secondaryButtonText: { color: '#027A48', fontWeight: '800' }, secondaryNeutralButton: { borderWidth: 1, borderColor: '#D0D5DD', borderRadius: 12, paddingVertical: 12, paddingHorizontal: 18, minHeight: 48, justifyContent: 'center' }, secondaryNeutralButtonText: { color: '#344054', fontWeight: '800' }, errorText: { color: '#B42318', textAlign: 'center', lineHeight: 20 }, note: { color: '#98A2B3', fontSize: 12, lineHeight: 18, marginTop: 18 },
});
