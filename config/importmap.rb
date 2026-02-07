# Pin npm packages by running ./bin/importmap

pin "application"

pin "@hotwired/turbo-rails",        to: "turbo.min.js",        preload: true
pin "@hotwired/stimulus",           to: "stimulus.min.js",     preload: true
pin "@hotwired/stimulus-loading",   to: "stimulus-loading.js", preload: true

pin_all_from "app/javascript/controllers", under: "controllers"

# Chart.js (ESM) + dependency (must be pinned to CDN URLs, not downloaded)
pin "chart.js",       to: "https://ga.jspm.io/npm:chart.js@4.5.1/dist/chart.js"
pin "@kurkle/color",  to: "https://ga.jspm.io/npm:@kurkle/color@0.3.4/dist/color.esm.js"

pin "chart.js", to: "https://ga.jspm.io/npm:chart.js@4.4.3/dist/chart.js"
