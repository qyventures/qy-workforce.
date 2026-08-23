'use client';

import { useEffect } from 'react';

declare global {
  interface Window {
    dataLayer?: Array<Record<string, unknown>>;
  }

  interface Navigator {
    globalPrivacyControl?: boolean;
  }
}

const ANALYTICS_CONSENT_KEY = 'qy-workforce:analytics-consent';

function analyticsAllowed() {
  if (navigator.globalPrivacyControl === true || navigator.doNotTrack === '1') return false;
  try {
    return window.localStorage.getItem(ANALYTICS_CONSENT_KEY) === 'granted';
  } catch {
    return false;
  }
}

export default function AnalyticsEvents() {
  useEffect(() => {
    const onClick = (event: MouseEvent) => {
      if (!analyticsAllowed()) return;

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
