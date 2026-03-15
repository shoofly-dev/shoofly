// script.js — shoofly.dev
// Handles copy-to-clipboard and Tally branding removal.

(function () {
  'use strict';

  // --- Copy buttons ---
  document.addEventListener('click', function (e) {
    var btn = e.target.closest('.copy-btn');
    if (!btn) return;

    var command = btn.getAttribute('data-command') || 'npx shoofly init';

    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(command).then(function () {
        showCopied(btn);
      }).catch(function () {
        fallbackCopy(command, btn);
      });
    } else {
      fallbackCopy(command, btn);
    }
  });

  function showCopied(btn) {
    btn.textContent = 'Copied!';
    btn.classList.add('copied');
    btn.disabled = true;

    setTimeout(function () {
      btn.textContent = 'copy';
      btn.classList.remove('copied');
      btn.disabled = false;
    }, 2000);
  }

  function fallbackCopy(text, btn) {
    var textarea = document.createElement('textarea');
    textarea.value = text;
    textarea.style.position = 'fixed';
    textarea.style.left = '-9999px';
    textarea.style.top = '-9999px';
    document.body.appendChild(textarea);
    textarea.focus();
    textarea.select();
    try {
      document.execCommand('copy');
      showCopied(btn);
    } catch (err) {
      // Silent fail — clipboard unavailable
    }
    document.body.removeChild(textarea);
  }

  // --- Tally branding removal ---
  // Try to hide "Made with Tally" via postMessage; CSS overlay is the fallback
  window.addEventListener('message', function (e) {
    if (e.origin !== 'https://tally.so') return;
    try {
      var data = typeof e.data === 'string' ? JSON.parse(e.data) : e.data;
      if (data && data.event === 'Tally.FormLoaded') {
        var iframe = document.querySelector('.waitlist iframe');
        if (iframe) {
          iframe.contentWindow.postMessage(
            JSON.stringify({ event: 'Tally.RemoveBranding' }),
            'https://tally.so'
          );
        }
      }
    } catch (err) {
      // Cross-origin or parse error — CSS overlay handles it
    }
  });
})();
