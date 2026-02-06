import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["canvas", "status", "asof", "m6", "m1y", "m3y", "m5y", "hbtn"]
  static values = { endpoint: String }

  connect() {
    this._chart = null
    this._data = null
    this._activeHorizon = "1y"
    this._chartjsReady = false
    this._Chart = null

    this._onShow = (e) => this.open(e)
    this.element.addEventListener("show.bs.modal", this._onShow)
  }

  disconnect() {
    this.element.removeEventListener("show.bs.modal", this._onShow)
    this._destroyChart()
  }

  async open(e) {
    const trigger = e.relatedTarget
    const setName = trigger?.dataset?.forecastSetName
    const productName = (trigger?.dataset?.forecastProductName || "").trim()
    const productCategory = (trigger?.dataset?.forecastProductCategory || "").trim()
    const productVariant = (trigger?.dataset?.forecastProductVariant || "").trim()
    const origin = (trigger?.dataset?.forecastOrigin || "").trim()

    if (!setName) {
      this._setError("Missing set name on button (data-forecast-set-name).")
      return
    }

    this._setLoading("Loading forecast…")
    this._setActiveHorizon("1y")

    try {
      await this._ensureChartJS()
    } catch (err) {
      this._setError(`Chart.js failed to load: ${this._errMsg(err)}`)
      return
    }

    const reqUrl = this._buildUrl(setName, productName, productCategory, productVariant, origin)

    try {
      const resp = await fetch(reqUrl, { headers: { "Accept": "application/json" } })
      const text = await resp.text()

      let json
      try {
        json = JSON.parse(text)
      } catch (_) {
        throw new Error(`Non-JSON response from /forecast: ${text.slice(0, 300)}`)
      }

      if (!resp.ok || json?.ok === false) {
        const detail = json?.detail ? JSON.stringify(json.detail) : JSON.stringify(json)
        throw new Error(`HTTP ${resp.status} from /forecast: ${detail}`)
      }

      this._data = json
      this._renderAll()

      const meta = json?.meta || null
      if (meta?.matched) {
        this._setOk(`Loaded (matched: ${meta.matched_product_name}).`)
      } else {
        this._setOk("Loaded.")
      }
    } catch (err) {
      this._setError(`${this._errMsg(err)}\nRequest URL: ${reqUrl}`)
    }
  }

  changeHorizon(e) {
    const h = e?.currentTarget?.dataset?.horizon
    if (!h) return
    this._setActiveHorizon(h)
    this._renderChart()
  }

  _buildUrl(setName, productName, productCategory, productVariant, origin) {
    const base = (this.endpointValue || "/forecast").toString()
    const u = new URL(base, window.location.origin)
    u.searchParams.set("set_name", setName)
    if (productName) u.searchParams.set("product_name", productName)
    if (productCategory) u.searchParams.set("product_category", productCategory)
    if (productVariant) u.searchParams.set("product_variant", productVariant)
    if (origin) u.searchParams.set("origin", origin)
    return u.toString()
  }

  async _ensureChartJS() {
    if (this._chartjsReady) return
    const mod = await import("chart.js")
    const Chart = mod.Chart
    const registerables = mod.registerables

    if (!Chart || !registerables) {
      throw new Error("chart.js module loaded but missing Chart/registerables exports.")
    }

    Chart.register(...registerables)
    this._Chart = Chart
    this._chartjsReady = true
  }

  _renderAll() {
    const d = this._data || {}

    this.asofTarget.textContent = d.as_of || "—"

    const ms = d.milestones || {}
    this.m6Target.textContent = this._fmtMoney(ms["6m"])
    this.m1yTarget.textContent = this._fmtMoney(ms["1y"])
    this.m3yTarget.textContent = this._fmtMoney(ms["3y"])
    this.m5yTarget.textContent = this._fmtMoney(ms["5y"])

    this._renderChart()
  }

  _renderChart() {
    if (!this._data) return
    const history = Array.isArray(this._data.history) ? this._data.history : []
    const forecast = Array.isArray(this._data.forecast) ? this._data.forecast : []

    if (history.length === 0 || forecast.length === 0) {
      this._setError("No history/forecast points returned.")
      return
    }

    const horizonMonths = { "6m": 6, "1y": 12, "3y": 36, "5y": 60 }[this._activeHorizon] || 12
    const fcSlice = forecast.slice(0, horizonMonths)

    const histLabels = history.map(p => (p.date || "").slice(0, 10))
    const fcLabels = fcSlice.map(p => (p.date || "").slice(0, 10))
    const labels = histLabels.concat(fcLabels)

    const actual = history.map(p => Number(p.value))
    const actualSeries = actual.concat(new Array(fcSlice.length).fill(null))

    const lastActual = actual.length ? actual[actual.length - 1] : null
    const predictedSeries = new Array(Math.max(0, history.length - 1)).fill(null)
      .concat([lastActual])
      .concat(fcSlice.map(p => Number(p.value)))

    this._destroyChart()

    const ctx = this.canvasTarget.getContext("2d")

    this._chart = new this._Chart(ctx, {
      type: "line",
      data: {
        labels,
        datasets: [
          { label: "Actual", data: actualSeries, spanGaps: false, tension: 0.2 },
          { label: "Forecast", data: predictedSeries, spanGaps: false, tension: 0.2 }
        ]
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        animation: false,
        interaction: { mode: "index", intersect: false },
        plugins: { legend: { display: true }, tooltip: { enabled: true } },
        scales: {
          y: { ticks: { callback: (v) => this._fmtMoney(v) } }
        }
      }
    })
  }

  _setActiveHorizon(h) {
    this._activeHorizon = h
    this.hbtnTargets.forEach(btn => {
      const isActive = (btn.dataset.horizon === h)
      btn.classList.toggle("btn-primary", isActive)
      btn.classList.toggle("btn-outline-primary", !isActive)
    })
  }

  _destroyChart() {
    if (this._chart) {
      try { this._chart.destroy() } catch (_) {}
      this._chart = null
    }
  }

  _setLoading(msg) {
    this.statusTarget.textContent = msg
    this.statusTarget.classList.remove("text-danger")
    this.statusTarget.classList.add("text-muted")
  }

  _setOk(msg) {
    this.statusTarget.textContent = msg
    this.statusTarget.classList.remove("text-danger")
    this.statusTarget.classList.add("text-muted")
  }

  _setError(msg) {
    this.statusTarget.textContent = msg
    this.statusTarget.classList.add("text-danger")
    this.statusTarget.classList.remove("text-muted")
    this._destroyChart()
    this.asofTarget.textContent = "—"
    this.m6Target.textContent = "—"
    this.m1yTarget.textContent = "—"
    this.m3yTarget.textContent = "—"
    this.m5yTarget.textContent = "—"
  }

  _fmtMoney(v) {
    const n = Number(v)
    if (!isFinite(n)) return "—"
    return "€" + n.toFixed(2)
  }

  _errMsg(err) {
    if (!err) return "Unknown error"
    if (typeof err === "string") return err
    return err.message || String(err)
  }
}
