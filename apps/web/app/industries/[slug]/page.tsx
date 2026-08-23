import type { Metadata } from 'next';
import { notFound } from 'next/navigation';
import { getIndustry, industries } from '../industry-data';

type IndustryPageProps = { params: Promise<{ slug: string }> };

export function generateStaticParams() {
  return industries.map((industry) => ({ slug: industry.id }));
}

export async function generateMetadata({ params }: IndustryPageProps): Promise<Metadata> {
  const { slug } = await params;
  const industry = getIndustry(slug);
  if (!industry) return {};
  const canonical = `/industries/${industry.id}`;
  const description = `${industry.employer} QY Workforce supports ${industry.name.toLowerCase()} employers and workers with readiness, attendance and approval controls.`;
  return {
    title: `${industry.name} Staffing | QY Workforce`,
    description,
    alternates: { canonical },
    openGraph: { title: `${industry.name} Staffing | QY Workforce`, description, url: canonical, type: 'website' },
  };
}

export default async function IndustryPage({ params }: IndustryPageProps) {
  const { slug } = await params;
  const industry = getIndustry(slug);
  if (!industry) notFound();

  const canonicalUrl = `https://workforce.qyvent.com/industries/${industry.id}`;
  const structuredData = {
    '@context': 'https://schema.org',
    '@type': 'Service',
    name: `${industry.name} staffing by QY Workforce`,
    description: industry.employer,
    url: canonicalUrl,
    provider: {
      '@type': 'Organization',
      name: 'QY Workforce',
      url: 'https://workforce.qyvent.com',
    },
    areaServed: {
      '@type': 'Country',
      name: 'Singapore',
    },
    serviceType: `${industry.name} staffing and workforce operations`,
  };

  return (
    <main style={{ minHeight: '100vh', background: '#F7F8FB', color: '#101828', padding: '56px 24px 72px' }}>
      <script
        type="application/ld+json"
        dangerouslySetInnerHTML={{ __html: JSON.stringify(structuredData).replace(/</g, '\\u003c') }}
      />
      <section style={{ maxWidth: 1080, margin: '0 auto' }}>
        <nav aria-label="Breadcrumb" style={{ display: 'flex', gap: 8, flexWrap: 'wrap', color: '#667085', fontSize: 14 }}>
          <a href="/" style={{ color: '#344054', textDecoration: 'none', fontWeight: 750 }}>QY Workforce</a>
          <span aria-hidden="true">/</span>
          <a href="/industries" style={{ color: '#344054', textDecoration: 'none' }}>Industries</a>
          <span aria-hidden="true">/</span>
          <span aria-current="page">{industry.name}</span>
        </nav>

        <div style={{ marginTop: 44, color: '#4D63FF', fontWeight: 850, fontSize: 12, letterSpacing: 1.3 }}>INDUSTRY STAFFING</div>
        <h1 style={{ fontSize: 'clamp(40px,6vw,70px)', lineHeight: 1.03, letterSpacing: '-.045em', maxWidth: 900, margin: '10px 0 16px' }}>{industry.name} staffing with operational control built in.</h1>
        <p style={{ fontSize: 19, color: '#667085', lineHeight: 1.65, maxWidth: 820 }}>{industry.employer}</p>

        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit,minmax(260px,1fr))', gap: 18, marginTop: 34 }}>
          <section style={{ background: '#fff', border: '1px solid #E4E7EC', borderRadius: 18, padding: 24 }}>
            <p style={{ margin: '0 0 8px', color: '#4D63FF', fontWeight: 800, fontSize: 12, letterSpacing: 1 }}>FOR EMPLOYERS</p>
            <h2 style={{ margin: '0 0 10px', fontSize: 25 }}>Fill demand without losing visibility.</h2>
            <p style={{ margin: 0, color: '#667085', lineHeight: 1.6 }}>{industry.employer}</p>
            <a href={`/employers?industry=${industry.id}`} data-analytics-event={`industry_page_${industry.id}_employer`} style={{ display: 'inline-block', marginTop: 20, background: '#111827', color: '#fff', padding: '12px 16px', borderRadius: 10, textDecoration: 'none', fontWeight: 800 }}>Request manpower</a>
          </section>
          <section style={{ background: '#fff', border: '1px solid #E4E7EC', borderRadius: 18, padding: 24 }}>
            <p style={{ margin: '0 0 8px', color: '#667085', fontWeight: 800, fontSize: 12, letterSpacing: 1 }}>FOR WORKERS</p>
            <h2 style={{ margin: '0 0 10px', fontSize: 25 }}>See suitable work with clear expectations.</h2>
            <p style={{ margin: 0, color: '#667085', lineHeight: 1.6 }}>{industry.worker}</p>
            <a href={`/workers?industry=${industry.id}`} data-analytics-event={`industry_page_${industry.id}_worker`} style={{ display: 'inline-block', marginTop: 20, border: '1px solid #D0D5DD', color: '#344054', padding: '12px 16px', borderRadius: 10, textDecoration: 'none', fontWeight: 800 }}>Find suitable shifts</a>
          </section>
        </div>

        <section style={{ marginTop: 18, background: '#fff', border: '1px solid #E4E7EC', borderRadius: 18, padding: 24 }}>
          <h2 style={{ margin: '0 0 16px', fontSize: 25 }}>Typical roles</h2>
          <div style={{ display: 'flex', gap: 9, flexWrap: 'wrap' }}>
            {industry.roles.map((role) => <span key={role} style={{ background: '#F2F4F7', color: '#344054', padding: '8px 11px', borderRadius: 999, fontSize: 14 }}>{role}</span>)}
          </div>
        </section>

        <section style={{ marginTop: 18, background: '#101828', color: '#fff', borderRadius: 18, padding: 26 }}>
          <h2 style={{ margin: '0 0 16px', fontSize: 27 }}>How QY Workforce keeps deployments controlled</h2>
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit,minmax(220px,1fr))', gap: 12 }}>
            {industry.proofPoints.map((point, index) => (
              <div key={point} style={{ border: '1px solid #344054', borderRadius: 14, padding: 18 }}>
                <span style={{ color: '#98A2B3', fontSize: 12, fontWeight: 800 }}>0{index + 1}</span>
                <p style={{ margin: '7px 0 0', lineHeight: 1.5 }}>{point}</p>
              </div>
            ))}
          </div>
          <a href="/how-it-works" data-analytics-event={`industry_page_${industry.id}_workflow`} style={{ display: 'inline-block', marginTop: 22, color: '#fff', fontWeight: 800 }}>See the full workflow →</a>
        </section>
      </section>
    </main>
  );
}
