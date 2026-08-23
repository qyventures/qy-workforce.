import { useEffect, useMemo, useState } from 'react';
import { ActivityIndicator, Alert, Pressable, RefreshControl, ScrollView, StyleSheet, Text, View } from 'react-native';
import { router } from 'expo-router';
import { supabase } from '../lib/supabase';
import { isLikelyNetworkError } from '../lib/errors';
import { formatShiftTime, normalizeAvailableShift, shiftAccessibilityLabel, shiftAcceptanceSummary, type AvailableShift } from '../lib/shifts.mjs';

type Shift = AvailableShift;

const demoShifts: Shift[] = [
  { id: 'shift-001', role: 'Banquet Crew', client: 'Harbour Hotel', site: 'Marina Bay', startsAt: '2026-08-22T17:00:00+08:00', endsAt: '2026-08-22T23:00:00+08:00', rate: 16, requirements: ['Black pants', 'Covered shoes'], availableSlots: 4 },
  { id: 'shift-002', role: 'Retail Promoter', client: 'Lifestyle Retailer', site: 'Orchard', startsAt: '2026-08-23T11:00:00+08:00', endsAt: '2026-08-23T20:00:00+08:00', rate: 15, requirements: ['Customer service'], availableSlots: 2 },
];

export default function ShiftsScreen() {
  const [shifts, setShifts] = useState<Shift[]>(supabase ? [] : demoShifts);
  const [loading, setLoading] = useState(Boolean(supabase));
  const [refreshing, setRefreshing] = useState(false);
  const [acceptingId, setAcceptingId] = useState<string | null>(null);
  const [connectionIssue, setConnectionIssue] = useState(false);

  const sorted = useMemo(() => [...shifts].sort((a, b) => Date.parse(a.startsAt) - Date.parse(b.startsAt)), [shifts]);

  const loadShifts = async (refresh = false) => {
    if (!supabase) return;
    refresh ? setRefreshing(true) : setLoading(true);

    const { data, error } = await supabase.rpc('get_available_shifts');
    if (error) {
      const offline = isLikelyNetworkError(error);
      setConnectionIssue(offline);
      Alert.alert('Unable to load shifts', offline
        ? 'You may be offline or on an unstable connection. Reconnect, then retry.'
        : 'Please try again. No private client data has been cached on this device.');
    } else {
      setConnectionIssue(false);
      setShifts((data ?? []).map(normalizeAvailableShift).filter((shift): shift is Shift => shift !== null));
    }
    setLoading(false);
    setRefreshing(false);
  };

  useEffect(() => { void loadShifts(); }, []);

  const acceptShift = async (shift: Shift) => {
    if (acceptingId !== null) return;
    if (!supabase) { router.push('/attendance'); return; }
    setAcceptingId(shift.id);
    const { data: assignmentId, error } = await supabase.rpc('accept_shift', { p_shift_id: shift.id });
    setAcceptingId(null);

    if (error) {
      const offline = isLikelyNetworkError(error);
      setConnectionIssue(offline);
      Alert.alert('Shift not accepted', offline
        ? 'Your connection appears unavailable. We did not assume the shift was accepted. Reconnect and check My Shifts before trying again.'
        : error.message.includes('full')
          ? 'This shift has just filled up. Refresh to see other jobs.'
          : 'Your eligibility or shift availability changed. Refresh and try again.');
      if (!offline) await loadShifts(true);
      return;
    }

    setConnectionIssue(false);
    setShifts((current) => current.filter((item) => item.id !== shift.id));
    router.push({ pathname: '/attendance', params: { assignmentId: String(assignmentId), shiftId: shift.id } });
  };

  const confirmShift = (shift: Shift) => {
    if (acceptingId !== null) return;
    Alert.alert(
      'Accept this shift?',
      `${shiftAcceptanceSummary(shift)}\n\nThe server will re-check your eligibility and availability before confirming.`,
      [
        { text: 'Cancel', style: 'cancel' },
        { text: 'Accept shift', onPress: () => void acceptShift(shift) },
      ]
    );
  };

  return (
    <ScrollView contentContainerStyle={styles.page} refreshControl={<RefreshControl refreshing={refreshing} onRefresh={() => void loadShifts(true)} accessibilityLabel="Refresh available shifts" />}>
      <View style={styles.headerRow}>
        <View><Text style={styles.eyebrow}>AVAILABLE SHIFTS</Text><Text style={styles.title} accessibilityRole="header">Find a shift</Text></View>
        <Pressable style={styles.profileButton} onPress={() => router.push('/readiness')} accessibilityRole="button" accessibilityLabel="View readiness"><Text style={styles.profileButtonText}>Readiness</Text></Pressable>
      </View>
      <Text style={styles.subtitle}>Only jobs matching your approved roles and deployability are shown.</Text>
      {connectionIssue && <View style={styles.connectionCard} accessibilityRole="alert"><Text style={styles.connectionTitle}>Connection issue</Text><Text style={styles.connectionBody}>Reconnect to the internet, then retry. Shift acceptance is never assumed when the server cannot confirm it.</Text><Pressable style={styles.retryButton} onPress={() => void loadShifts(true)} accessibilityRole="button" accessibilityLabel="Retry loading available shifts"><Text style={styles.retryButtonText}>Retry</Text></Pressable></View>}
      {loading && <View style={styles.loadingBlock} accessibilityRole="progressbar" accessibilityLabel="Loading available shifts"><ActivityIndicator size="large" /><Text style={styles.loadingText}>Checking eligible shifts…</Text></View>}
      {!loading && sorted.length === 0 && <View style={styles.emptyCard}><Text style={styles.emptyTitle}>No eligible shifts right now</Text><Text style={styles.emptyBody}>New shifts will appear here when they match your approved roles and readiness status.</Text></View>}
      {sorted.map((shift) => (
        <View key={shift.id} style={styles.card} accessible accessibilityLabel={shiftAccessibilityLabel(shift)}>
          <View style={styles.cardTop}><View style={{ flex: 1 }}><Text style={styles.role}>{shift.role}</Text><Text style={styles.client}>{[shift.client, shift.site].filter(Boolean).join(' · ')}</Text></View><View style={styles.ratePill}><Text style={styles.rate}>S${shift.rate.toFixed(2)}/hr</Text></View></View>
          <Text style={styles.meta}>{formatShiftTime(shift.startsAt, shift.endsAt)}</Text>
          <Text style={styles.meta}>{shift.availableSlots} slot{shift.availableSlots === 1 ? '' : 's'} remaining</Text>
          {shift.requirements.length > 0 && <View style={styles.tags}>{shift.requirements.map((item) => <View key={item} style={styles.tag}><Text style={styles.tagText}>{item}</Text></View>)}</View>}
          <Pressable accessibilityRole="button" accessibilityLabel={`Accept ${shift.role} shift`} accessibilityHint="Review the shift details, then confirm before the server re-checks eligibility and availability" disabled={acceptingId !== null} style={[styles.primaryButton, acceptingId !== null && styles.disabledButton]} onPress={() => confirmShift(shift)}><Text style={styles.primaryButtonText}>{acceptingId === shift.id ? 'Securing shift…' : 'Review & accept'}</Text></Pressable>
        </View>
      ))}
      <Pressable style={styles.secondaryButton} onPress={() => router.push('/my-shifts')} accessibilityRole="button" accessibilityLabel="View my accepted shifts"><Text style={styles.secondaryButtonText}>View my accepted shifts</Text></Pressable>
      <Text style={styles.note}>{supabase ? 'Live staging feed. Pull down to refresh.' : 'Demo mode only. Configure staging Supabase environment variables to use live matching.'}</Text>
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  page: { padding: 22, paddingTop: 64, backgroundColor: '#F5F7FB', flexGrow: 1 }, headerRow: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center' }, eyebrow: { fontSize: 12, fontWeight: '800', letterSpacing: 1.3, color: '#4D63FF' }, title: { fontSize: 32, lineHeight: 38, fontWeight: '800', color: '#111827', marginTop: 4 }, subtitle: { fontSize: 16, lineHeight: 23, color: '#667085', marginTop: 8, marginBottom: 18 }, profileButton: { backgroundColor: '#E8ECFF', paddingHorizontal: 14, paddingVertical: 10, borderRadius: 12, minHeight: 44, justifyContent: 'center' }, profileButtonText: { color: '#3448C5', fontWeight: '700' }, connectionCard: { backgroundColor: '#FFF4E5', borderRadius: 16, padding: 16, marginBottom: 14 }, connectionTitle: { color: '#B54708', fontWeight: '800', fontSize: 16 }, connectionBody: { color: '#7A2E0E', marginTop: 6, lineHeight: 20 }, retryButton: { alignSelf: 'flex-start', marginTop: 12, minHeight: 44, justifyContent: 'center', paddingHorizontal: 16, borderRadius: 10, backgroundColor: '#7A2E0E' }, retryButtonText: { color: '#FFFFFF', fontWeight: '800' }, loadingBlock: { alignItems: 'center', marginVertical: 32, gap: 10 }, loadingText: { color: '#667085', fontWeight: '600' }, emptyCard: { backgroundColor: '#FFFFFF', borderRadius: 20, padding: 20, marginBottom: 14 }, emptyTitle: { fontSize: 18, fontWeight: '800', color: '#101828' }, emptyBody: { marginTop: 7, color: '#667085', lineHeight: 20 }, card: { backgroundColor: '#FFFFFF', borderRadius: 20, padding: 18, marginBottom: 14, shadowColor: '#000', shadowOpacity: 0.05, shadowRadius: 10, shadowOffset: { width: 0, height: 4 }, elevation: 2 }, cardTop: { flexDirection: 'row', alignItems: 'flex-start', gap: 12 }, role: { fontSize: 20, fontWeight: '800', color: '#101828' }, client: { marginTop: 5, fontSize: 14, color: '#667085' }, ratePill: { backgroundColor: '#EEFDF3', paddingHorizontal: 10, paddingVertical: 7, borderRadius: 999 }, rate: { fontWeight: '800', color: '#027A48' }, meta: { marginTop: 12, color: '#344054', fontWeight: '600' }, tags: { flexDirection: 'row', flexWrap: 'wrap', gap: 8, marginTop: 14 }, tag: { backgroundColor: '#F2F4F7', borderRadius: 999, paddingHorizontal: 10, paddingVertical: 6 }, tagText: { fontSize: 12, color: '#475467', fontWeight: '600', textTransform: 'capitalize' }, primaryButton: { backgroundColor: '#111827', borderRadius: 14, paddingVertical: 15, alignItems: 'center', marginTop: 18, minHeight: 48, justifyContent: 'center' }, disabledButton: { opacity: 0.55 }, primaryButtonText: { color: '#FFFFFF', fontWeight: '800', fontSize: 15 }, secondaryButton: { borderWidth: 1, borderColor: '#D0D5DD', borderRadius: 14, paddingVertical: 14, alignItems: 'center', marginTop: 4, minHeight: 48, justifyContent: 'center' }, secondaryButtonText: { color: '#344054', fontWeight: '800' }, note: { color: '#98A2B3', fontSize: 12, lineHeight: 18, marginTop: 16, marginBottom: 28 },
});