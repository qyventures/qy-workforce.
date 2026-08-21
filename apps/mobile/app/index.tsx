import { Link } from 'expo-router';
import { SafeAreaView, ScrollView, StyleSheet, Text, View } from 'react-native';

const cards = [
  ['Find shifts', 'Browse eligible jobs matched to your verified roles and skills.'],
  ['My shifts', 'See accepted shifts, reporting instructions and attendance status.'],
  ['Clock in / out', 'Verify attendance at the assigned site using geofenced location.'],
  ['Profile & training', 'Complete onboarding, verification, certificates and required training.'],
];

export default function HomeScreen() {
  return (
    <SafeAreaView style={styles.safe}>
      <ScrollView contentContainerStyle={styles.container}>
        <Text style={styles.eyebrow}>QY WORKFORCE</Text>
        <Text style={styles.title}>Work that fits your schedule.</Text>
        <Text style={styles.subtitle}>Verified shifts, clear pay, simple attendance and one worker profile.</Text>
        <View style={styles.statusCard}>
          <Text style={styles.statusTitle}>Onboarding status</Text>
          <Text style={styles.statusValue}>Profile setup required</Text>
          <Link href="/onboarding" style={styles.link}>Continue onboarding →</Link>
        </View>
        {cards.map(([title, body]) => (
          <View key={title} style={styles.card}>
            <Text style={styles.cardTitle}>{title}</Text>
            <Text style={styles.cardBody}>{body}</Text>
          </View>
        ))}
      </ScrollView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  safe: { flex: 1, backgroundColor: '#0A0A0A' },
  container: { padding: 24, gap: 16 },
  eyebrow: { color: '#A3A3A3', fontSize: 12, letterSpacing: 2 },
  title: { color: '#FFFFFF', fontSize: 34, fontWeight: '700', lineHeight: 40 },
  subtitle: { color: '#D4D4D4', fontSize: 17, lineHeight: 25, marginBottom: 8 },
  statusCard: { backgroundColor: '#171717', borderRadius: 18, padding: 20, gap: 7 },
  statusTitle: { color: '#A3A3A3', fontSize: 13 },
  statusValue: { color: '#FFFFFF', fontSize: 20, fontWeight: '600' },
  link: { color: '#FFFFFF', fontSize: 15, marginTop: 4 },
  card: { backgroundColor: '#111111', borderWidth: 1, borderColor: '#262626', borderRadius: 18, padding: 20, gap: 8 },
  cardTitle: { color: '#FFFFFF', fontSize: 18, fontWeight: '600' },
  cardBody: { color: '#B3B3B3', fontSize: 15, lineHeight: 22 },
});
