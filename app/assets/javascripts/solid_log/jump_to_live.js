// Jump to Live button functionality
(function() {
  let isSetup = false;

  function handleJumpToLive(event) {
    const button = event.currentTarget;

    // Disable button for 5 seconds
    button.disabled = true;
    const originalText = button.textContent;
    let countdown = 5;

    const countdownInterval = setInterval(() => {
      countdown--;
      button.textContent = `↓ Jump to Live (${countdown}s)`;
      if (countdown <= 0) {
        clearInterval(countdownInterval);
        button.disabled = false;
        button.textContent = originalText;
      }
    }, 1000);

    // Get current URL and filters
    const url = new URL(window.location.href);

    // Fetch with turbo_stream format
    fetch(url.pathname + url.search, {
      headers: {
        'Accept': 'text/vnd.turbo-stream.html',
        'X-Requested-With': 'XMLHttpRequest'
      }
    })
    .then(response => response.text())
    .then(html => {
      if (html && html.trim()) {
        Turbo.renderStreamMessage(html);
      }
    })
    .catch(error => {
      console.error('Error jumping to live:', error);
      // Re-enable button immediately on error
      clearInterval(countdownInterval);
      button.disabled = false;
      button.textContent = originalText;
    });
  }

  function setupJumpToLive() {
    if (isSetup) return; // Prevent multiple setups

    const jumpButton = document.getElementById('jump-to-live');

    if (jumpButton) {
      // Remove any existing listener first
      jumpButton.removeEventListener('click', handleJumpToLive);
      // Add the listener
      jumpButton.addEventListener('click', handleJumpToLive);
      isSetup = true;
    }
  }

  // Setup on load
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', setupJumpToLive);
  } else {
    setupJumpToLive();
  }

  // Re-setup on turbo navigation
  document.addEventListener('turbo:load', () => {
    isSetup = false; // Reset flag for new page
    setupJumpToLive();
  });

  // Scroll to bottom after Turbo Stream renders
  document.addEventListener('turbo:before-stream-render', function(event) {
    // In Turbo 8, check event.target for the stream element
    const streamElement = event.target;

    if (streamElement && streamElement.tagName === 'TURBO-STREAM') {
      const target = streamElement.getAttribute('target');
      const action = streamElement.getAttribute('action');

      // If we're updating log-stream-content, scroll after render
      if (target === 'log-stream-content' && (action === 'replace' || action === 'append')) {
        // Wait for DOM to fully update, then scroll
        requestAnimationFrame(() => {
          requestAnimationFrame(() => {
            if (window.SolidLogStream && window.SolidLogStream.scrollToBottom) {
              window.SolidLogStream.scrollToBottom();
            }
          });
        });
      }
    }
  });
})();
