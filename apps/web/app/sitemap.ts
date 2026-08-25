import type { MetadataRoute } from 'next';

const base = process.env.NEXT_PUBLIC_SITE_URL || 'https://qyworkforce.com';

export default function sitemap(): MetadataRoute.Sitemap {
  const paths = ['/', '/employers', '/workers', '/how-it-works', '/industries', '/privacy', '/terms'];
  return paths.map((path) => ({
    url: `${base}${path}`,
    lastModified: new Date(),
    changeFrequency: path === '/' ? 'weekly' : 'monthly',
    priority: path === '/' ? 1 : path === '/employers' || path === '/workers' ? 0.9 : 0.7,
  }));
}
