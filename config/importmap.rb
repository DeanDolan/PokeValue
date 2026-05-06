# Pin npm packages by running ./bin/importmap

# Main JavaScript entry point for the Rails application
pin "application"

# Turbo improves page navigation and form handling without full page reloads
pin "@hotwired/turbo-rails", to: "turbo.min.js", preload: true

# Stimulus connects JavaScript controllers to HTML using data-controller attributes
pin "@hotwired/stimulus", to: "stimulus.min.js", preload: true

# Automatically loads Stimulus controllers from the controllers folder
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js", preload: true

# Makes all files in app/javascript/controllers available as Stimulus controllers
pin_all_from "app/javascript/controllers", under: "controllers"

# Chart.js colour helper dependency used by Chart.js
pin "@kurkle/color", to: "https://ga.jspm.io/npm:@kurkle/color@0.3.4/dist/color.esm.js"

# Chart.js is used for portfolio metrics and future projection line charts
pin "chart.js", to: "https://ga.jspm.io/npm:chart.js@4.4.3/dist/chart.js"
