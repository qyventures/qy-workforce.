import { useMemo, useState } from 'react';
import { Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { router } from 'expo-router';

type Shift = {
  id: string;
  role: string;
  client: string;
  site: string;
  date: string;
  time: string;
  rate: number;
  distanceKm: number;
  requirements: string[];
};

const shifts: Shift[] = [
  {
    id: 'shift-001',
    role: 'Banquet Crew',
    client: 'Harbour Hotel',
    site: 'Marina Bay',
    date: '22 Aug',
    time: '17:00–23:00',
    rate: 16,
    distanceKm: 2.1,
    requirements: ['Black pants', 'Covered shoes'],
  },
  {
    id: 'shift-002',
    role: 'Retail Promoter',
    client: 'Lifestyle Retailer',
    site: 'Orchard',
    date: '23 Aug',
    time: '11:00–20:00',
    rate: 15,
    distanceKm: 4.8,
    requirements: ['Customer service'],
  },
  {
    id: 'shift-003',
    role: 'Cleaning Crew',
    client: 'City Serviced Residence',
    site: 'Bugis',
    date: '24 Aug',
    time: '09:00–17:00',
    rate: 17,
    distanceKm: 3.3,
    requirements: ['Training verified'],
  },
];

export default function ShiftsScreen() {
  const [accepted, setAccepted] = useState<string | null>(null);
  const sorted = useMemo(() => [...shifts].sort((a, b) => a.distanceKm - b.distanceKm), []);

  return (
    <ScrollView contentContainerStyle={styles.page}>
      <View style={styles.headerRow}>
        <View>
          <Text style={styles.eyebrow}>AVAILABLE NOW</Text>
          <Text style={styles.title}>Find a shift</Text>
        </View>
        <Pressable style={styles.profileButton} onPress={() => router.push('/onboarding')}>
          <Text style={styles.profileButtonText}>Profile</Text>
        </Pressable>
      </View>

      <Text style={styles.subtitle}>Matched to your verified skills and work preferences.</Text>

      {sorted.map((shift) => {
        const isAccepted = accepted === shift.id;
        return (
          <View key={shift.id} style={styles.card}>
            <View style={styles.cardTop}>
              <View style={{ flex: 1 }}>
                <Text style={styles.role}>{shift.role}</Text>
                <Text style={styles.client}>{shift.client} · {shift.site}</Text>
              </View>
              <View style={styles.ratePill}>
                <Text style={styles.rate}>S${shift.rate}/hr</Text>
              </View>
            </View>

            <Text style={styles.meta}>{shift.date} · {shift.time}</Text>
            <Text style={styles.meta}>{shift.distanceKm.toFixed(1)} km away</Text>

            <View style={styles.tags}>
              {shift.requirements.map((item) => (
                <View key={item} style={styles.tag}><Text style={styles.tagText}>{item}</Text></View>
              ))}
            </View>

            <Pressable
              accessibilityRole="button"
              style={[styles.primaryButton, isAccepted && styles.acceptedButton]}
              onPress={() => setAccepted(shift.id)}
            >
              <Text style={styles.primaryButtonText}>{isAccepted ? 'Shift accepted' : 'Accept shift'}</Text>
            </Pressable>

            {isAccepted && (
              <Pressable style={styles.secondaryButton} onPress={() => router.push('/attendance')}>
                <Text style={styles.secondaryButtonText}>Open attendance</Text>
              </Pressable>
            )}
          </View>
        );
      })}

      <Text style={styles.note}>Demo data only. Live availability will come from Supabase once staging credentials are configured.</Text>
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  page: { padding: 22, paddingTop: 64, backgroundColor: '#F5F7FB', flexGrow: 1 },
  headerRow: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center' },
  eyebrow: { fontSize: 12, fontWeight: '800', letterSpacing: 1.3, color: '#4D63FF' },
  title: { fontSize: 32, lineHeight: 38, fontWeight: '800', color: '#111827', marginTop: 4 },
  subtitle: { fontSize: 16, lineHeight: 23, color: '#667085', marginTop: 8, marginBottom: 18 },
  profileButton: { backgroundColor: '#E8ECFF', paddingHorizontal: 14, paddingVertical: 10, borderRadius: 12 },
  profileButtonText: { color: '#3448C5', fontWeight: '700' },
  card: { backgroundColor: '#FFFFFF', borderRadius: 20, padding: 18, marginBottom: 14, shadowColor: '#000', shadowOpacity: 0.05, shadowRadius: 10, shadowOffset: { width: 0, height: 4 }, elevation: 2 },
  cardTop: { flexDirection: 'row', alignItems: 'flex-start', gap: 12 },
  role: { fontSize: 20, fontWeight: '800', color: '#101828' },
  client: { marginTop: 5, fontSize: 14, color: '#667085' },
  ratePill: { backgroundColor: '#EEFDF3', paddingHorizontal: 10, paddingVertical: 7, borderRadius: 999 },
  rate: { fontWeight: '800', color: '#027A48' },
  meta: { marginTop: 12, color: '#344054', fontWeight: '600' },
  tags: { flexDirection: 'row', flexWrap: 'wrap', gap: 8, marginTop: 14 },
  tag: { backgroundColor: '#F2F4F7', borderRadius: 999, paddingHorizontal: 10, paddingVertical: 6 },
  tagText: { fontSize: 12, color: '#475467', fontWeight: '600' },
  primaryButton: { backgroundColor: '#111827', borderRadius: 14, paddingVertical: 15, alignItems: 'center', marginTop: 18 },
  acceptedButton: { backgroundColor: '#147A55' },
  primaryButtonText: { color: '#FFFFFF', fontWeight: '800', fontSize: 15 },
  secondaryButton: { borderWidth: 1, borderColor: '#D0D5DD', borderRadius: 14, paddingVertical: 14, alignItems: 'center', marginTop: 10 },
  secondaryButtonText: { color: '#344054', fontWeight: '800' },
  note: { color: '#98A2B3', fontSize: 12, lineHeight: 18, marginTop: 8, marginBottom: 28 },
});