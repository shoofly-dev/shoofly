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

  // --- Open in Terminal button ---
  document.addEventListener('click', function (e) {
    var btn = e.target.closest('.open-in-terminal-btn');
    if (!btn) return;

    var command = btn.getAttribute('data-command') || 'npx shoofly init';

    // Copy command to clipboard
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(command).catch(function () {
        fallbackCopy(command, btn);
      });
    } else {
      fallbackCopy(command, btn);
    }

    // Best-effort terminal URI schemes
    try {
      var encoded = encodeURIComponent(command);
      window.open('terminal://run/?cmd=' + encoded, '_self');
    } catch (err) { /* ignore */ }
    try {
      var encoded2 = encodeURIComponent(command);
      window.open('x-terminal-emulator:?cmd=' + encoded2, '_self');
    } catch (err) { /* ignore */ }

    // Show tooltip
    var existing = btn.querySelector('.terminal-tooltip');
    if (existing) existing.remove();

    var tooltip = document.createElement('span');
    tooltip.className = 'terminal-tooltip';
    tooltip.textContent = 'Command copied — paste it in your terminal';
    btn.appendChild(tooltip);

    // Trigger reflow then show
    tooltip.offsetHeight;
    tooltip.classList.add('visible');

    setTimeout(function () {
      tooltip.classList.remove('visible');
      setTimeout(function () { tooltip.remove(); }, 200);
    }, 3000);
  });

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

  // --- Hamburger nav toggle ---
  var hamburger = document.getElementById('navHamburger');
  var navLinks = document.querySelector('.nav-links');
  if (hamburger && navLinks) {
    hamburger.addEventListener('click', function () {
      navLinks.classList.toggle('nav-open');
    });
    // Close menu when a nav link is clicked
    navLinks.addEventListener('click', function (e) {
      if (e.target.tagName === 'A') {
        navLinks.classList.remove('nav-open');
      }
    });
  }
})();

  // --- Purchase confirmation banner (?purchased=1) ---
  (function () {
    var params = new URLSearchParams(window.location.search);
    if (!params.get('purchased')) return;

    var banner = document.createElement('div');
    banner.id = 'purchase-banner';
    banner.innerHTML = [
      '<span style="font-size:1.1rem;">✅</span>',
      '<span>Purchase confirmed — check your email for your personal install command.</span>',
      '<button id="purchase-banner-close" aria-label="Dismiss">✕</button>'
    ].join('');
    banner.style.cssText = [
      'position:fixed',
      'top:0',
      'left:0',
      'right:0',
      'z-index:9999',
      'display:flex',
      'align-items:center',
      'justify-content:center',
      'gap:10px',
      'padding:14px 20px',
      'background:#052e16',
      'border-bottom:1px solid #166534',
      'color:#86efac',
      'font-family:inherit',
      'font-size:0.95rem',
      'line-height:1.4',
      'text-align:center'
    ].join(';');

    document.body.prepend(banner);

    // Push body content down so banner doesn't overlap nav
    document.body.style.paddingTop = (banner.offsetHeight + 'px');

    // Scroll to pricing section
    var pricing = document.getElementById('pricing');
    if (pricing) {
      setTimeout(function () {
        pricing.scrollIntoView({ behavior: 'smooth', block: 'start' });
      }, 300);
    }

    // Dismiss button
    document.getElementById('purchase-banner-close').addEventListener('click', function () {
      banner.remove();
      document.body.style.paddingTop = '';
      // Clean URL without reload
      var url = new URL(window.location.href);
      url.searchParams.delete('purchased');
      window.history.replaceState({}, '', url.toString());
    });
  })();
