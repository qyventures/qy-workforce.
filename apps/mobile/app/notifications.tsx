import { Link } from 'expo-router';
import { Pressable, SafeAreaView, ScrollView, StyleSheet, Text, View } from 'react-native';

const updates = [
  {
    title: 'Shift updates',
    body: 'Accepted shifts, schedule changes and assignment reminders will open directly to the relevant worker-safe screen.',
    href: '/my-shifts' as const,
  },
  {
    title: 'Attendance reminders',
    body: 'Clock-in and clock-out reminders can deep-link to an assignment only when a valid assignment identifier is present.',
    href: '/my-shifts' as const,
  },
  {
    title: 'Readiness alerts',
    body: 'Identity, training, consent or role-readiness changes can bring you back to your readiness checklist.',
    href: '/readiness' as const,
  },
];

export default function NotificationsScreen() {
  return (
    <SafeAreaView style={styles.safe}>
      <ScrollView contentContainerStyle={styles.container}>
        <Text style={styles.eyebrow}>UPDATES</Text>
        <Text style={styles.title} accessibilityRole="header">Stay ready for your next shift.</Text>
        <Text style={styles.subtitle}>
          This inbox is ready for trusted app links and push-notification routing. Notification delivery is only enabled when a non-production provider is configured.
        </Text>

        <View style={styles.info} accessible accessibilityLabel="Notification privacy information">
          <Text style={styles.infoTitle}>Privacy first</Text>
          <Text style={styles.infoBody}>
            Notifications should contain minimal information. Sensitive worker, attendance and pay details remain behind authenticated screens and backend authorization.
          </Text>
        </View>

        {updates.map((item) => (
          <Link key={item.title} href={item.href} asChild>
            <Pressable
              style={({ pressed }) => [styles.card, pressed && styles.cardPressed]}
              accessibilityRole="button"
              accessibilityLabel={`${item.title}. ${item.body}`}
              accessibilityHint="Opens the related worker screen"
            >
              <Text style={styles.cardTitle}>{item.title}</Text>
              <Text style={styles.cardBody}>{item.body}</Text>
              <Text style={styles.cardLink}>Open →</Text>
            </Pressable>
          </Link>
        ))}

        <Text style={styles.foot}>
          If you receive an unexpected message asking for a verification code or personal information, do not share it. Open QY Workforce directly instead.
        </Text>
      </ScrollView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  safe: { flex: 1, backgroundColor: '#0A0A0A' },
  container: { padding: 24, gap: 16, paddingBottom: 48 },
  eyebrow: { color: '#A3A3A3', fontSize: 12, letterSpacing: 2 },
  title: { color: '#FFFFFF', fontSize: 32, fontWeight: '700', lineHeight: 39 },
  subtitle: { color: '#D4D4D4', fontSize: 16, lineHeight: 24 },
  info: { backgroundColor: '#171717', borderRadius: 16, padding: 18, borderWidth: 1, borderColor: '#2A2A2A' },
  infoTitle: { color: '#FFFFFF', fontSize: 16, fontWeight: '700', marginBottom: 6 },
  infoBody: { color: '#B3B3B3', fontSize: 14, lineHeight: 21 },
  card: { backgroundColor: '#111111', borderWidth: 1, borderColor: '#262626', borderRadius: 18, padding: 20, minHeight: 120 },
  cardPressed: { opacity: 0.72 },
  cardTitle: { color: '#FFFFFF', fontSize: 18, fontWeight: '600' },
  cardBody: { color: '#B3B3B3', fontSize: 15, lineHeight: 22, marginTop: 8 },
  cardLink: { color: '#FFFFFF', fontSize: 14, fontWeight: '700', marginTop: 12 },
  foot: { color: '#8C8C8C', fontSize: 12, lineHeight: 18, marginTop: 8 },
});
