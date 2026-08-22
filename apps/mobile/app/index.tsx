import { Link } from 'expo-router';
import { SafeAreaView, ScrollView, StyleSheet, Text, View } from 'react-native';

const cards = [
  { title: 'Find shifts', body: 'Browse eligible jobs matched to your verified roles and skills.', href: '/shifts' as const },
  { title: 'My shifts', body: 'See accepted work, attendance status and submitted timesheets.', href: '/my-shifts' as const },
  { title: 'Earnings', body: 'Track estimated earnings and timesheet payment status in one place.', href: '/earnings' as const },
  { title: 'Clock in / out', body: 'Verify attendance at the assigned site using geofenced location.', href: '/attendance' as const },
  { title: 'Readiness', body: 'See identity, eligibility, role, vetting, training and consent checks in one place.', href: '/readiness' as const },
  { title: 'Profile & training', body: 'Complete onboarding, verification, certificates and required training.', href: '/onboarding' as const },
];

export default function HomeScreen() {
  return (
    <SafeAreaView style={styles.safe}>
      <ScrollView contentContainerStyle={styles.container}>
        <Text style={styles.eyebrow}>QY WORKFORCE</Text>
        <Text style={styles.title}>Work that fits your schedule.</Text>
        <Text style={styles.subtitle}>Verified shifts, clear pay, simple attendance and one worker profile.</Text>

        <View style={styles.statusCard}>
          <Text style={styles.statusTitle}>Deployment readiness</Text>
          <Text style={styles.statusValue}>Check your verified status</Text>
          <Link href="/readiness" style={styles.link}>View readiness →</Link>
        </View>

        {cards.map((card) => (
          <Link key={card.title} href={card.href} style={styles.card} accessibilityLabel={`${card.title}. ${card.body}`}>
            <View>
              <Text style={styles.cardTitle}>{card.title}</Text>
              <Text style={styles.cardBody}>{card.body}</Text>
              <Text style={styles.cardLink}>Open →</Text>
            </View>
          </Link>
        ))}
      </ScrollView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  safe: { flex: 1, backgroundColor: '#0A0A0A' },
  container: { padding: 24, gap: 16, paddingBottom: 48 },
  eyebrow: { color: '#A3A3A3', fontSize: 12, letterSpacing: 2 },
  title: { color: '#FFFFFF', fontSize: 34, fontWeight: '700', lineHeight: 40 },
  subtitle: { color: '#D4D4D4', fontSize: 17, lineHeight: 25, marginBottom: 8 },
  statusCard: { backgroundColor: '#171717', borderRadius: 18, padding: 20, gap: 7 },
  statusTitle: { color: '#A3A3A3', fontSize: 13 },
  statusValue: { color: '#FFFFFF', fontSize: 20, fontWeight: '600' },
  link: { color: '#FFFFFF', fontSize: 15, marginTop: 4 },
  card: { backgroundColor: '#111111', borderWidth: 1, borderColor: '#262626', borderRadius: 18, padding: 20 },
  cardTitle: { color: '#FFFFFF', fontSize: 18, fontWeight: '600' },
  cardBody: { color: '#B3B3B3', fontSize: 15, lineHeight: 22, marginTop: 8 },
  cardLink: { color: '#FFFFFF', fontSize: 14, fontWeight: '700', marginTop: 12 },
});
