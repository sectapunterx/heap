import { useCallback, useEffect, useRef, useState } from 'react';

export function useToast<T = string>(ms = 2600) {
  const [toast, setToast] = useState<T | null>(null);
  const timer = useRef<ReturnType<typeof setTimeout>>(undefined);
  const show = useCallback(
    (msg: T) => {
      setToast(msg);
      clearTimeout(timer.current);
      timer.current = setTimeout(() => setToast(null), ms);
    },
    [ms],
  );
  useEffect(() => () => clearTimeout(timer.current), []);
  return [toast, show] as const;
}
