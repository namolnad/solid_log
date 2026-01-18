// Live Tail functionality for SolidLog streams
// Supports both WebSocket (ActionCable) and HTTP polling modes
(function() {
  let liveTailActive = false;
  let pollingInterval = null;
  let cableSubscription = null;
  let lastEntryId = null;
  let mode = null;
  let isInitialFetch = true; // Skip highlighting on first fetch after starting live tail

  function initializeLiveTail() {
    const toggleButton = document.getElementById('live-tail-toggle');
    if (!toggleButton) return;

    mode = toggleButton.dataset.liveTailMode;
    if (!mode || mode === 'disabled') return;

    // Check if already initialized to prevent duplicate listeners
    if (toggleButton.dataset.liveTailInitialized === 'true') {
      // Still need to set up scroll listener even if already initialized
      // because .log-stream element might have been replaced
      setupScrollListener();
      return;
    }

    toggleButton.addEventListener('click', function(e) {
      e.preventDefault();
      toggleLiveTail();
    });

    // Mark as initialized
    toggleButton.dataset.liveTailInitialized = 'true';

    // Set up jump-to-live button
    initializeJumpToLive();

    // Set up scroll listener
    setupScrollListener();

    // Store last entry ID for tracking
    updateLastEntryId();
  }

  function setupScrollListener() {
    const logStream = document.querySelector('.log-stream');
    if (logStream) {
      // Remove existing listener if any to prevent duplicates
      logStream.removeEventListener('scroll', checkScrollPosition);
      logStream.addEventListener('scroll', checkScrollPosition, { passive: true });
    }
  }

  function toggleLiveTail() {
    liveTailActive = !liveTailActive;
    const button = document.getElementById('live-tail-toggle');
    const indicator = document.getElementById('live-tail-indicator');

    if (liveTailActive) {
      startLiveTail();
      button.textContent = '⏸ Pause';
      button.classList.add('btn-primary');
      button.classList.remove('btn-secondary');

      // Show indicator
      if (indicator) {
        indicator.style.display = 'inline-flex';
      }

      // Show toast notification
      if (window.SolidLogToast) {
        window.SolidLogToast.show(`Live tail ${mode === 'websocket' ? 'streaming' : 'polling'} started`, 'info');
      }
    } else {
      stopLiveTail();
      button.textContent = '▶ Live Tail';
      button.classList.remove('btn-primary');
      button.classList.add('btn-secondary');

      // Hide indicator
      if (indicator) {
        indicator.style.display = 'none';
      }

      if (window.SolidLogToast) {
        window.SolidLogToast.show('Live tail stopped', 'info');
      }
    }
  }

  function startLiveTail() {
    // Reset flag - next fetch will be the initial one
    isInitialFetch = true;

    // Clear any time filters from URL (start_time, end_time, before_id, after_id)
    clearTimeFilters();

    console.log('startLiveTail - mode:', mode, 'createConsumer available:', typeof createConsumer !== 'undefined');

    if (mode === 'websocket' && typeof createConsumer !== 'undefined') {
      console.log('Starting WebSocket tail');
      startWebSocketTail();
    } else {
      console.log('Starting polling tail (fallback or polling mode)');
      // Fallback to polling if websocket unavailable or mode is 'polling'
      startPollingTail();
    }

    // Don't auto-scroll - let user maintain their position
    // Show jump-to-live button if new entries arrive while scrolled up
  }

  function stopLiveTail() {
    if (cableSubscription) {
      cableSubscription.unsubscribe();
      cableSubscription = null;
    }

    if (pollingInterval) {
      clearInterval(pollingInterval);
      pollingInterval = null;
    }
  }

  function startWebSocketTail() {
    // Get current filter params
    const filters = getCurrentFilters();

    // Create ActionCable subscription
    const consumer = createConsumer();
    cableSubscription = consumer.subscriptions.create(
      {
        channel: "SolidLog::UI::LogStreamChannel",
        filters: filters
      },
      {
        connected() {
          console.log('Connected to log stream');

          // Send heartbeat every 2 minutes to keep cache entry alive
          this.heartbeatInterval = setInterval(() => {
            this.perform('refresh_subscription');
          }, 2 * 60 * 1000);
        },

        disconnected() {
          console.log('Disconnected from log stream');

          // Clear heartbeat interval
          if (this.heartbeatInterval) {
            clearInterval(this.heartbeatInterval);
            this.heartbeatInterval = null;
          }

          // Reset button state to show stream has stopped
          resetLiveTailButton();

          // If still active, fallback to polling
          if (liveTailActive) {
            console.log('Falling back to polling mode');
            if (window.SolidLogToast) {
              window.SolidLogToast.show('Connection lost, switching to polling mode', 'warning');
            }
            startPollingTail();
          }
        },

        received(data) {
          // Received new log entry via websocket (already filtered server-side)
          console.log('[LiveTail] WebSocket received data:', data, 'isInitialFetch:', isInitialFetch, 'has html:', !!data.html);
          if (data.html) {
            console.log('[LiveTail] Appending entry with ID:', data.entry_id);
            appendEntry(data.html);
            updateLastEntryId();

            // Only highlight if this is NOT the initial message
            if (!isInitialFetch) {
              console.log('[LiveTail] Not initial message - highlighting button');
              highlightJumpToLive();
              // Update timeline to show new data has arrived
              updateTimeline();
            } else {
              console.log('[LiveTail] Initial message - skipping highlight');
            }

            // Mark that we've received the initial message
            isInitialFetch = false;
          } else {
            console.log('[LiveTail] No HTML in data, ignoring');
          }
        }
      }
    );
  }

  function startPollingTail() {
    // Poll every 2 seconds
    pollingInterval = setInterval(function() {
      fetchNewEntries();
    }, 2000);

    // Initial fetch
    fetchNewEntries();
  }

  function fetchNewEntries() {
    const streamsPath = document.body.dataset.streamsPath || '/streams';
    const url = new URL(window.location.origin + streamsPath);

    // Copy current filters
    const currentParams = new URLSearchParams(window.location.search);
    currentParams.forEach((value, key) => {
      url.searchParams.append(key, value);
    });

    // Add after_id parameter if we have a last entry
    if (lastEntryId) {
      url.searchParams.set('after_id', lastEntryId);
    }

    // Request turbo stream format
    fetch(url.toString(), {
      headers: {
        'Accept': 'text/vnd.turbo-stream.html',
        'X-Requested-With': 'XMLHttpRequest'
      }
    })
    .then(response => {
      if (!response.ok) throw new Error('Network response was not ok');
      return response.text();
    })
    .then(html => {
      console.log('Polling received HTML, length:', html ? html.length : 0, 'isInitialFetch:', isInitialFetch);
      if (html && html.trim()) {
        // Turbo will automatically process the stream response
        Turbo.renderStreamMessage(html);
        updateLastEntryId();

        // Only highlight if this is NOT the initial fetch
        if (!isInitialFetch) {
          console.log('Not initial fetch - highlighting button');
          highlightJumpToLive();
          // Update timeline to show new data has arrived
          updateTimeline();
        } else {
          console.log('Initial fetch - skipping highlight');
        }

        // Mark that we've completed the initial fetch
        isInitialFetch = false;
      }
    })
    .catch(error => {
      console.error('Error fetching new logs:', error);
    });
  }

  function appendEntry(html) {
    const logStream = document.getElementById('log-stream-content');
    if (!logStream) return;

    const temp = document.createElement('div');
    temp.innerHTML = html;

    // Append new entries
    while (temp.firstChild) {
      logStream.appendChild(temp.firstChild);
    }
  }

  function updateLastEntryId() {
    const logStream = document.getElementById('log-stream-content');
    if (!logStream) return;

    const entries = logStream.querySelectorAll('[data-entry-id]');
    if (entries.length > 0) {
      const lastEntry = entries[entries.length - 1];
      lastEntryId = lastEntry.dataset.entryId;
    }
  }

  function clearTimeFilters() {
    // Remove time-based filters from URL when starting live tail
    const url = new URL(window.location.href);
    const params = url.searchParams;

    // Remove time filters
    params.delete('filters[start_time]');
    params.delete('filters[end_time]');
    params.delete('before_id');
    params.delete('after_id');

    // Update URL without reloading the page
    window.history.replaceState({}, '', url);

    // Clear the timeline selection visually if it exists
    const timelineController = document.querySelector('[data-controller="timeline-histogram"]');
    if (timelineController && window.Stimulus) {
      const controller = window.Stimulus.getControllerForElementAndIdentifier(timelineController, 'timeline-histogram');
      if (controller && controller.clearSelection) {
        controller.clearSelection();
      }
    }
  }

  function updateTimeline() {
    // Fetch updated timeline data when new entries arrive during live tail
    const url = new URL(window.location.href);
    url.searchParams.set('timeline_only', '1');

    fetch(url, {
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
      console.error('Error updating timeline:', error);
    });
  }

  function getCurrentFilters() {
    const filters = {};
    const params = new URLSearchParams(window.location.search);

    params.forEach((value, key) => {
      if (key.startsWith('filters[')) {
        const filterKey = key.match(/filters\[(.*?)\]/)[1];
        // Skip time filters - they should be cleared for live tail
        if (filterKey === 'start_time' || filterKey === 'end_time') {
          return;
        }
        if (!filters[filterKey]) {
          filters[filterKey] = [];
        }
        filters[filterKey].push(value);
      }
    });

    return filters;
  }

  function resetLiveTailButton() {
    const button = document.getElementById('live-tail-toggle');
    const indicator = document.getElementById('live-tail-indicator');

    if (button) {
      button.textContent = '▶ Live Tail';
      button.classList.remove('btn-primary');
      button.classList.add('btn-secondary');
      liveTailActive = false;
    }

    if (indicator) {
      indicator.style.display = 'none';
    }
  }

  function scrollToBottom() {
    setTimeout(() => {
      if (window.SolidLogStream && window.SolidLogStream.scrollToBottom) {
        window.SolidLogStream.scrollToBottom();
      } else {
        const logStream = document.querySelector('.log-stream');
        if (logStream) {
          logStream.scrollTop = logStream.scrollHeight;
        }
      }
    }, 50);
  }

  function initializeJumpToLive() {
    const jumpButton = document.getElementById('jump-to-live');
    if (!jumpButton) return;

    // Check if already initialized
    if (jumpButton.dataset.jumpInitialized === 'true') {
      return;
    }

    jumpButton.addEventListener('click', function(e) {
      e.preventDefault();
      scrollToBottom();
      clearJumpToLiveHighlight();
    });

    jumpButton.dataset.jumpInitialized = 'true';
  }

  function highlightJumpToLive() {
    const jumpButton = document.getElementById('jump-to-live');
    if (!jumpButton) return;

    console.log('highlightJumpToLive() called');

    // Clear countdown timer if button is disabled
    if (window.SolidLogJumpToLive && window.SolidLogJumpToLive.clearCountdown) {
      window.SolidLogJumpToLive.clearCountdown();
    }

    // Always highlight when new entries arrive
    console.log('Adding has-new-entries class to button');
    jumpButton.classList.add('has-new-entries');
    console.log('Button classes now:', jumpButton.className);
  }

  function clearJumpToLiveHighlight() {
    const jumpButton = document.getElementById('jump-to-live');
    if (jumpButton) {
      jumpButton.classList.remove('has-new-entries');
    }
  }

  function checkScrollPosition() {
    // Clear highlight when user scrolls to bottom
    const atBottom = isAtBottom();
    console.log('[LiveTail] checkScrollPosition - atBottom:', atBottom);
    if (atBottom) {
      console.log('[LiveTail] Clearing jump-to-live highlight (user scrolled to bottom)');
      clearJumpToLiveHighlight();
    }
  }

  function isAtBottom() {
    const logStream = document.querySelector('.log-stream');
    if (!logStream) return true;

    // Consider "at bottom" if within 10px of the bottom
    const scrollDistance = logStream.scrollHeight - logStream.scrollTop - logStream.clientHeight;
    console.log('[LiveTail] isAtBottom check - scrollHeight:', logStream.scrollHeight,
                'scrollTop:', logStream.scrollTop, 'clientHeight:', logStream.clientHeight,
                'scrollDistance:', scrollDistance);
    return scrollDistance < 10;
  }

  // Initialize on page load
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', initializeLiveTail);
  } else {
    initializeLiveTail();
  }

  // Re-initialize on turbo navigation
  document.addEventListener('turbo:load', function() {
    // Reset state on new page
    liveTailActive = false;
    lastEntryId = null;

    initializeLiveTail();
  });

  // Stop live tail when navigating away or changing filters
  document.addEventListener('turbo:before-visit', function() {
    if (liveTailActive) {
      stopLiveTail();
      liveTailActive = false;
      console.log('Stopped live tail due to navigation');
    }
  });

  // Stop live tail when filter form is submitted
  document.addEventListener('submit', function(e) {
    if (e.target.closest('.filter-form') && liveTailActive) {
      stopLiveTail();
      console.log('Stopped live tail due to filter change');
    }
  });

  // Clean up on page unload
  window.addEventListener('beforeunload', stopLiveTail);
})();
