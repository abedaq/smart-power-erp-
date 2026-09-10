import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import './index.css'
import App from './App.tsx'

// Intercept beforeinput event to convert Eastern Arabic / Persian digits (٠-٩) to English digits (0-9) cleanly before DOM insertion
if (typeof window !== 'undefined') {
  document.addEventListener('beforeinput', (e: any) => {
    if (e.data && /[\u0660-\u0669\u06F0-\u06F9]/.test(e.data)) {
      const normalized = e.data
        .replace(/[\u0660-\u0669]/g, (d: string) => String.fromCharCode(d.charCodeAt(0) - 1632 + 48))
        .replace(/[\u06F0-\u06F9]/g, (d: string) => String.fromCharCode(d.charCodeAt(0) - 1776 + 48));
      
      e.preventDefault();
      document.execCommand('insertText', false, normalized);
    }
  }, true);
}

const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      staleTime: 60 * 1000,
      refetchOnWindowFocus: false,
      retry: 1,
    },
  },
});

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <QueryClientProvider client={queryClient}>
      <App />
    </QueryClientProvider>
  </StrictMode>,
)
