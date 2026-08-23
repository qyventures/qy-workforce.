import { useEffect, useMemo, useState } from 'react';
import { router } from 'expo-router';
import { SafeAreaView, StyleSheet, Text, TextInput, TouchableOpacity, View } from 'react-native';
import { isLikelyNetworkError } from '../lib/errors';
import { MAX_OTP_LENGTH, isValidOtp, isValidPhone, normalizeOtp, normalizePhone } from '../lib/otp.mjs';
import { supabase } from '../lib/supabase';

const RESEND_COOLDOWN_SECONDS = 45;

export default function SignInScreen() {
  const [phone, setPhone] = useState('+65');
  const [token, setToken] = useState('');
  const [stage, setStage] = useState<'phone' | 'otp'>('phone');
  const [message, setMessage] = useState('');
  const [busy, setBusy] = useState(false);
  const [resendSeconds, setResendSeconds] = useState(0);

  useEffect(() => {
    if (resendSeconds <= 0) return;
    const timer = setTimeout(() => setResendSeconds((value) => Math.max(0, value - 1)), 1000);
    return () => clearTimeout(timer);
  }, [resendSeconds]);

  const normalizedPhone = useMemo(() => normalizePhone(phone), [phone]);
  const normalizedToken = useMemo(() => normalizeOtp(token), [token]);
  const canRequestOtp = !busy && resendSeconds === 0 && isValidPhone(normalizedPhone);
  const canVerifyOtp = !busy && isValidOtp(normalizedToken);

  async function requestOtp() {
    if (!supabase) {
      setMessage('Staging sign-in is not configured on this build.');
      return;
    }

    if (!isValidPhone(normalizedPhone)) {
      setMessage('Enter a valid mobile number including country code.');
      return;
    }

    if (!canRequestOtp) return;

    setBusy(true);
    setMessage('');
    try {
      const { error } = await supabase.auth.signInWithOtp({ phone: normalizedPhone });
      if (error) throw error;
      setPhone(normalizedPhone);
      setToken('');
      setStage('otp');
      setResendSeconds(RESEND_COOLDOWN_SECONDS);
      setMessage('If this number can receive verification messages, enter the latest code sent to your mobile.');
    } catch (error) {
      setMessage(
        isLikelyNetworkError(error)
          ? 'We could not reach the sign-in service. Check your connection and try again.'
          : 'We could not send a verification code. Please try again shortly.'
      );
    } finally {
      setBusy(false);
    }
  }

  async function verifyOtp() {
    if (!supabase) return;
    if (!isValidOtp(normalizedToken)) {
      setMessage('Enter the verification code.');
      return;
    }

    setBusy(true);
    setMessage('');
    try {
      const { error } = await supabase.auth.verifyOtp({ phone: normalizedPhone, token: normalizedToken, type: 'sms' });
      if (error) throw error;
      setToken('');
      router.replace('/');
    } catch (error) {
      setMessage(
        isLikelyNetworkError(error)
          ? 'We could not verify the code because the connection was interrupted. Check your connection and try again.'
          : 'The verification code could not be accepted. Check the code or request a new one.'
      );
    } finally {
      setBusy(false);
    }
  }

  function changeNumber() {
    setStage('phone');
    setToken('');
    setMessage('');
    setResendSeconds(0);
  }

  return (
    <SafeAreaView style={styles.safe}>
      <View style={styles.container}>
        <Text style={styles.eyebrow}>QY WORKFORCE</Text>
        <Text style={styles.title} accessibilityRole="header">Sign in securely</Text>
        <Text style={styles.body}>Use your mobile number to access your worker profile, shifts and attendance. Never share your verification code.</Text>

        {stage === 'phone' ? (
          <>
            <Text style={styles.label}>Mobile number</Text>
            <TextInput
              value={phone}
              onChangeText={(value) => {
                setMessage('');
                setPhone(value);
              }}
              keyboardType="phone-pad"
              autoComplete="tel"
              textContentType="telephoneNumber"
              style={styles.input}
              placeholder="+65 8123 4567"
              placeholderTextColor="#737373"
              accessibilityLabel="Mobile number including country code"
              accessibilityHint="Include your country code, for example plus 65 for Singapore"
              editable={!busy}
              returnKeyType="done"
              onSubmitEditing={requestOtp}
            />
            <TouchableOpacity
              disabled={!canRequestOtp}
              onPress={requestOtp}
              style={[styles.button, !canRequestOtp && styles.disabled]}
              accessibilityRole="button"
              accessibilityState={{ disabled: !canRequestOtp, busy }}
              accessibilityLabel="Send verification code"
            >
              <Text style={styles.buttonText}>{busy ? 'Sending…' : 'Send verification code'}</Text>
            </TouchableOpacity>
          </>
        ) : (
          <>
            <Text style={styles.number}>Code sent to {phone}</Text>
            <Text style={styles.label}>Verification code</Text>
            <TextInput
              value={token}
              onChangeText={(value) => {
                setMessage('');
                setToken(normalizeOtp(value));
              }}
              keyboardType="number-pad"
              autoComplete="sms-otp"
              textContentType="oneTimeCode"
              secureTextEntry
              maxLength={MAX_OTP_LENGTH}
              style={styles.input}
              placeholder="Enter code"
              placeholderTextColor="#737373"
              accessibilityLabel="Verification code"
              accessibilityHint="Enter the latest code sent to your mobile"
              editable={!busy}
              returnKeyType="done"
              onSubmitEditing={verifyOtp}
            />
            <TouchableOpacity
              disabled={!canVerifyOtp}
              onPress={verifyOtp}
              style={[styles.button, !canVerifyOtp && styles.disabled]}
              accessibilityRole="button"
              accessibilityState={{ disabled: !canVerifyOtp, busy }}
              accessibilityLabel="Verify code and sign in"
            >
              <Text style={styles.buttonText}>{busy ? 'Verifying…' : 'Verify and sign in'}</Text>
            </TouchableOpacity>

            <TouchableOpacity
              disabled={!canRequestOtp}
              onPress={requestOtp}
              style={[styles.secondary, !canRequestOtp && styles.disabled]}
              accessibilityRole="button"
              accessibilityState={{ disabled: !canRequestOtp }}
              accessibilityLabel={resendSeconds > 0 ? `Resend verification code in ${resendSeconds} seconds` : 'Resend verification code'}
            >
              <Text style={styles.secondaryText}>
                {resendSeconds > 0 ? `Resend code in ${resendSeconds}s` : 'Resend verification code'}
              </Text>
            </TouchableOpacity>

            <TouchableOpacity
              disabled={busy}
              onPress={changeNumber}
              style={styles.secondary}
              accessibilityRole="button"
              accessibilityState={{ disabled: busy }}
              accessibilityLabel="Use a different mobile number"
            >
              <Text style={styles.secondaryText}>Use a different number</Text>
            </TouchableOpacity>
          </>
        )}

        {message ? <Text style={styles.message} accessibilityLiveRegion="polite">{message}</Text> : null}
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
  number: { color: '#A3A3A3', fontSize: 13, marginBottom: 16 },
  label: { color: '#D4D4D4', fontSize: 14, marginBottom: 8 },
  input: { backgroundColor: '#171717', borderWidth: 1, borderColor: '#333333', borderRadius: 12, padding: 15, color: '#FFFFFF', fontSize: 18, marginBottom: 14, minHeight: 52 },
  button: { backgroundColor: '#FFFFFF', borderRadius: 12, padding: 16, minHeight: 52, alignItems: 'center', justifyContent: 'center' },
  buttonText: { color: '#111111', fontWeight: '700', fontSize: 16 },
  disabled: { opacity: 0.55 },
  secondary: { padding: 14, minHeight: 48, alignItems: 'center', justifyContent: 'center' },
  secondaryText: { color: '#D4D4D4' },
  message: { color: '#E5E7EB', marginTop: 18, lineHeight: 20 },
  privacy: { color: '#737373', fontSize: 12, lineHeight: 18, marginTop: 28 },
});
