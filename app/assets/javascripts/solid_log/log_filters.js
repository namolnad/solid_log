// Log Filter Buttons
// Handles click events on log filter buttons to apply filters

document.addEventListener('DOMContentLoaded', function() {
  // Handle filter button clicks
  document.addEventListener('click', function(e) {
    if (e.target.matches('.log-filter-btn') || e.target.closest('.log-filter-btn')) {
      e.preventDefault();
      e.stopPropagation();

      const button = e.target.matches('.log-filter-btn') ? e.target : e.target.closest('.log-filter-btn');
      const filterType = button.dataset.filterType;
      const filterValue = button.dataset.filterValue;

      if (!filterType || !filterValue) return;

      // Build URL using current location as base
      const url = new URL(window.location.origin + window.location.pathname);

      // Map filter types to URL parameters
      const paramMapping = {
        'request_id': 'filters[request_id]',
        'ip': 'filters[ip]',
        'user_id': 'filters[user_id]',
        'method': 'filters[method][]',
        'app': 'filters[app][]'
      };

      const paramName = paramMapping[filterType];
      if (paramName) {
        url.searchParams.set(paramName, filterValue);
        window.location.href = url.toString();
      }
    }
  });
});
