// Stream scroll behavior: newest at bottom, infinite scroll up, auto-scroll
(function() {
  let isScrollingProgrammatically = false;
  let oldestEntryTimestamp = null;
  let isLoadingMore = false;

  function initializeStreamScroll() {
    const logStream = document.querySelector('.log-stream');
    if (!logStream) return;

    // Get the oldest entry timestamp for pagination
    const entries = logStream.querySelectorAll('.log-row-compact, .log-row');
    if (entries.length > 0) {
      const firstEntry = entries[0];
      const timeElement = firstEntry.querySelector('[title]');
      if (timeElement) {
        oldestEntryTimestamp = timeElement.getAttribute('title');
      }
    }

    // Auto-scroll to bottom on initial load (to show newest logs)
    // Use requestAnimationFrame to ensure DOM is fully rendered and laid out
    requestAnimationFrame(() => {
      requestAnimationFrame(() => {
        scrollToBottom(logStream);
      });
    });

    // Infinite scroll: load more when scrolling up
    const streamsMain = document.querySelector('.streams-main');
    if (streamsMain) {
      streamsMain.addEventListener('scroll', function() {
        if (isScrollingProgrammatically || isLoadingMore) return;

        // Check if scrolled to top (or near top)
        if (this.scrollTop < 100) {
          loadMoreLogs();
        }
      });
    }
  }

  function scrollToBottom(container) {
    isScrollingProgrammatically = true;
    const parent = container.closest('.streams-main');
    if (parent) {
      // Try multiple approaches to ensure scroll works
      parent.scrollTop = parent.scrollHeight;
      // Also try scrolling the last element into view
      const lastElement = container.lastElementChild;
      if (lastElement) {
        lastElement.scrollIntoView({ behavior: 'instant', block: 'end' });
      }
    }
    setTimeout(() => {
      isScrollingProgrammatically = false;
    }, 100);
  }

  function loadMoreLogs() {
    if (isLoadingMore || !oldestEntryTimestamp) return;

    isLoadingMore = true;

    // Get current filters from the URL
    const url = new URL(window.location.href);
    const params = new URLSearchParams(url.search);

    // Add pagination parameter (load logs before the oldest timestamp)
    params.set('before', oldestEntryTimestamp);
    params.set('limit', '50'); // Load 50 more entries

    // Show loading indicator
    showLoadingIndicator();

    // Fetch more logs
    fetch(`${url.pathname}?${params.toString()}`, {
      headers: {
        'Accept': 'application/json',
        'X-Requested-With': 'XMLHttpRequest'
      }
    })
    .then(response => response.json())
    .then(data => {
      if (data.entries && data.entries.length > 0) {
        prependEntries(data.entries);
        oldestEntryTimestamp = data.oldest_timestamp;
      }
      hideLoadingIndicator();
      isLoadingMore = false;
    })
    .catch(error => {
      console.error('Error loading more logs:', error);
      hideLoadingIndicator();
      isLoadingMore = false;
    });
  }

  function prependEntries(entries) {
    const logStream = document.querySelector('.log-stream');
    if (!logStream) return;

    const streamsMain = document.querySelector('.streams-main');
    const scrollHeightBefore = streamsMain.scrollHeight;
    const scrollTopBefore = streamsMain.scrollTop;

    // Create temporary container for new entries
    const temp = document.createElement('div');
    temp.innerHTML = entries;

    // Prepend new entries
    while (temp.firstChild) {
      logStream.insertBefore(temp.firstChild, logStream.firstChild);
    }

    // Maintain scroll position (so the view doesn't jump)
    const scrollHeightAfter = streamsMain.scrollHeight;
    const scrollDifference = scrollHeightAfter - scrollHeightBefore;
    streamsMain.scrollTop = scrollTopBefore + scrollDifference;
  }

  function showLoadingIndicator() {
    const logStream = document.querySelector('.log-stream');
    if (!logStream) return;

    const indicator = document.createElement('div');
    indicator.className = 'loading-indicator';
    indicator.textContent = 'Loading more logs...';
    logStream.insertBefore(indicator, logStream.firstChild);
  }

  function hideLoadingIndicator() {
    const indicator = document.querySelector('.loading-indicator');
    if (indicator) {
      indicator.remove();
    }
  }

  // Initialize on page load
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', initializeStreamScroll);
  } else {
    initializeStreamScroll();
  }

  // Re-initialize on Turbo load (if using Turbo)
  document.addEventListener('turbo:load', initializeStreamScroll);

  // Export for live tail usage
  window.SolidLogStream = {
    scrollToBottom: function() {
      const logStream = document.querySelector('.log-stream');
      if (logStream) {
        scrollToBottom(logStream);
      }
    }
  };
})();
