# Pin npm packages for SolidLog UI engine

pin "application", to: "application.js"
pin "@hotwired/turbo-rails", to: "turbo.min.js", preload: true
pin "@rails/actioncable", to: "actioncable.esm.js"

# Pin SolidLog UI JavaScript modules
pin "solid_log/stream_scroll", to: "solid_log/stream_scroll.js"
pin "solid_log/live_tail", to: "solid_log/live_tail.js"
pin "solid_log/jump_to_live", to: "solid_log/jump_to_live.js"
pin "solid_log/checkbox_dropdown", to: "solid_log/checkbox_dropdown.js"
pin "solid_log/timeline_histogram", to: "solid_log/timeline_histogram.js"
pin "solid_log/log_filters", to: "solid_log/log_filters.js"
pin "solid_log/filter_state", to: "solid_log/filter_state.js"
pin "solid_log/toast", to: "solid_log/toast.js"
