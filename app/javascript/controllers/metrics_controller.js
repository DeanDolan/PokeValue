import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["status", "panel"]
  static values = { endpoint: String }

  connect() {
    this.loaded = false
    this.series = []
    this.labels = []
    this.dataByKey = {}
    this.labelByKey = {
      cost: "Total Cost (€)",
      value: "Total Value (€)",
      pl: "Unrealised P/L (€)",
      roi: "ROI (%)"
    }
    this.charts = {}
    this.activeKey = "cost"
    this.Chart = null

    if (this.hasStatusTarget) {
      this.statusTarget.textContent = `metrics controller connected | endpoint: ${this.endpointValue || "(missing)"}`
    }
  }

  async onShown() {
    if (!this.endpointValue) {
      if (this.hasStatusTarget) this.statusTarget.textContent = "ERROR: metrics endpoint missing (data-metrics-endpoint-value)"
      return
    }

    if (!this.loaded) {
      await this.loadEverything()
      this.loaded = true
    }

    this.show("cost")
  }

  async loadEverything() {
    const chartLoad = await this.loadChartLib()
    if (!chartLoad.ok) {
      if (this.hasStatusTarget) this.statusTarget.textContent = chartLoad.msg
      return
    }

    const dataLoad = await this.loadData()
    if (!dataLoad.ok) {
      if (this.hasStatusTarget) this.statusTarget.textContent = dataLoad.msg
      return
    }

    if (this.hasStatusTarget) {
      const dbg = dataLoad.debug ? ` | debug: ${JSON.stringify(dataLoad.debug)}` : ""
      this.statusTarget.textContent = `OK | points: ${this.series.length}${dbg}`
    }
  }

  async loadChartLib() {
    if (window.Chart) {
      this.Chart = window.Chart
      return { ok: true }
    }

    try {
      const m = await import("chart.js/auto")
      this.Chart = m.default || m.Chart || window.Chart
      if (this.Chart) return { ok: true }
    } catch (e) {
      this.Chart = null
    }

    try {
      const m = await import("chart.js")
      const Chart = m.default || m.Chart
      const registerables = m.registerables
      if (Chart && registerables && Chart.register) Chart.register(...registerables)
      this.Chart = Chart || window.Chart
      if (this.Chart) return { ok: true }
    } catch (e) {
      return {
        ok: false,
        msg:
          "ERROR: Chart.js failed to load. Fix importmap pin.\n" +
          "Fast fix: run `bin/importmap pin chart.js/auto` and restart server.\n" +
          `Details: ${e?.message || e}`
      }
    }

    return {
      ok: false,
      msg: "ERROR: Chart.js not available (no window.Chart and imports failed)."
    }
  }

  async loadData() {
    let res
    try {
      const url = this.endpointValue
      res = await fetch(url, { headers: { Accept: "application/json" } })
    } catch (e) {
      return { ok: false, msg: `ERROR: fetch failed: ${e?.message || e}` }
    }

    const ct = res.headers.get("content-type") || "(none)"
    if (!res.ok) {
      const body = await this.readTextSafe(res)
      return {
        ok: false,
        msg:
          `ERROR: /portfolio/metrics HTTP ${res.status} (${res.statusText}) | content-type: ${ct}\n` +
          `Body (first 300): ${body}`
      }
    }

    let json
    try {
      json = await res.json()
    } catch (_) {
      const body = await this.readTextSafe(res)
      return {
        ok: false,
        msg:
          `ERROR: response was not JSON | content-type: ${ct}\n` +
          `Body (first 300): ${body}`
      }
    }

    const series = Array.isArray(json.series) ? json.series : []
    if (!series.length) {
      return {
        ok: false,
        msg: `ERROR: JSON loaded but series is empty. content-type: ${ct}`,
        debug: json.debug
      }
    }

    this.series = series
    this.labels = series.map(p => this.ddmmyyyy(p.date))
    this.dataByKey = {
      cost: series.map(p => p.total_cost),
      value: series.map(p => p.total_value),
      pl: series.map(p => p.pl),
      roi: series.map(p => p.roi)
    }

    return { ok: true, debug: json.debug }
  }

  async readTextSafe(res) {
    try {
      const t = await res.text()
      return (t || "").slice(0, 300).replace(/\s+/g, " ")
    } catch (_) {
      return "(unable to read body)"
    }
  }

  select(event) {
    const key = event.currentTarget.getAttribute("data-metrics-key-param")
    if (!key) return
    this.show(key)
  }

  show(key) {
    this.activeKey = key

    this.panelTargets.forEach(p => {
      p.classList.toggle("d-none", p.dataset.key !== key)
    })

    const btns = this.element.querySelectorAll("[data-metrics-key-param]")
    btns.forEach(b => {
      const isOn = b.getAttribute("data-metrics-key-param") === key
      b.classList.toggle("btn-primary", isOn)
      b.classList.toggle("btn-outline-primary", !isOn)
    })

    if (!this.series.length || !this.Chart) return
    if (!this.charts[key]) this.buildChart(key)
    if (this.charts[key]) this.charts[key].resize()
  }

  buildChart(key) {
    const canvas = this.element.querySelector(`canvas[data-key="${key}"]`)
    if (!canvas) return

    const data = this.dataByKey[key]
    if (!data) return

    if (this.charts[key]) {
      try { this.charts[key].destroy() } catch (_) {}
      delete this.charts[key]
    }

    this.charts[key] = new this.Chart(canvas.getContext("2d"), {
      type: "line",
      data: {
        labels: this.labels,
        datasets: [{ label: this.labelByKey[key], data, tension: 0.25, pointRadius: 2 }]
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        plugins: { legend: { display: true } },
        scales: { x: { ticks: { maxTicksLimit: 10 } } }
      }
    })
  }

  ddmmyyyy(iso) {
    const d = new Date(iso + "T00:00:00")
    const dd = String(d.getDate()).padStart(2, "0")
    const mm = String(d.getMonth() + 1).padStart(2, "0")
    const yyyy = d.getFullYear()
    return `${dd}/${mm}/${yyyy}`
  }
}
