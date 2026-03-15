// script.js — shoofly.dev
// Handles copy-to-clipboard for the terminal install command.

(function () {
  'use strict';

  var copyBtn = document.getElementById('copyBtn');
  if (!copyBtn) return;

  copyBtn.addEventListener('click', function () {
    var command = copyBtn.getAttribute('data-command') || 'npx shoofly init';

    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(command).then(function () {
        showCopied();
      }).catch(function () {
        fallbackCopy(command);
      });
    } else {
      fallbackCopy(command);
    }
  });

  function showCopied() {
    copyBtn.textContent = 'Copied!';
    copyBtn.classList.add('copied');
    copyBtn.disabled = true;

    setTimeout(function () {
      copyBtn.textContent = 'copy';
      copyBtn.classList.remove('copied');
      copyBtn.disabled = false;
    }, 2000);
  }

  function fallbackCopy(text) {
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
      showCopied();
    } catch (err) {
      // Silent fail — clipboard unavailable
    }
    document.body.removeChild(textarea);
  }
})();
