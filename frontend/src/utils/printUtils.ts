/**
 * Robust cross-browser helper to print a specific DOM element cleanly
 * without including web layout controls, modals, or page backgrounds.
 * Sets the document and iframe title to the customer's / document's name
 * so that PDF exports and printer queues reflect the person's name accurately.
 */
export interface PrintOptions {
  orientation?: 'portrait' | 'landscape';
  pageSize?: 'A4' | 'A5' | 'thermal80mm' | 'auto';
  margin?: string;
}

export function sanitizePrintTitle(title: string): string {
  if (!title) return 'مستند_طباعة';
  return title
    .replace(/[/\\?%*:|"<>]/g, '-')
    .replace(/\s+/g, '_')
    .trim();
}

export function printElementViaIframe(
  elementId: string,
  title = 'طباعة',
  options: PrintOptions = {}
): void {
  const targetElement = document.getElementById(elementId);
  if (!targetElement) {
    console.error(`Print target element #${elementId} not found`);
    window.print();
    return;
  }

  const safeTitle = sanitizePrintTitle(title);
  const originalDocTitle = document.title;

  // Temporarily set document title so browser print dialog suggests this name
  document.title = safeTitle;

  // Create temporary hidden print iframe with renderable offscreen dimensions
  const iframe = document.createElement('iframe');
  iframe.style.position = 'fixed';
  iframe.style.left = '-9999px';
  iframe.style.top = '-9999px';
  iframe.style.width = '1024px';
  iframe.style.height = '768px';
  iframe.style.border = '0';
  iframe.style.opacity = '0';
  iframe.style.pointerEvents = 'none';
  iframe.setAttribute('aria-hidden', 'true');
  document.body.appendChild(iframe);

  const doc = iframe.contentWindow?.document;
  if (!doc) {
    window.print();
    document.title = originalDocTitle;
    if (document.body.contains(iframe)) {
      document.body.removeChild(iframe);
    }
    return;
  }

  const styles = Array.from(document.querySelectorAll('style, link[rel="stylesheet"]'))
    .map((style) => style.outerHTML)
    .join('\n');

  const {
    orientation = 'portrait',
    pageSize = 'A4',
    margin = '5mm'
  } = options;

  let pageCss = '';
  if (pageSize === 'thermal80mm') {
    pageCss = `
      @page {
        size: 80mm auto;
        margin: ${margin};
      }
      @media print {
        body, .printable-root {
          width: 78mm !important;
          max-width: 78mm !important;
          margin: 0 auto !important;
          padding: 2mm 0 !important;
          font-size: 11px !important;
        }
      }
    `;
  } else if (pageSize === 'A5') {
    pageCss = `
      @page {
        size: A5 ${orientation};
        margin: ${margin};
      }
      @media print {
        html, body {
          width: 100% !important;
          height: auto !important;
          margin: 0 !important;
          padding: 0 !important;
        }
        .printable-root {
          width: 100% !important;
          max-width: 100% !important;
          box-sizing: border-box !important;
          margin: 0 auto !important;
        }
      }
    `;
  } else {
    pageCss = `
      @page {
        size: A4 ${orientation};
        margin: ${margin};
      }
      @media print {
        html, body {
          width: 100% !important;
          height: auto !important;
          margin: 0 !important;
          padding: 0 !important;
        }
        .printable-root {
          width: 100% !important;
          max-width: 100% !important;
          box-sizing: border-box !important;
          margin: 0 auto !important;
        }
      }
    `;
  }

  doc.open();
  doc.write(`
    <!DOCTYPE html>
    <html lang="ar" dir="rtl">
      <head>
        <meta charset="UTF-8">
        <title>${safeTitle}</title>
        <link rel="preconnect" href="https://fonts.googleapis.com">
        <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
        <link href="https://fonts.googleapis.com/css2?family=Cairo:wght@400;500;600;700;800;900&family=IBM+Plex+Sans+Arabic:wght@400;500;600;700;800&display=swap" rel="stylesheet">
        ${styles}
        <style>
          ${pageCss}
          html, body {
            background: #ffffff !important;
            background-color: #ffffff !important;
            color: #000000 !important;
            margin: 0 !important;
            padding: 0 !important;
            direction: rtl !important;
            font-family: 'Cairo', 'IBM Plex Sans Arabic', system-ui, -apple-system, sans-serif !important;
            -webkit-print-color-adjust: exact !important;
            print-color-adjust: exact !important;
            visibility: visible !important;
          }
          *, html, body, div, span, table, th, td, p, h1, h2, h3, h4, h5, h6 {
            font-feature-settings: "lnum" 1, "tnum" 1, "zero" 0 !important;
            font-variant-numeric: lining-nums tabular-nums !important;
          }
          .font-mono {
            font-family: 'Cairo', 'IBM Plex Sans Arabic', 'Segoe UI', Tahoma, system-ui, -apple-system, sans-serif !important;
            font-weight: 700 !important;
            font-variant-numeric: tabular-nums lining-nums !important;
            font-feature-settings: "lnum" 1, "tnum" 1, "zero" 0 !important;
          }
          .no-print, button, nav, header, aside {
            display: none !important;
          }
          .printable-root {
            width: 100% !important;
            margin: 0 auto !important;
            background: #ffffff !important;
            visibility: visible !important;
          }
          .printable-root * {
            visibility: visible !important;
            -webkit-print-color-adjust: exact !important;
            print-color-adjust: exact !important;
          }
          @media print {
            body, .printable-root, .printable-root * {
              visibility: visible !important;
              -webkit-print-color-adjust: exact !important;
              print-color-adjust: exact !important;
            }
            .no-print, button {
              display: none !important;
            }
            .page-break {
              page-break-after: always !important;
              break-after: page !important;
            }
          }
        </style>
      </head>
      <body>
        <div class="printable-root font-sans" dir="rtl">
          ${targetElement.outerHTML}
        </div>
      </body>
    </html>
  `);
  doc.close();

  const triggerPrint = () => {
    try {
      iframe.contentWindow?.focus();
      iframe.contentWindow?.print();
    } catch (e) {
      console.error('Iframe print error:', e);
      window.print();
    } finally {
      setTimeout(() => {
        document.title = originalDocTitle;
        if (document.body.contains(iframe)) {
          document.body.removeChild(iframe);
        }
      }, 1200);
    }
  };

  // Wait for images and fonts to settle inside iframe before opening print preview
  if (doc.fonts && doc.fonts.ready) {
    doc.fonts.ready
      .then(() => setTimeout(triggerPrint, 250))
      .catch(() => setTimeout(triggerPrint, 350));
  } else {
    setTimeout(triggerPrint, 350);
  }
}
