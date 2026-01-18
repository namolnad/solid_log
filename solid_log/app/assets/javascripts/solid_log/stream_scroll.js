// Stream scroll behavior: newest at bottom, infinite scroll up, auto-scroll
(function() {
  let isScrollingProgrammatically = false;
  let oldestEntryId = null;
  let isLoadingMore = false;
  let hasMoreEntries = true;
  let hasInitialized = false;

  function initializeStreamScroll() {
    const logStreamContent = document.getElementById('log-stream-content');
    if (!logStreamContent) return;

    // Get the oldest entry ID for pagination (first entry in the list)
    updateOldestEntryId();

    // Auto-scroll to bottom ONLY on initial page load (not on Turbo updates)
    // Check if live tail is active - don't auto-scroll if it is
    const liveTailButton = document.getElementById('live-tail-toggle');
    const liveTailActive = liveTailButton && liveTailButton.textContent.includes('Pause');

    if (!hasInitialized && !liveTailActive) {
      // Use requestAnimationFrame to ensure DOM is fully rendered and laid out
      requestAnimationFrame(() => {
        requestAnimationFrame(() => {
          scrollToBottom();
        });
      });
      hasInitialized = true;
    }

    // Infinite scroll: load more when scrolling up
    const logStream = document.querySelector('.log-stream');
    if (logStream) {
      console.log('Attaching scroll listener to .log-stream');
      logStream.addEventListener('scroll', function() {
        console.log('Scroll event - scrollTop:', this.scrollTop, 'isScrollingProgrammatically:', isScrollingProgrammatically, 'isLoadingMore:', isLoadingMore);

        if (isScrollingProgrammatically || isLoadingMore) return;

        // Check if scrolled to top (or near top)
        if (this.scrollTop < 100) {
          console.log('Near top, triggering loadMoreLogs');
          loadMoreLogs();
        }
      });
    } else {
      console.log('WARNING: .log-stream not found!');
    }
  }

  function updateOldestEntryId() {
    const logStreamContent = document.getElementById('log-stream-content');
    if (!logStreamContent) {
      console.log('updateOldestEntryId: log-stream-content not found');
      return;
    }

    const entries = logStreamContent.querySelectorAll('.log-row-compact-wrapper, .log-row');
    console.log('updateOldestEntryId: found', entries.length, 'entries');

    if (entries.length > 0) {
      // Get the FIRST entry (oldest, since DOM is in ASC order after reversing)
      const firstEntry = entries[0];
      const newOldestId = firstEntry.dataset.entryId;
      console.log('updateOldestEntryId: newOldestId =', newOldestId, ', oldestEntryId =', oldestEntryId);

      // If the oldest ID hasn't changed after a fetch, we've reached the end
      if (oldestEntryId !== null && newOldestId === oldestEntryId) {
        console.log('updateOldestEntryId: reached the end (ID unchanged)');
        hasMoreEntries = false;
      } else {
        console.log('updateOldestEntryId: updating to', newOldestId);
        oldestEntryId = newOldestId;
        hasMoreEntries = true;
      }
    }
  }

  function scrollToBottom() {
    isScrollingProgrammatically = true;
    const logStream = document.querySelector('.log-stream');
    if (logStream) {
      // Scroll to bottom
      logStream.scrollTop = logStream.scrollHeight;
    }
    setTimeout(() => {
      isScrollingProgrammatically = false;
    }, 100);
  }

  function loadMoreLogs() {
    console.log('loadMoreLogs called - isLoadingMore:', isLoadingMore, 'oldestEntryId:', oldestEntryId, 'hasMoreEntries:', hasMoreEntries);

    if (isLoadingMore || !oldestEntryId || !hasMoreEntries) {
      console.log('Cannot load more - bailing out');
      return;
    }

    console.log('Loading more logs before ID:', oldestEntryId);
    isLoadingMore = true;

    // Store scroll position before loading
    const logStream = document.querySelector('.log-stream');
    const scrollHeightBefore = logStream.scrollHeight;
    const scrollTopBefore = logStream.scrollTop;

    // Get current filters from the URL
    const url = new URL(window.location.href);
    const params = new URLSearchParams(url.search);

    // Add pagination parameter (load logs before the oldest ID)
    params.set('before_id', oldestEntryId);
    params.set('limit', '50'); // Load 50 more entries

    // Show loading indicator
    showLoadingIndicator();

    // Fetch more logs via Turbo Stream
    fetch(`${url.pathname}?${params.toString()}`, {
      headers: {
        'Accept': 'text/vnd.turbo-stream.html',
        'X-Requested-With': 'XMLHttpRequest'
      }
    })
    .then(response => {
      console.log('Fetch response status:', response.status, 'ok:', response.ok);
      if (response.ok) {
        return response.text();
      }
      throw new Error('No more logs');
    })
    .then(html => {
      console.log('Received HTML, length:', html.length);
      // Turbo will handle prepending via turbo_stream.prepend
      // We just need to update the oldest entry ID and restore scroll position
      if (window.Turbo) {
        console.log('Rendering Turbo stream');
        window.Turbo.renderStreamMessage(html);
      }

      // Update oldest entry ID after Turbo renders
      setTimeout(() => {
        console.log('Updating oldest entry ID after render');
        updateOldestEntryId();

        // Maintain scroll position (so the view doesn't jump)
        const scrollHeightAfter = logStream.scrollHeight;
        const scrollDifference = scrollHeightAfter - scrollHeightBefore;
        console.log('Scroll adjustment - before:', scrollHeightBefore, 'after:', scrollHeightAfter, 'diff:', scrollDifference);
        logStream.scrollTop = scrollTopBefore + scrollDifference;

        hideLoadingIndicator();
        isLoadingMore = false;
        console.log('Load complete');
      }, 50);
    })
    .catch(error => {
      console.log('Fetch error:', error.message);
      hideLoadingIndicator();
      isLoadingMore = false;
      hasMoreEntries = false;
    });
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

  // For Turbo apps, turbo:load handles both initial load and navigations
  document.addEventListener('turbo:load', initializeStreamScroll);

  // Reset initialization flag on actual navigation
  document.addEventListener('turbo:before-visit', function() {
    hasInitialized = false;
  });

  // Export for live tail usage
  window.SolidLogStream = {
    scrollToBottom: scrollToBottom,
    updateOldestEntryId: updateOldestEntryId
  };
})();
