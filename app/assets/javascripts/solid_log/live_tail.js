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
    // Poll for new entries every 3 seconds
    liveTailInterval = setInterval(function() {
      fetchNewEntries();
    }, 3000);

    // Initial fetch
    fetchNewEntries();
  }

  function stopLiveTail() {
    if (liveTailInterval) {
      clearInterval(liveTailInterval);
      liveTailInterval = null;
    }
  }

  function fetchNewEntries() {
    const logStream = document.querySelector('.log-stream');
    if (!logStream) return;

    // Get timestamp of the newest entry currently displayed
    const entries = logStream.querySelectorAll('.log-row-compact, .log-row');
    if (entries.length === 0) {
      window.location.reload();
      return;
    }

    const lastEntry = entries[entries.length - 1];
    const timeElement = lastEntry.querySelector('[title]');
    if (!timeElement) return;

    const newestTimestamp = timeElement.getAttribute('title');

    // Get current filters from URL
    const url = new URL(window.location.href);
    const params = new URLSearchParams(url.search);

    // Add parameter to get entries after the newest timestamp
    params.set('after', newestTimestamp);
    params.set('limit', '100'); // Get up to 100 new entries

    // Fetch new entries
    fetch(`${url.pathname}?${params.toString()}`, {
      headers: {
        'Accept': 'application/json',
        'X-Requested-With': 'XMLHttpRequest'
      }
    })
    .then(response => response.json())
    .then(data => {
      if (data.entries && data.entries.length > 0) {
        appendEntries(data.entries);
        scrollToBottom();
      }
    })
    .catch(error => {
      console.error('Error fetching new logs:', error);
    });
  }

  function appendEntries(entriesHTML) {
    const logStream = document.querySelector('.log-stream');
    if (!logStream) return;

    const temp = document.createElement('div');
    temp.innerHTML = entriesHTML;

    // Append new entries
    while (temp.firstChild) {
      logStream.appendChild(temp.firstChild);
    }
  }

  function scrollToBottom() {
    if (window.SolidLogStream && window.SolidLogStream.scrollToBottom) {
      window.SolidLogStream.scrollToBottom();
    } else {
      const streamsMain = document.querySelector('.streams-main');
      if (streamsMain) {
        streamsMain.scrollTop = streamsMain.scrollHeight;
      }
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
