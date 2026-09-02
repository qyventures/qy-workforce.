import type { Metadata } from 'next';
import { ConsentBanner, SiteFooter, SiteHeader } from '../components/site-shell';

export const metadata: Metadata = {
  title: 'Terms of Use | QY Workforce',
  description: 'Terms governing use of the QY Workforce public website and pilot enquiry forms.',
  alternates: { canonical: '/terms' },
};

const sectionStyle = { marginTop: 30 };

export default function TermsPage() {
  return <main id="main-content" style={{ minHeight: '100vh', background: '#fff', color: '#101828' }}>
    <SiteHeader />
    <article style={{ maxWidth: 820, margin: '0 auto', padding: '64px 24px 76px', lineHeight: 1.7 }}>
      <p style={{ letterSpacing: 1.5, fontSize: 12, fontWeight: 800, color: '#475467' }}>QY WORKFORCE</p>
      <h1 style={{ fontSize: 'clamp(36px, 5vw, 56px)', letterSpacing: '-.04em', lineHeight: 1.06, margin: '10px 0 14px' }}>Terms of Use</h1>
      <p><strong>Last updated: 1 September 2026</strong></p>
      <p>These terms govern use of the QY Workforce website and pilot enquiry forms. They do not replace any employment, client-service, or other agreement that may be provided separately.</p>
      <section style={sectionStyle}><h2>Using this website</h2><p>You may use this website to learn about QY Workforce and submit genuine employer or worker-interest enquiries. You must not attempt unauthorised access, interfere with the website, submit misleading information, or use the forms for unlawful purposes.</p></section>
      <section style={sectionStyle}><h2>Employer enquiries</h2><p>An enquiry is a request for a discussion only. It does not create a booking, guaranteed fulfilment level, service agreement, or other binding commitment. Rates, scope, worker suitability, site requirements and final terms are confirmed separately.</p></section>
      <section style={sectionStyle}><h2>Worker interest</h2><p>Registering interest does not create an employment relationship, guarantee a shift, or confirm eligibility. Onboarding, identity checks, role requirements, availability and any applicable work arrangements are handled separately before a worker can be deployed.</p></section>
      <section style={sectionStyle}><h2>Website information</h2><p>We aim to keep information current, but service features, supported roles and availability may change as the pilot develops. Do not rely on website information as a promise of a particular shift, worker, rate or outcome.</p></section>
      <section style={sectionStyle}><h2>Content and liability</h2><p>QY Workforce branding and original website content may not be copied or reused without permission except as permitted by law. To the extent allowed by law, the website is provided without warranties and QY Workforce is not liable for indirect or consequential loss arising from its use.</p></section>
      <section style={sectionStyle}><h2>Pilot status</h2><p>The service is being prepared for pilot use. Final legal-entity details, governing-law provisions and service-specific terms will be published before a wider public launch.</p></section>
    </article>
    <SiteFooter /><ConsentBanner />
  </main>;
}
