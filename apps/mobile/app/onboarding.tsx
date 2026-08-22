import { useMemo, useState } from 'react';
import { Alert, SafeAreaView, ScrollView, StyleSheet, Text, TextInput, TouchableOpacity, View } from 'react-native';
import { router } from 'expo-router';
import { supabase } from '../lib/supabase';

const POLICY_VERSION = '2026-08-22';
const WORK_INTERESTS = ['Hospitality','F&B','Cleaning','Retail','Promoter','Events'];

export default function OnboardingScreen() {
  const [fullName, setFullName] = useState('');
  const [email, setEmail] = useState('');
  const [selected, setSelected] = useState<string[]>([]);
  const [consented, setConsented] = useState(false);
  const [submitting, setSubmitting] = useState(false);

  const canContinue = useMemo(
    () => fullName.trim().length >= 2 && selected.length > 0 && consented && !submitting,
    [fullName, selected, consented, submitting]
  );

  function toggleInterest(value: string) {
    setSelected(current => current.includes(value) ? current.filter(x => x !== value) : [...current, value]);
  }

  async function submit() {
    if (!canContinue) return;

    if (!supabase) {
      Alert.alert('Demo mode', 'Profile data was not transmitted because the staging backend is not configured on this build.');
      router.push('/readiness');
      return;
    }

    setSubmitting(true);
    try {
      const { data: sessionData, error: sessionError } = await supabase.auth.getSession();
      if (sessionError) throw sessionError;
      const user = sessionData.session?.user;
      if (!user) {
        router.replace('/sign-in');
        return;
      }

      const { error: profileError } = await supabase
        .from('profiles')
        .upsert({
          id: user.id,
          role: 'worker',
          display_name: fullName.trim(),
          phone: user.phone ?? null,
          updated_at: new Date().toISOString(),
        }, { onConflict: 'id' });
      if (profileError) throw profileError;

      const { error: workerError } = await supabase
        .from('worker_profiles')
        .upsert({ user_id: user.id }, { onConflict: 'user_id' });
      if (workerError) throw workerError;

      // Work interests are intentionally kept in auth metadata only until a worker-role
      // mapping is approved by ops. This avoids granting unverified role eligibility.
      const { error: metadataError } = await supabase.auth.updateUser({
        data: {
          onboarding_email: email.trim() || null,
          work_interests: selected,
          onboarding_policy_version: POLICY_VERSION,
        },
      });
      if (metadataError) throw metadataError;

      const consentRows = ['identity_verification','work_eligibility','location_clocking'].map(purpose => ({
        worker_id: user.id,
        purpose,
        policy_version: POLICY_VERSION,
        granted: true,
        source: 'worker_app',
      }));
      const { error: consentError } = await supabase.from('worker_consents').insert(consentRows);
      if (consentError) throw consentError;

      router.replace('/readiness');
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Unable to complete onboarding.';
      Alert.alert('Onboarding not completed', message);
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <SafeAreaView style={styles.safe}>
      <ScrollView contentContainerStyle={styles.container} keyboardShouldPersistTaps="handled">
        <Text style={styles.kicker}>WORKER ONBOARDING</Text>
        <Text style={styles.title}>Set up your worker profile</Text>
        <Text style={styles.body}>We collect only what is needed for eligibility, attendance, deployment and payment. Identity verification is Singpass-ready and stays in mock/staging mode until production access is approved.</Text>

        <TextInput
          value={fullName}
          onChangeText={setFullName}
          placeholder="Full name"
          placeholderTextColor="#777"
          autoComplete="name"
          textContentType="name"
          style={styles.input}
        />
        <TextInput
          value={email}
          onChangeText={setEmail}
          placeholder="Email (optional)"
          placeholderTextColor="#777"
          keyboardType="email-address"
          autoCapitalize="none"
          autoComplete="email"
          textContentType="emailAddress"
          style={styles.input}
        />

        <Text style={styles.section}>Primary work interests</Text>
        <Text style={styles.hint}>Choose at least one. Selection does not make you deployable until verification and role approval are complete.</Text>
        <View style={styles.tags}>
          {WORK_INTERESTS.map(x => {
            const active = selected.includes(x);
            return (
              <TouchableOpacity
                key={x}
                onPress={() => toggleInterest(x)}
                style={[styles.tag, active && styles.tagActive]}
                accessibilityRole="checkbox"
                accessibilityState={{ checked: active }}
              >
                <Text style={[styles.tagText, active && styles.tagTextActive]}>{x}</Text>
              </TouchableOpacity>
            );
          })}
        </View>

        <TouchableOpacity
          onPress={() => setConsented(!consented)}
          style={styles.consent}
          accessibilityRole="checkbox"
          accessibilityState={{ checked: consented }}
        >
          <View style={[styles.box, consented && styles.boxChecked]}><Text style={styles.check}>{consented ? '✓' : ''}</Text></View>
          <Text style={styles.consentText}>I consent to QY Workforce using my data for identity verification, work eligibility, location-based attendance and workforce administration under policy version {POLICY_VERSION}.</Text>
        </TouchableOpacity>

        <TouchableOpacity disabled={!canContinue} onPress={submit} style={[styles.button, !canContinue && styles.buttonDisabled]}>
          <Text style={styles.buttonText}>{submitting ? 'Saving…' : 'Continue to readiness'}</Text>
        </TouchableOpacity>
      </ScrollView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  safe:{flex:1,backgroundColor:'#0A0A0A'},container:{padding:24,gap:16},kicker:{color:'#888',fontSize:12,letterSpacing:2},title:{color:'#fff',fontSize:32,fontWeight:'700'},body:{color:'#bbb',fontSize:15,lineHeight:22},input:{borderWidth:1,borderColor:'#333',borderRadius:12,padding:16,color:'#fff',backgroundColor:'#111'},section:{color:'#fff',fontSize:17,fontWeight:'600',marginTop:4},hint:{color:'#8f8f8f',fontSize:13,lineHeight:19,marginTop:-8},tags:{flexDirection:'row',flexWrap:'wrap',gap:8},tag:{borderWidth:1,borderColor:'#333',borderRadius:999,paddingVertical:9,paddingHorizontal:13},tagActive:{backgroundColor:'#fff',borderColor:'#fff'},tagText:{color:'#ddd'},tagTextActive:{color:'#000',fontWeight:'700'},consent:{flexDirection:'row',gap:12,alignItems:'flex-start',marginTop:8},box:{width:22,height:22,borderRadius:5,borderWidth:1,borderColor:'#666',alignItems:'center',justifyContent:'center'},boxChecked:{backgroundColor:'#fff'},check:{color:'#000',fontWeight:'800'},consentText:{color:'#bbb',flex:1,lineHeight:20},button:{backgroundColor:'#fff',borderRadius:12,padding:16,alignItems:'center',marginTop:8},buttonDisabled:{opacity:0.35},buttonText:{color:'#000',fontWeight:'700'}
});
