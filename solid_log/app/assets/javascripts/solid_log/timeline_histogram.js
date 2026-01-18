// Timeline Histogram functionality for log stream filtering
(function() {
  function initializeTimelineHistograms() {
    document.querySelectorAll('[data-controller="timeline-histogram"]').forEach(histogram => {
      const chart = histogram.querySelector('[data-timeline-histogram-target="chart"]');
      const barsContainer = histogram.querySelector('[data-timeline-histogram-target="barsContainer"]');
      const bars = histogram.querySelectorAll('[data-timeline-histogram-target="bar"]');
      const tooltip = histogram.querySelector('[data-timeline-histogram-target="tooltip"]');
      const selection = histogram.querySelector('[data-timeline-histogram-target="selection"]');
      const form = histogram.querySelector('[data-timeline-histogram-target="form"]');
      const startTimeField = histogram.querySelector('[data-timeline-histogram-target="startTimeField"]');
      const endTimeField = histogram.querySelector('[data-timeline-histogram-target="endTimeField"]');

      if (!chart || !bars.length) return;

      let selectionStart = null;
      let selectionEnd = null;
      let isDragging = false;

      // Show tooltip on hover
      bars.forEach(bar => {
        bar.addEventListener('mouseenter', function() {
          const count = this.dataset.count;
          const startTime = new Date(this.dataset.startTime);
          const endTime = new Date(this.dataset.endTime);

          tooltip.innerHTML = `
            <div class="tooltip-time">${formatTime(startTime)} - ${formatTime(endTime)}</div>
            <div class="tooltip-count">${count} log${count == 1 ? '' : 's'}</div>
          `;

          const rect = this.getBoundingClientRect();
          const chartRect = chart.getBoundingClientRect();

          tooltip.style.display = 'block';
          tooltip.style.left = (rect.left - chartRect.left + rect.width / 2) + 'px';
          tooltip.style.top = (rect.top - chartRect.top - 10) + 'px';
        });

        bar.addEventListener('mouseleave', function() {
          if (!isDragging) {
            tooltip.style.display = 'none';
          }
        });

        // Start selection on mousedown
        bar.addEventListener('mousedown', function(e) {
          e.preventDefault();
          isDragging = true;
          const index = parseInt(this.dataset.index);
          selectionStart = index;
          selectionEnd = index;
          updateSelection();
        });
      });

      // Handle dragging
      document.addEventListener('mousemove', function(e) {
        if (!isDragging) return;

        const chartRect = barsContainer.getBoundingClientRect();
        const x = e.clientX - chartRect.left;

        // Find the bar at this x position
        bars.forEach(bar => {
          const rect = bar.getBoundingClientRect();
          const barX = rect.left - chartRect.left;

          if (x >= barX && x <= barX + rect.width) {
            const index = parseInt(bar.dataset.index);
            if (index !== selectionEnd) {
              selectionEnd = index;
              updateSelection();
            }
          }
        });
      });

      // End selection on mouseup
      document.addEventListener('mouseup', function() {
        if (isDragging) {
          isDragging = false;
          applySelection();
        }
      });

      function updateSelection() {
        if (selectionStart === null || selectionEnd === null) {
          selection.style.display = 'none';
          return;
        }

        const start = Math.min(selectionStart, selectionEnd);
        const end = Math.max(selectionStart, selectionEnd);

        const startBar = bars[start];
        const endBar = bars[end];

        const startRect = startBar.getBoundingClientRect();
        const endRect = endBar.getBoundingClientRect();
        const chartRect = barsContainer.getBoundingClientRect();

        const left = startRect.left - chartRect.left;
        const width = (endRect.left + endRect.width) - startRect.left;

        selection.style.display = 'block';
        selection.style.left = left + 'px';
        selection.style.width = width + 'px';

        // Highlight selected bars
        bars.forEach((bar, index) => {
          if (index >= start && index <= end) {
            bar.classList.add('selected');
          } else {
            bar.classList.remove('selected');
          }
        });
      }

      function applySelection() {
        if (selectionStart === null || selectionEnd === null) return;

        const start = Math.min(selectionStart, selectionEnd);
        const end = Math.max(selectionStart, selectionEnd);

        const startTime = bars[start].dataset.startTime;
        const endTime = bars[end].dataset.endTime;

        startTimeField.value = startTime;
        endTimeField.value = endTime;

        form.requestSubmit();
      }

      function formatTime(date) {
        const hours = String(date.getHours()).padStart(2, '0');
        const minutes = String(date.getMinutes()).padStart(2, '0');
        return `${hours}:${minutes}`;
      }

      // Clear selection button
      const clearButton = histogram.querySelector('[data-action*="clearSelection"]');
      if (clearButton) {
        clearButton.addEventListener('click', function() {
          startTimeField.value = '';
          endTimeField.value = '';
          form.requestSubmit();
        });
      }
    });
  }

  // Initialize on page load
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', initializeTimelineHistograms);
  } else {
    initializeTimelineHistograms();
  }

  // Re-initialize on Turbo load (if using Turbo)
  document.addEventListener('turbo:load', initializeTimelineHistograms);
})();
