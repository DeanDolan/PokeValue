import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  // Connects the status message and chart panels to this controller.
  static targets = ["status", "panel"]

  // Stores the Rails JSON endpoint used to load portfolio metrics.
  static values = { endpoint: String }

  // Sets up the metrics controller before the modal opens.
  connect() {
    this.loaded = false
    this.series = []
    this.labels = []
    this.dataByKey = {}
    this.labelByKey = {
      cost: "Total Cost (€)",
      value: "Total Value (€)",
      pl: "Unrealised P/L (€)",
      roi: "ROI (%)",
      realised_pl: "Realised P/L (€)"
    }
    this.charts = {}
    this.activeKey = "cost"
    this.Chart = null
  }

  // Loads Chart.js and portfolio metric data when the metrics modal opens.
  async onShown() {
    if (!this.endpointValue) {
      if (this.hasStatusTarget) this.statusTarget.textContent = "ERROR: metrics endpoint missing."
      return
    }

    if (!this.Chart) {
      try {
        const chartModule = await import("chart.js/auto")
        this.Chart = chartModule.default || chartModule.Chart || window.Chart
      } catch (_) {
        try {
          const chartModule = await import("chart.js")
          const Chart = chartModule.default || chartModule.Chart
          const registerables = chartModule.registerables

          if (Chart && registerables && Chart.register) {
            Chart.register(...registerables)
          }

          this.Chart = Chart || window.Chart
        } catch (error) {
          if (this.hasStatusTarget) this.statusTarget.textContent = `ERROR: Chart.js failed to load. ${error?.message || error}`
          return
        }
      }
    }

    if (!this.loaded) {
      const loaded = await this.loadData()
      if (!loaded) return
      this.loaded = true
    }

    this.buildChart("cost")
  }

  // Fetches the portfolio metrics JSON from Rails.
  async loadData() {
    let response

    try {
      response = await fetch(this.endpointValue, { headers: { Accept: "application/json" } })
    } catch (error) {
      if (this.hasStatusTarget) this.statusTarget.textContent = `ERROR: fetch failed. ${error?.message || error}`
      return false
    }

    if (!response.ok) {
      let body = ""

      try {
        body = await response.text()
      } catch (_) {
        body = "(unable to read response body)"
      }

      if (this.hasStatusTarget) {
        this.statusTarget.textContent = `ERROR: /portfolio/metrics HTTP ${response.status}. ${body.slice(0, 300).replace(/\s+/g, " ")}`
      }

      return false
    }

    let json

    try {
      json = await response.json()
    } catch (_) {
      if (this.hasStatusTarget) this.statusTarget.textContent = "ERROR: metrics response was not JSON."
      return false
    }

    this.series = Array.isArray(json.series) ? json.series : []

    if (!this.series.length) {
      if (this.hasStatusTarget) this.statusTarget.textContent = "ERROR: metrics data is empty."
      return false
    }

    this.labels = this.series.map((point) => {
      const date = new Date(String(point.date) + "T00:00:00")
      const day = String(date.getDate()).padStart(2, "0")
      const month = String(date.getMonth() + 1).padStart(2, "0")
      const year = date.getFullYear()

      return `${day}/${month}/${year}`
    })

    this.dataByKey = {
      cost: this.series.map((point) => point.total_cost ?? point.cost ?? 0),
      value: this.series.map((point) => point.total_value ?? point.value ?? 0),
      pl: this.series.map((point) => point.pl ?? point.unrealised_pl ?? point.unrealized_pl ?? 0),
      roi: this.series.map((point) => point.roi ?? point.roi_pct ?? point.roi_percent ?? 0),
      realised_pl: this.series.map((point) => point.realised_pl ?? point.realized_pl ?? 0)
    }

    if (this.hasStatusTarget) {
      this.statusTarget.textContent = ""
    }

    return true
  }

  // Handles metric button clicks.
  select(event) {
    const key = event.currentTarget.getAttribute("data-metrics-key-param")
    if (!key) return

    this.buildChart(key)
  }

  // Shows the selected metric panel and builds its chart.
  buildChart(key) {
    this.activeKey = key

    this.panelTargets.forEach((panel) => {
      panel.classList.toggle("d-none", panel.dataset.key !== key)
    })

    this.element.querySelectorAll("[data-metrics-key-param]").forEach((button) => {
      const active = button.getAttribute("data-metrics-key-param") === key
      button.classList.toggle("btn-primary", active)
      button.classList.toggle("btn-outline-primary", !active)
    })

    if (!this.Chart || !this.series.length) return

    const canvas = this.element.querySelector(`canvas[data-key="${key}"]`)
    if (!canvas) return

    if (this.charts[key]) {
      this.charts[key].resize()
      return
    }

    this.charts[key] = new this.Chart(canvas.getContext("2d"), {
      type: "line",
      data: {
        labels: this.labels,
        datasets: [
          {
            label: this.labelByKey[key] || key,
            data: this.dataByKey[key] || [],
            tension: 0.25,
            pointRadius: 2
          }
        ]
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        plugins: {
          legend: {
            display: true
          }
        },
        scales: {
          x: {
            ticks: {
              maxTicksLimit: 10
            }
          }
        }
      }
    })
  }
}