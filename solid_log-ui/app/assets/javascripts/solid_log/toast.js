// Toast Notification System
(function() {
  window.SolidLogToast = {
    show: function(message, type = 'info', duration = 3000) {
      const container = document.getElementById('toast-container');
      if (!container) {
        console.warn('Toast container not found');
        return;
      }

      const toast = document.createElement('div');
      toast.className = `toast toast-${type}`;

      const icons = {
        success: '✓',
        info: 'ℹ',
        warning: '⚠',
        error: '✕'
      };

      toast.innerHTML = `
        <span class="toast-icon">${icons[type] || icons.info}</span>
        <span class="toast-message">${message}</span>
        <button type="button" class="toast-close" aria-label="Close">×</button>
      `;

      const closeBtn = toast.querySelector('.toast-close');
      closeBtn.addEventListener('click', () => {
        this.dismiss(toast);
      });

      container.appendChild(toast);

      if (duration > 0) {
        setTimeout(() => {
          this.dismiss(toast);
        }, duration);
      }

      return toast;
    },

    dismiss: function(toast) {
      toast.classList.add('toast-dismissing');
      setTimeout(() => {
        toast.remove();
      }, 200);
    }
  };
})();
