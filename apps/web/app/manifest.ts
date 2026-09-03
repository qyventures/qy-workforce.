import type { MetadataRoute } from 'next';

export default function manifest(): MetadataRoute.Manifest {
  return {
    name: 'QY Workforce',
    short_name: 'QY Workforce',
    description: 'Flexible staffing for Singapore employers and workers.',
    start_url: '/',
    display: 'standalone',
    background_color: '#ffffff',
    theme_color: '#101828',
    lang: 'en-SG',
  };
}
