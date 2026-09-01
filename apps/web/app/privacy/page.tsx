import type { Metadata } from 'next';
import { ConsentBanner, SiteFooter, SiteHeader } from '../components/site-shell';

export const metadata: Metadata = {
  title: 'Privacy Notice | QY Workforce',
  description: 'How QY Workforce handles information submitted through its public website and workforce services.',
  alternates: { canonical: '/privacy' },
};

const sectionStyle = { marginTop: 30 };

export default function PrivacyPage() {
  return <main style={{ minHeight: '100vh', background: '#fff', color: '#101828' }}>
    <SiteHeader />
    <article style={{ maxWidth: 820, margin: '0 auto', padding: '64px 24px 76px', lineHeight: 1.7 }}>
      <p style={{ letterSpacing: 1.5, fontSize: 12, fontWeight: 800, color: '#475467' }}>QY WORKFORCE</p>
      <h1 style={{ fontSize: 'clamp(36px, 5vw, 56px)', letterSpacing: '-.04em', lineHeight: 1.06, margin: '10px 0 14px' }}>Privacy Notice</h1>
      <p><strong>Last updated: 1 September 2026</strong></p>
      <p>This notice explains how QY Workforce handles personal data collected through this website and in connection with workforce services. It is written for the pilot service and will be updated with the final legal-entity and data-protection contact details before any wider public launch.</p>
      <section style={sectionStyle}><h2>Information we collect</h2><p>For employer enquiries and worker-interest registrations, we collect the information you choose to submit, such as your name, contact details, company details, work interests, availability and location preferences. During onboarding or shift operations, we may separately collect verification, readiness, assignment, attendance and timesheet records needed for the relevant service.</p></section>
      <section style={sectionStyle}><h2>How we use it</h2><p>We use information to respond to enquiries, assess worker interest and readiness, operate assignments, support attendance and timesheet workflows, communicate where you have agreed, protect the service from misuse, and meet applicable legal or contractual obligations. Submitting a public form does not itself create an employment or client-service agreement.</p></section>
      <section style={sectionStyle}><h2>Location and sensitive information</h2><p>We do not ask for NRIC, bank, health, or identity-document details through public forms. Location information may be submitted when a worker actively clocks in or out for an assigned shift; the pilot does not use continuous background location tracking.</p></section>
      <section style={sectionStyle}><h2>Sharing and retention</h2><p>We may share data with authorised QY Workforce personnel, relevant client-site contacts where needed to operate a shift, and service providers acting on our instructions. We may also disclose data where required by law. We do not sell personal data. Data is retained only for the purpose collected, operational and dispute needs, and applicable legal requirements.</p></section>
      <section id="analytics" style={sectionStyle}><h2>Optional anonymous analytics</h2><p>Our website asks before enabling optional analytics. If you allow it and an analytics endpoint is configured, we send only an event name, page path and timestamp to a first-party endpoint. We do not send form contents, names, email addresses, phone numbers, advertising cookies, device identifiers, or fingerprinting data. You can decline without affecting use of the website.</p></section>
      <section style={sectionStyle}><h2>Your choices</h2><p>You can decline optional analytics and WhatsApp follow-up. You may also ask to access, correct, or withdraw consent for personal data, subject to applicable requirements and records we must retain. Until a dedicated privacy contact is published, please use the relevant public enquiry form and clearly state that your request concerns privacy; do not include identification documents in that request.</p></section>
      <section style={sectionStyle}><h2>Security</h2><p>We use safeguards designed to protect information, including access controls, audit logging, encryption in transit, data minimisation and retention controls. No online service can guarantee absolute security.</p></section>
    </article>
    <SiteFooter /><ConsentBanner />
  </main>;
}
