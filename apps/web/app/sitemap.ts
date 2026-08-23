import type { MetadataRoute } from 'next';
import { industries } from './industries/industry-data';

const base = process.env.NEXT_PUBLIC_SITE_URL || 'https://workforce.qyvent.com';

export default function sitemap(): MetadataRoute.Sitemap {
  const corePaths = ['/', '/employers', '/workers', '/how-it-works', '/industries', '/trust', '/privacy', '/terms'];
  const industryPaths = industries.map((industry) => `/industries/${industry.id}`);
  const paths = [...corePaths, ...industryPaths];

  return paths.map((path) => ({
    url: `${base}${path}`,
    lastModified: new Date(),
    changeFrequency: path === '/' ? 'weekly' : 'monthly',
    priority: path === '/' ? 1 : path === '/employers' || path === '/workers' ? 0.9 : path.startsWith('/industries/') || path === '/trust' ? 0.8 : 0.7,
  }));
}
