// Checkbox Dropdown functionality for multi-select filters
(function() {
  function closeDropdown(dropdown) {
    const toggle = dropdown.querySelector('[data-action*="toggle"]');
    const menu = dropdown.querySelector('[data-checkbox-dropdown-target="menu"]');
    if (toggle && menu) {
      toggle.setAttribute('aria-expanded', 'false');
      menu.style.display = 'none';
    }
  }

  function initializeCheckboxDropdowns() {
    document.querySelectorAll('[data-controller="checkbox-dropdown"]').forEach(dropdown => {
      const toggle = dropdown.querySelector('[data-action*="toggle"]');
      const menu = dropdown.querySelector('[data-checkbox-dropdown-target="menu"]');
      const search = dropdown.querySelector('[data-checkbox-dropdown-target="search"]');
      const options = dropdown.querySelectorAll('[data-checkbox-dropdown-target="option"]');
      const checkboxes = dropdown.querySelectorAll('input[type="checkbox"]');
      const badge = dropdown.querySelector('.badge-small');
      const closeBtn = dropdown.querySelector('.popover-close');

      if (!toggle || !menu) return;

      // Toggle dropdown
      toggle.addEventListener('click', function(e) {
        e.preventDefault();
        e.stopPropagation();
        const isExpanded = toggle.getAttribute('aria-expanded') === 'true';

        // Close all other dropdowns
        document.querySelectorAll('[data-controller="checkbox-dropdown"]').forEach(other => {
          if (other !== dropdown) {
            closeDropdown(other);
          }
        });

        // Toggle this dropdown
        toggle.setAttribute('aria-expanded', !isExpanded);
        menu.style.display = isExpanded ? 'none' : 'flex';

        // Focus search if opening
        if (!isExpanded && search) {
          setTimeout(() => search.focus(), 100);
        }
      });

      // Close button
      if (closeBtn) {
        closeBtn.addEventListener('click', function(e) {
          e.preventDefault();
          e.stopPropagation();
          closeDropdown(dropdown);
        });
      }

      // Filter options
      if (search) {
        search.addEventListener('input', function() {
          const filter = this.value.toLowerCase();
          options.forEach(option => {
            const value = option.getAttribute('data-value') || '';
            if (value.includes(filter)) {
              option.style.display = '';
            } else {
              option.style.display = 'none';
            }
          });
        });
      }

      // Update count badge
      function updateCount() {
        const count = Array.from(checkboxes).filter(cb => cb.checked).length;
        if (badge) {
          badge.textContent = count;
          badge.style.display = count > 0 ? '' : 'none';
        }
      }

      checkboxes.forEach(checkbox => {
        checkbox.addEventListener('change', updateCount);
      });

      // Initialize count
      updateCount();
    });

    // Close dropdowns when clicking outside or pressing escape
    document.addEventListener('click', function(e) {
      if (!e.target.closest('[data-controller="checkbox-dropdown"]')) {
        document.querySelectorAll('[data-controller="checkbox-dropdown"]').forEach(dropdown => {
          closeDropdown(dropdown);
        });
      }
    });

    document.addEventListener('keydown', function(e) {
      if (e.key === 'Escape') {
        document.querySelectorAll('[data-controller="checkbox-dropdown"]').forEach(dropdown => {
          closeDropdown(dropdown);
        });
      }
    });
  }

  // Initialize on page load
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', initializeCheckboxDropdowns);
  } else {
    initializeCheckboxDropdowns();
  }

  // Re-initialize on Turbo load (if using Turbo)
  document.addEventListener('turbo:load', initializeCheckboxDropdowns);
})();
