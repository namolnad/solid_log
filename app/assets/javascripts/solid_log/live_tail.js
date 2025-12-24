// Live Tail functionality for SolidLog streams
(function() {
  let liveTailInterval = null;
  let isLiveTailActive = false;

  function initializeLiveTail() {
    const toggleButton = document.getElementById('live-tail-toggle');
    if (!toggleButton) return;

    toggleButton.addEventListener('click', function(e) {
      e.preventDefault();
      toggleLiveTail();
    });
  }

  function toggleLiveTail() {
    isLiveTailActive = !isLiveTailActive;
    const button = document.getElementById('live-tail-toggle');

    if (isLiveTailActive) {
      startLiveTail();
      button.textContent = '⏸ Pause Live Tail';
      button.classList.add('active');
    } else {
      stopLiveTail();
      button.textContent = '▶ Live Tail';
      button.classList.remove('active');
    }
  }

  function startLiveTail() {
    // Reload every 5 seconds
    liveTailInterval = setInterval(function() {
      window.location.reload();
    }, 5000);
  }

  function stopLiveTail() {
    if (liveTailInterval) {
      clearInterval(liveTailInterval);
      liveTailInterval = null;
    }
  }

  // Auto-scroll to bottom when live tail is active
  function scrollToBottom() {
    if (isLiveTailActive) {
      window.scrollTo({
        top: document.body.scrollHeight,
        behavior: 'smooth'
      });
    }
  }

  // Initialize on page load
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', initializeLiveTail);
  } else {
    initializeLiveTail();
  }

  // Clean up on page unload
  window.addEventListener('beforeunload', stopLiveTail);
})();
