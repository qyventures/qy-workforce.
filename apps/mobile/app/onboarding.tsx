import { useMemo, useState } from 'react';
import {
  Alert,
  SafeAreaView,
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
  TouchableOpacity,
  View,
} from 'react-native';
import { router } from 'expo-router';
import { supabase } from '../lib/supabase';
import { isLikelyNetworkError, mobileErrorMessage } from '../lib/errors';
import {
  MAX_EMAIL_LENGTH,
  MAX_INTERESTS,
  MAX_NAME_LENGTH,
  canSubmitOnboarding,
  isValidOptionalEmail,
  normalizeEmail,
} from '../lib/onboarding.mjs';

const POLICY_VERSION = '2026-08-22';
const WORK_INTERESTS = [
  { label: 'Hospitality', code: 'banquet' },
  { label: 'F&B Service', code: 'fnb_service' },
  { label: 'F&B Kitchen', code: 'fnb_kitchen' },
  { label: 'Cleaning', code: 'cleaner' },
  { label: 'Retail', code: 'retail' },
  { label: 'Promoter', code: 'promoter' },
  { label: 'Events', code: 'event_crew' },
];

export default function OnboardingScreen() {
  const [fullName, setFullName] = useState('');
  const [email, setEmail] = useState('');
  const [selected, setSelected] = useState<string[]>([]);
  const [consented, setConsented] = useState(false);
  const [submitting, setSubmitting] = useState(false);
  const [status, setStatus] = useState('');

  const trimmedName = fullName.trim();
  const emailValid = isValidOptionalEmail(email);
  const canContinue = useMemo(
    () => canSubmitOnboarding({
      fullName,
      email,
      selectedInterests: selected,
      consented,
      submitting,
    }),
    [fullName, email, selected, consented, submitting]
  );

  function toggleInterest(code: string) {
    setStatus('');
    setSelected(current => {
      if (current.includes(code)) return current.filter(x => x !== code);
      if (current.length >= MAX_INTERESTS) {
        setStatus(`Choose up to ${MAX_INTERESTS} work interests so we can keep your shift feed relevant.`);
        return current;
      }
      return [...current, code];
    });
  }

  async function submit() {
    if (!canContinue) return;
    setStatus('');

    if (!supabase) {
      Alert.alert('Demo mode', 'Profile data was not transmitted because the staging backend is not configured on this build.');
      router.push('/readiness');
      return;
    }

    setSubmitting(true);
    let profileSaved = false;

    try {
      const { data: sessionData, error: sessionError } = await supabase.auth.getSession();
      if (sessionError) throw sessionError;
      if (!sessionData.session?.user) {
        router.replace('/sign-in');
        return;
      }

      // A security-definer RPC controls exactly which worker fields can be created or changed.
      // The app never receives direct write access to verification, eligibility or deployability status.
      const { error: onboardingError } = await supabase.rpc('complete_worker_onboarding', {
        p_display_name: trimmedName,
        p_role_codes: selected,
        p_policy_version: POLICY_VERSION,
      });
      if (onboardingError) throw onboardingError;
      profileSaved = true;

      // Optional email remains in the authenticated user's private metadata rather than
      // being duplicated into workforce tables until a business purpose requires it.
      const normalizedEmail = normalizeEmail(email);
      if (normalizedEmail) {
        const { error: metadataError } = await supabase.auth.updateUser({
          data: { onboarding_email: normalizedEmail },
        });
        if (metadataError) {
          // The worker profile has already been securely created. Do not turn a secondary
          // metadata failure into a misleading onboarding failure or encourage duplicate retries.
          setStatus('Your worker profile is saved. We could not save the optional email right now; you can continue safely.');
        }
      }

      router.replace('/readiness');
    } catch (error) {
      if (profileSaved) {
        setStatus('Your worker profile was saved. Continue to readiness before trying onboarding again.');
        router.replace('/readiness');
        return;
      }

      const message = isLikelyNetworkError(error)
        ? 'Your connection may have dropped while saving. Reconnect and check readiness before retrying, in case the server already received your profile.'
        : mobileErrorMessage(error, 'Unable to complete onboarding. Please review your details and try again.');
      setStatus(message);
      Alert.alert('Onboarding not completed', message);
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <SafeAreaView style={styles.safe}>
      <ScrollView contentContainerStyle={styles.container} keyboardShouldPersistTaps="handled">
        <Text style={styles.kicker}>WORKER ONBOARDING</Text>
        <Text style={styles.title} accessibilityRole="header">Set up your worker profile</Text>
        <Text style={styles.body}>We collect only what is needed for eligibility, attendance, deployment and payment. Identity verification is Singpass-ready and stays in mock/staging mode until production access is approved.</Text>

        <TextInput
          value={fullName}
          onChangeText={value => {
            setStatus('');
            setFullName(value.slice(0, MAX_NAME_LENGTH));
          }}
          placeholder="Full name"
          placeholderTextColor="#777"
          autoComplete="name"
          textContentType="name"
          maxLength={MAX_NAME_LENGTH}
          accessibilityLabel="Full name"
          style={styles.input}
        />
        <TextInput
          value={email}
          onChangeText={value => {
            setStatus('');
            setEmail(value.slice(0, MAX_EMAIL_LENGTH));
          }}
          placeholder="Email (optional)"
          placeholderTextColor="#777"
          keyboardType="email-address"
          autoCapitalize="none"
          autoCorrect={false}
          autoComplete="email"
          textContentType="emailAddress"
          maxLength={MAX_EMAIL_LENGTH}
          accessibilityLabel="Email, optional"
          accessibilityHint="Used only as private account metadata during onboarding"
          style={[styles.input, !emailValid && styles.inputError]}
        />
        {!emailValid && <Text style={styles.errorText} accessibilityLiveRegion="polite">Enter a valid email address or leave this field blank.</Text>}

        <Text style={styles.section}>Primary work interests</Text>
        <Text style={styles.hint}>Choose 1–{MAX_INTERESTS}. An interest is not an approved deployment role until verification, vetting and training requirements are complete.</Text>
        <View style={styles.tags} accessibilityRole="list">
          {WORK_INTERESTS.map(item => {
            const active = selected.includes(item.code);
            const disabled = !active && selected.length >= MAX_INTERESTS;
            return (
              <TouchableOpacity
                key={item.code}
                onPress={() => toggleInterest(item.code)}
                disabled={disabled}
                style={[styles.tag, active && styles.tagActive, disabled && styles.tagDisabled]}
                accessibilityRole="checkbox"
                accessibilityLabel={`${item.label} work interest`}
                accessibilityState={{ checked: active, disabled }}
              >
                <Text style={[styles.tagText, active && styles.tagTextActive]}>{item.label}</Text>
              </TouchableOpacity>
            );
          })}
        </View>
        <Text style={styles.selectionCount} accessibilityLiveRegion="polite">{selected.length} of {MAX_INTERESTS} selected</Text>

        <TouchableOpacity
          onPress={() => {
            setStatus('');
            setConsented(!consented);
          }}
          style={styles.consent}
          accessibilityRole="checkbox"
          accessibilityLabel="Consent to required workforce data use"
          accessibilityState={{ checked: consented }}
        >
          <View style={[styles.box, consented && styles.boxChecked]}><Text style={styles.check}>{consented ? '✓' : ''}</Text></View>
          <Text style={styles.consentText}>I consent to QY Workforce using my data for identity verification, work eligibility, location-based attendance and workforce administration under policy version {POLICY_VERSION}.</Text>
        </TouchableOpacity>

        {!!status && <Text style={styles.status} accessibilityLiveRegion="polite">{status}</Text>}

        <TouchableOpacity
          disabled={!canContinue}
          onPress={submit}
          style={[styles.button, !canContinue && styles.buttonDisabled]}
          accessibilityRole="button"
          accessibilityLabel="Continue to readiness"
          accessibilityState={{ disabled: !canContinue, busy: submitting }}
        >
          <Text style={styles.buttonText}>{submitting ? 'Saving…' : 'Continue to readiness'}</Text>
        </TouchableOpacity>
      </ScrollView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  safe:{flex:1,backgroundColor:'#0A0A0A'},container:{padding:24,gap:16},kicker:{color:'#888',fontSize:12,letterSpacing:2},title:{color:'#fff',fontSize:32,fontWeight:'700'},body:{color:'#bbb',fontSize:15,lineHeight:22},input:{borderWidth:1,borderColor:'#333',borderRadius:12,padding:16,minHeight:52,color:'#fff',backgroundColor:'#111'},inputError:{borderColor:'#9f4a4a'},errorText:{color:'#ffb4b4',fontSize:13,lineHeight:18,marginTop:-8},section:{color:'#fff',fontSize:17,fontWeight:'600',marginTop:4},hint:{color:'#8f8f8f',fontSize:13,lineHeight:19,marginTop:-8},tags:{flexDirection:'row',flexWrap:'wrap',gap:8},tag:{borderWidth:1,borderColor:'#333',borderRadius:999,paddingVertical:11,paddingHorizontal:14,minHeight:44,justifyContent:'center'},tagActive:{backgroundColor:'#fff',borderColor:'#fff'},tagDisabled:{opacity:0.35},tagText:{color:'#ddd'},tagTextActive:{color:'#000',fontWeight:'700'},selectionCount:{color:'#8f8f8f',fontSize:12},consent:{flexDirection:'row',gap:12,alignItems:'flex-start',marginTop:8,minHeight:44},box:{width:24,height:24,borderRadius:5,borderWidth:1,borderColor:'#666',alignItems:'center',justifyContent:'center'},boxChecked:{backgroundColor:'#fff'},check:{color:'#000',fontWeight:'800'},consentText:{color:'#bbb',flex:1,lineHeight:20},status:{color:'#d4d4d4',fontSize:13,lineHeight:19,borderWidth:1,borderColor:'#333',backgroundColor:'#111',borderRadius:10,padding:12},button:{backgroundColor:'#fff',borderRadius:12,padding:16,minHeight:52,alignItems:'center',justifyContent:'center',marginTop:8},buttonDisabled:{opacity:0.35},buttonText:{color:'#000',fontWeight:'700'}
});
