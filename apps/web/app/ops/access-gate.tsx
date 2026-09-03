'use client';

import { useEffect, useState, type ReactNode } from 'react';
import { usePathname, useRouter } from 'next/navigation';
import { supabase } from '../../lib/supabase';

export default function OpsAccessGate({ children }: { children: ReactNode }) {
  const pathname = usePathname();
  const router = useRouter();
  const isLogin = pathname === '/ops/login';
  const [checking, setChecking] = useState(!isLogin && Boolean(supabase));
  const [signedIn, setSignedIn] = useState(isLogin || !supabase);

  useEffect(() => {
    if (isLogin || !supabase) {
      setChecking(false);
      setSignedIn(true);
      return;
    }

    let active = true;
    void supabase.auth.getSession().then(({ data }) => {
      if (!active) return;
      if (!data.session) {
        router.replace('/ops/login');
        return;
      }
      setSignedIn(true);
      setChecking(false);
    });
    const { data: listener } = supabase.auth.onAuthStateChange((event, session) => {
      if (!active) return;
      if (event === 'SIGNED_OUT' || !session) {
        setSignedIn(false);
        router.replace('/ops/login');
      }
    });
    return () => {
      active = false;
      listener.subscription.unsubscribe();
    };
  }, [isLogin, router]);

  if (isLogin || !supabase || (!checking && signedIn)) return <>{children}</>;
  return <main style={{ minHeight: '100vh', display: 'grid', placeItems: 'center', padding: 24, background: '#f5f7fb', color: '#344054' }}>Checking staff session…</main>;
}
