// Filter form state management - disable/enable buttons based on changes
(function() {
  function initializeFilterState() {
    const filterForm = document.querySelector('.filter-form form');
    if (!filterForm) return;

    const applyButton = filterForm.querySelector('[type="submit"]');
    const clearButton = filterForm.querySelector('a[href*="streams"]');

    if (!applyButton) return;

    // Store initial form state
    const initialFormData = new FormData(filterForm);
    const initialState = formDataToObject(initialFormData);

    // Check if any filters are currently active
    function hasActiveFilters() {
      const currentFormData = new FormData(filterForm);
      const currentState = formDataToObject(currentFormData);

      // Check if any filter has a value
      for (let key in currentState) {
        if (currentState[key] && currentState[key].length > 0) {
          // Ignore empty strings and empty arrays
          if (Array.isArray(currentState[key])) {
            if (currentState[key].some(v => v !== '')) return true;
          } else if (currentState[key] !== '') {
            return true;
          }
        }
      }
      return false;
    }

    // Check if form has changed from initial state
    function hasFormChanged() {
      const currentFormData = new FormData(filterForm);
      const currentState = formDataToObject(currentFormData);

      return !areStatesEqual(initialState, currentState);
    }

    // Update button states
    function updateButtonStates() {
      const hasChanges = hasFormChanged();
      const hasFilters = hasActiveFilters();

      // Disable Apply button if no changes
      if (applyButton) {
        applyButton.disabled = !hasChanges;
        if (hasChanges) {
          applyButton.classList.remove('btn-disabled');
        } else {
          applyButton.classList.add('btn-disabled');
        }
      }

      // Disable Clear button if no active filters
      if (clearButton) {
        if (hasFilters) {
          clearButton.classList.remove('btn-disabled');
          clearButton.style.pointerEvents = '';
        } else {
          clearButton.classList.add('btn-disabled');
          clearButton.style.pointerEvents = 'none';
        }
      }
    }

    // Listen to all form input changes
    filterForm.addEventListener('input', updateButtonStates);
    filterForm.addEventListener('change', updateButtonStates);

    // Initial state
    updateButtonStates();
  }

  // Helper: Convert FormData to plain object
  function formDataToObject(formData) {
    const obj = {};
    for (let [key, value] of formData.entries()) {
      if (obj[key]) {
        // Multiple values for same key (e.g., checkboxes)
        if (Array.isArray(obj[key])) {
          obj[key].push(value);
        } else {
          obj[key] = [obj[key], value];
        }
      } else {
        obj[key] = value;
      }
    }
    return obj;
  }

  // Helper: Deep compare two state objects
  function areStatesEqual(state1, state2) {
    const keys1 = Object.keys(state1);
    const keys2 = Object.keys(state2);

    // Check if they have the same number of keys
    if (keys1.length !== keys2.length) return false;

    // Check each key
    for (let key of keys1) {
      const val1 = state1[key];
      const val2 = state2[key];

      // Both arrays
      if (Array.isArray(val1) && Array.isArray(val2)) {
        if (val1.length !== val2.length) return false;
        for (let i = 0; i < val1.length; i++) {
          if (val1[i] !== val2[i]) return false;
        }
      }
      // One is array, other isn't
      else if (Array.isArray(val1) || Array.isArray(val2)) {
        return false;
      }
      // Both are simple values
      else if (val1 !== val2) {
        return false;
      }
    }

    return true;
  }

  // Initialize on page load
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', initializeFilterState);
  } else {
    initializeFilterState();
  }

  // Re-initialize on Turbo load (if using Turbo)
  document.addEventListener('turbo:load', initializeFilterState);
})();
