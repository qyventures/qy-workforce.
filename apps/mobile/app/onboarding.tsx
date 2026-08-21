import { useState } from 'react';
import { SafeAreaView, ScrollView, StyleSheet, Text, TextInput, TouchableOpacity, View } from 'react-native';

export default function OnboardingScreen() {
  const [consented, setConsented] = useState(false);
  return (
    <SafeAreaView style={styles.safe}>
      <ScrollView contentContainerStyle={styles.container}>
        <Text style={styles.kicker}>WORKER ONBOARDING</Text>
        <Text style={styles.title}>Set up your worker profile</Text>
        <Text style={styles.body}>Only information needed for eligibility, attendance, deployment and payment will be collected. Identity verification will use a Singpass-ready flow when production access is approved.</Text>
        <TextInput placeholder="Full name" placeholderTextColor="#777" style={styles.input} />
        <TextInput placeholder="Mobile number" placeholderTextColor="#777" keyboardType="phone-pad" style={styles.input} />
        <TextInput placeholder="Email" placeholderTextColor="#777" keyboardType="email-address" autoCapitalize="none" style={styles.input} />
        <Text style={styles.section}>Primary work interests</Text>
        <View style={styles.tags}>{['Hospitality','F&B','Cleaning','Retail','Promoter','Events'].map(x => <View key={x} style={styles.tag}><Text style={styles.tagText}>{x}</Text></View>)}</View>
        <TouchableOpacity onPress={() => setConsented(!consented)} style={styles.consent} accessibilityRole="checkbox" accessibilityState={{checked: consented}}>
          <View style={[styles.box, consented && styles.boxChecked]} />
          <Text style={styles.consentText}>I consent to QY Workforce using my data for worker onboarding, eligibility, shift matching, attendance and workforce administration.</Text>
        </TouchableOpacity>
        <TouchableOpacity disabled={!consented} style={[styles.button, !consented && styles.buttonDisabled]}><Text style={styles.buttonText}>Continue to verification</Text></TouchableOpacity>
      </ScrollView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  safe:{flex:1,backgroundColor:'#0A0A0A'},container:{padding:24,gap:16},kicker:{color:'#888',fontSize:12,letterSpacing:2},title:{color:'#fff',fontSize:32,fontWeight:'700'},body:{color:'#bbb',fontSize:15,lineHeight:22},input:{borderWidth:1,borderColor:'#333',borderRadius:12,padding:16,color:'#fff',backgroundColor:'#111'},section:{color:'#fff',fontSize:17,fontWeight:'600',marginTop:4},tags:{flexDirection:'row',flexWrap:'wrap',gap:8},tag:{borderWidth:1,borderColor:'#333',borderRadius:999,paddingVertical:9,paddingHorizontal:13},tagText:{color:'#ddd'},consent:{flexDirection:'row',gap:12,alignItems:'flex-start',marginTop:8},box:{width:22,height:22,borderRadius:5,borderWidth:1,borderColor:'#666'},boxChecked:{backgroundColor:'#fff'},consentText:{color:'#bbb',flex:1,lineHeight:20},button:{backgroundColor:'#fff',borderRadius:12,padding:16,alignItems:'center',marginTop:8},buttonDisabled:{opacity:0.35},buttonText:{color:'#000',fontWeight:'700'}
});
