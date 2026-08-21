import { useState } from 'react';
import { Alert, Pressable, StyleSheet, Text, View } from 'react-native';
import * as Location from 'expo-location';

type AttendanceState = 'idle' | 'locating' | 'clocked-in' | 'clocked-out';

const site = { latitude: 1.2834, longitude: 103.8607, radiusM: 250 };

function metresBetween(lat1: number, lon1: number, lat2: number, lon2: number) {
  const R = 6371000;
  const toRad = (v: number) => (v * Math.PI) / 180;
  const dLat = toRad(lat2 - lat1);
  const dLon = toRad(lon2 - lon1);
  const a = Math.sin(dLat / 2) ** 2 + Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLon / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(a));
}

export default function AttendanceScreen() {
  const [state, setState] = useState<AttendanceState>('idle');
  const [distanceM, setDistanceM] = useState<number | null>(null);

  const verifyAndRecord = async (action: 'in' | 'out') => {
    setState('locating');
    const permission = await Location.requestForegroundPermissionsAsync();
    if (permission.status !== 'granted') {
      setState(action === 'in' ? 'idle' : 'clocked-in');
      Alert.alert('Location required', 'QY Workforce only uses foreground location when you clock in or out.');
      return;
    }

    const position = await Location.getCurrentPositionAsync({ accuracy: Location.Accuracy.High });
    const distance = Math.round(metresBetween(position.coords.latitude, position.coords.longitude, site.latitude, site.longitude));
    setDistanceM(distance);

    if (distance > site.radiusM) {
      setState(action === 'in' ? 'idle' : 'clocked-in');
      Alert.alert('Outside worksite', `You are approximately ${distance}m from the approved clock-in point.`);
      return;
    }

    setState(action === 'in' ? 'clocked-in' : 'clocked-out');
  };

  const isWorking = state === 'clocked-in';

  return (
    <View style={styles.page}>
      <Text style={styles.eyebrow}>TODAY'S SHIFT</Text>
      <Text style={styles.title}>Banquet Crew</Text>
      <Text style={styles.client}>Harbour Hotel · Marina Bay</Text>

      <View style={styles.timeCard}>
        <Text style={styles.date}>22 Aug · 17:00–23:00</Text>
        <Text style={styles.status}>{isWorking ? 'You are clocked in' : state === 'clocked-out' ? 'Shift completed' : 'Ready to clock in'}</Text>
        {distanceM !== null && <Text style={styles.distance}>Last verified distance: {distanceM}m</Text>}
      </View>

      <View style={styles.privacyCard}>
        <Text style={styles.privacyTitle}>Location privacy</Text>
        <Text style={styles.privacyBody}>Location is requested only when you tap clock in or clock out. Continuous background tracking is not required for V1.</Text>
      </View>

      {state !== 'clocked-out' && (
        <Pressable
          disabled={state === 'locating'}
          style={[styles.primaryButton, isWorking && styles.outButton, state === 'locating' && styles.disabledButton]}
          onPress={() => verifyAndRecord(isWorking ? 'out' : 'in')}
        >
          <Text style={styles.primaryButtonText}>{state === 'locating' ? 'Checking location…' : isWorking ? 'Clock out' : 'Verify location & clock in'}</Text>
        </Pressable>
      )}

      {state === 'clocked-out' && (
        <View style={styles.completeCard}>
          <Text style={styles.completeTitle}>Attendance captured</Text>
          <Text style={styles.completeBody}>Your timesheet can now be calculated and sent for supervisor approval.</Text>
        </View>
      )}

      <Text style={styles.note}>This screen currently validates against a staging worksite coordinate. Server-side anti-spoofing, timestamp signing and Supabase event writes are the next integration step.</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  page: { flex: 1, padding: 24, paddingTop: 68, backgroundColor: '#F7F8FC' },
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
  primaryButton: { backgroundColor: '#4D63FF', borderRadius: 16, paddingVertical: 17, alignItems: 'center', marginTop: 22 },
  outButton: { backgroundColor: '#B42318' },
  disabledButton: { opacity: 0.55 },
  primaryButtonText: { color: '#FFFFFF', fontSize: 16, fontWeight: '800' },
  completeCard: { backgroundColor: '#ECFDF3', borderRadius: 18, padding: 18, marginTop: 22 },
  completeTitle: { color: '#027A48', fontSize: 18, fontWeight: '800' },
  completeBody: { color: '#475467', lineHeight: 20, marginTop: 6 },
  note: { color: '#98A2B3', fontSize: 12, lineHeight: 18, marginTop: 18 },
});