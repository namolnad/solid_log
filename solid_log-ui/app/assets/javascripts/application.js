// Entry point for the build script in your package.json
import "@hotwired/turbo-rails"
import { createConsumer } from "@rails/actioncable"

// Make createConsumer available globally for live tail
window.createConsumer = createConsumer
