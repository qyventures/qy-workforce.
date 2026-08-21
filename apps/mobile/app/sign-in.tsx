import { useState } from 'react';
import { router } from 'expo-router';
import { SafeAreaView, StyleSheet, Text, TextInput, TouchableOpacity, View } from 'react-native';
import { supabase } from '../lib/supabase';

export default function SignInScreen() {
  const [phone, setPhone] = useState('+65');
  const [token, setToken] = useState('');
  const [stage, setStage] = useState<'phone' | 'otp'>('phone');
  const [message, setMessage] = useState('');
  const [busy, setBusy] = useState(false);

  async function requestOtp() {
    if (!supabase) { setMessage('Staging sign-in is not configured on this build.'); return; }
    const normalized = phone.replace(/[\s()-]/g, '');
    if (!/^\+[1-9]\d{7,14}$/.test(normalized)) { setMessage('Enter a valid mobile number including country code.'); return; }
    setBusy(true); setMessage('');
    const { error } = await supabase.auth.signInWithOtp({ phone: normalized });
    setBusy(false);
    if (error) setMessage(error.message);
    else { setPhone(normalized); setStage('otp'); setMessage('Enter the verification code sent to your mobile.'); }
  }

  async function verifyOtp() {
    if (!supabase) return;
    if (!/^\d{4,8}$/.test(token)) { setMessage('Enter the verification code.'); return; }
    setBusy(true); setMessage('');
    const { error } = await supabase.auth.verifyOtp({ phone, token, type: 'sms' });
    setBusy(false);
    if (error) setMessage(error.message);
    else router.replace('/');
  }

  return (
    <SafeAreaView style={styles.safe}>
      <View style={styles.container}>
        <Text style={styles.eyebrow}>QY WORKFORCE</Text>
        <Text style={styles.title}>Sign in securely</Text>
        <Text style={styles.body}>Use your mobile number to access your worker profile, shifts and attendance. Never share your verification code.</Text>

        {stage === 'phone' ? (
          <>
            <Text style={styles.label}>Mobile number</Text>
            <TextInput
              value={phone}
              onChangeText={setPhone}
              keyboardType="phone-pad"
              autoComplete="tel"
              textContentType="telephoneNumber"
              style={styles.input}
              placeholder="+65 8123 4567"
              placeholderTextColor="#737373"
            />
            <TouchableOpacity disabled={busy} onPress={requestOtp} style={[styles.button, busy && styles.disabled]}>
              <Text style={styles.buttonText}>{busy ? 'Sending…' : 'Send verification code'}</Text>
            </TouchableOpacity>
          </>
        ) : (
          <>
            <Text style={styles.label}>Verification code</Text>
            <TextInput
              value={token}
              onChangeText={setToken}
              keyboardType="number-pad"
              autoComplete="sms-otp"
              textContentType="oneTimeCode"
              secureTextEntry
              maxLength={8}
              style={styles.input}
              placeholder="Enter code"
              placeholderTextColor="#737373"
            />
            <TouchableOpacity disabled={busy} onPress={verifyOtp} style={[styles.button, busy && styles.disabled]}>
              <Text style={styles.buttonText}>{busy ? 'Verifying…' : 'Verify and sign in'}</Text>
            </TouchableOpacity>
            <TouchableOpacity onPress={() => { setStage('phone'); setToken(''); setMessage(''); }} style={styles.secondary}>
              <Text style={styles.secondaryText}>Use a different number</Text>
            </TouchableOpacity>
          </>
        )}

        {message ? <Text style={styles.message}>{message}</Text> : null}
        <Text style={styles.privacy}>QY Workforce stores an authenticated session securely on this device. SMS delivery remains disabled until a staging Supabase authentication provider is configured.</Text>
      </View>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  safe: { flex: 1, backgroundColor: '#0A0A0A' },
  container: { flex: 1, padding: 24, justifyContent: 'center' },
  eyebrow: { color: '#A3A3A3', fontSize: 12, letterSpacing: 2, marginBottom: 12 },
  title: { color: '#FFFFFF', fontSize: 34, fontWeight: '700', marginBottom: 12 },
  body: { color: '#B3B3B3', fontSize: 16, lineHeight: 24, marginBottom: 28 },
  label: { color: '#D4D4D4', fontSize: 14, marginBottom: 8 },
  input: { backgroundColor: '#171717', borderWidth: 1, borderColor: '#333333', borderRadius: 12, padding: 15, color: '#FFFFFF', fontSize: 18, marginBottom: 14 },
  button: { backgroundColor: '#FFFFFF', borderRadius: 12, padding: 16, alignItems: 'center' },
  buttonText: { color: '#111111', fontWeight: '700', fontSize: 16 },
  disabled: { opacity: 0.55 },
  secondary: { padding: 16, alignItems: 'center' },
  secondaryText: { color: '#D4D4D4' },
  message: { color: '#E5E7EB', marginTop: 18, lineHeight: 20 },
  privacy: { color: '#737373', fontSize: 12, lineHeight: 18, marginTop: 28 },
});
