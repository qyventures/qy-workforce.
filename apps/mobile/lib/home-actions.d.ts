export type HomeAction = {
  title: string;
  body: string;
  href: '/shifts' | '/my-shifts' | '/earnings' | '/notifications' | '/readiness' | '/onboarding';
};

export const HOME_ACTIONS: HomeAction[];
export function homeAction(title: string): HomeAction | null;
