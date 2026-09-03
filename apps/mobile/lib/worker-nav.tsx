import { Pressable, StyleSheet, Text, View } from 'react-native';
import { router, usePathname } from 'expo-router';

const links = [
  { href: '/', label: 'Home' },
  { href: '/shifts', label: 'Find shifts' },
  { href: '/my-shifts', label: 'My shifts' },
  { href: '/earnings', label: 'Earnings' },
  { href: '/readiness', label: 'Readiness' },
] as const;

/** Lightweight, screen-level navigation for workers on phones and tablets. */
export function WorkerNav() {
  const pathname = usePathname();

  return (
    <View style={styles.nav} accessibilityLabel="Worker navigation">
      {links.map((link) => {
        const active = pathname === link.href;
        return (
          <Pressable
            key={link.href}
            accessibilityRole="button"
            accessibilityState={{ selected: active }}
            accessibilityLabel={`Go to ${link.label}`}
            style={[styles.item, active && styles.activeItem]}
            onPress={() => router.replace(link.href)}
          >
            <Text style={[styles.label, active && styles.activeLabel]}>{link.label}</Text>
          </Pressable>
        );
      })}
    </View>
  );
}

const styles = StyleSheet.create({
  nav: { flexDirection: 'row', flexWrap: 'wrap', gap: 6, padding: 6, borderRadius: 16, backgroundColor: '#EEF1F5', marginTop: 4 },
  item: { flex: 1, minHeight: 44, paddingHorizontal: 4, borderRadius: 11, alignItems: 'center', justifyContent: 'center' },
  activeItem: { backgroundColor: '#111827' },
  label: { color: '#475467', fontSize: 12, fontWeight: '700', textAlign: 'center' },
  activeLabel: { color: '#FFFFFF' },
});
