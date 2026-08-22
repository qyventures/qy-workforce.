'use client';

import { useEffect } from 'react';

declare global {
  interface Window {
    dataLayer?: Array<Record<string, unknown>>;
  }
}

export default function AnalyticsEvents() {
  useEffect(() => {
    const onClick = (event: MouseEvent) => {
      const target = event.target instanceof Element ? event.target.closest<HTMLElement>('[data-analytics-event]') : null;
      const eventName = target?.dataset.analyticsEvent;
      if (!eventName) return;

      const payload = {
        event: 'qy_workforce_conversion',
        action: eventName,
        path: window.location.pathname,
      };

      window.dispatchEvent(new CustomEvent('qy-workforce:analytics', { detail: payload }));
      if (Array.isArray(window.dataLayer)) window.dataLayer.push(payload);
    };

    document.addEventListener('click', onClick);
    return () => document.removeEventListener('click', onClick);
  }, []);

  return null;
}
