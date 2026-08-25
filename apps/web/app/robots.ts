import type { MetadataRoute } from 'next';

const base = process.env.NEXT_PUBLIC_SITE_URL || 'https://qyworkforce.com';

export default function robots(): MetadataRoute.Robots {
  return {
    rules: [
      {
        userAgent: '*',
        allow: '/',
        disallow: ['/ops/', '/api/'],
      },
    ],
    sitemap: `${base}/sitemap.xml`,
  };
}
