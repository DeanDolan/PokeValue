import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.SETS_BY_ERA = {
      "Mega Evolution": ["Phantasmal Flames", "Mega Evolution Base"],
      "Scarlet & Violet": [
        "White Flare","Black Bolt","Destined Rivals","Journey Together",
        "Prismatic Evolutions","Surging Sparks","Stellar Crown","Shrouded Fable",
        "Twilight Masquerade","Temporal Forces","Paldean Fates","Paradox Rift","151",
        "Obsidian Flames","Paldea Evolved","Scarlet & Violet Base"
      ],
      "Sword & Shield": [
        "Crown Zenith","Silver Tempest","Lost Origin","Pokemon GO",
        "Astral Radiance","Brilliant Stars","Fusion Strike","Celebrations",
        "Celebrations: Classic Collection","Evolving Skies","Chilling Reign",
        "Battle Styles","Shining Fates","Vivid Voltage","Champion's Path",
        "Darkness Ablaze","Rebel Clash","Sword & Shield Base"
      ]
    }

    this.eraSel   = this.element.querySelector("#filter-era")
    this.setSel   = this.element.querySelector("#filter-set")
    this.typeSel  = this.element.querySelector("#filter-type")
    this.condSel  = this.element.querySelector("#filter-condition")
    this.qInput   = this.element.querySelector("#filter-q")

    this.costMin  = this.element.querySelector("#filter-cost-min")
    this.costMax  = this.element.querySelector("#filter-cost-max")
    this.valueMin = this.element.querySelector("#filter-value-min")
    this.valueMax = this.element.querySelector("#filter-value-max")
    this.plMin    = this.element.querySelector("#filter-pl-min")
    this.plMax    = this.element.querySelector("#filter-pl-max")
    this.roiMin   = this.element.querySelector("#filter-roi-min")
    this.roiMax   = this.element.querySelector("#filter-roi-max")
    this.dateFrom = this.element.querySelector("#filter-date-start")
    this.dateTo   = this.element.querySelector("#filter-date-end")

    this.tbody    = this.element.querySelector("#holdings-body")

    this._onEraChange = () => { this.populateSets(); this.applyFilters(); }
    this._onApply     = () => this.applyFilters()

    this.eraSel?.addEventListener("change", this._onEraChange)
    this.setSel?.addEventListener("change", this._onApply)
    this.typeSel?.addEventListener("change", this._onApply)
    this.condSel?.addEventListener("change", this._onApply)
    this.qInput?.addEventListener("input", this._onApply)

    this.costMin?.addEventListener("input", this._onApply)
    this.costMax?.addEventListener("input", this._onApply)
    this.valueMin?.addEventListener("input", this._onApply)
    this.valueMax?.addEventListener("input", this._onApply)
    this.plMin?.addEventListener("input", this._onApply)
    this.plMax?.addEventListener("input", this._onApply)
    this.roiMin?.addEventListener("input", this._onApply)
    this.roiMax?.addEventListener("input", this._onApply)
    this.dateFrom?.addEventListener("change", this._onApply)
    this.dateTo?.addEventListener("change", this._onApply)

    this.populateSets()
    this.applyFilters()
  }

  disconnect() {
    this.eraSel?.removeEventListener("change", this._onEraChange)
    this.setSel?.removeEventListener("change", this._onApply)
    this.typeSel?.removeEventListener("change", this._onApply)
    this.condSel?.removeEventListener("change", this._onApply)
    this.qInput?.removeEventListener("input", this._onApply)

    this.costMin?.removeEventListener("input", this._onApply)
    this.costMax?.removeEventListener("input", this._onApply)
    this.valueMin?.removeEventListener("input", this._onApply)
    this.valueMax?.removeEventListener("input", this._onApply)
    this.plMin?.removeEventListener("input", this._onApply)
    this.plMax?.removeEventListener("input", this._onApply)
    this.roiMin?.removeEventListener("input", this._onApply)
    this.roiMax?.removeEventListener("input", this._onApply)
    this.dateFrom?.removeEventListener("change", this._onApply)
    this.dateTo?.removeEventListener("change", this._onApply)
  }

  populateSets() {
    const era = this.eraSel?.value
    const sets = era ? (this.SETS_BY_ERA[era] || []) : []
    if (this.setSel) {
      this.setSel.innerHTML = '<option value="">All</option>' + sets.map(s => `<option value="${s}">${s}</option>`).join("")
    }
  }

  inRange(value, min, max) {
    if (min !== "" && !isNaN(min) && value < Number(min)) return false
    if (max !== "" && !isNaN(max) && value > Number(max)) return false
    return true
  }

  applyFilters() {
    if (!this.tbody) return

    const era  = this.eraSel?.value || ""
    const set  = this.setSel?.value || ""
    const type = this.typeSel?.value || ""
    const cond = this.condSel?.value || ""
    const q    = (this.qInput?.value || "").trim().toLowerCase()

    const cMin  = this.costMin?.value || ""
    const cMax  = this.costMax?.value || ""
    const vMin  = this.valueMin?.value || ""
    const vMax  = this.valueMax?.value || ""
    const pMin  = this.plMin?.value || ""
    const pMax  = this.plMax?.value || ""
    const rMin  = this.roiMin?.value || ""
    const rMax  = this.roiMax?.value || ""
    const dFrom = this.dateFrom?.value || ""
    const dTo   = this.dateTo?.value || ""

    const rows = Array.from(this.tbody.querySelectorAll("tr"))

    rows.forEach(row => {
      const rowEra   = row.getAttribute("data-era") || ""
      const rowSet   = row.getAttribute("data-set") || ""
      const rowType  = row.getAttribute("data-type") || ""
      const rowCond  = row.getAttribute("data-condition") || ""
      const rowDate  = row.getAttribute("data-date") || ""
      const rowCost  = parseFloat(row.getAttribute("data-cost") || "0")
      const rowVal   = parseFloat(row.getAttribute("data-value") || "0")
      const rowPL    = parseFloat(row.getAttribute("data-pl") || "0")
      const rowROI   = parseFloat(row.getAttribute("data-roi") || "0")
      const haystack = (row.getAttribute("data-search") || "")

      let visible = true

      if (era && rowEra !== era) visible = false
      if (set && rowSet !== set) visible = false
      if (type && rowType !== type) visible = false
      if (cond && rowCond !== cond) visible = false

      if (q && !haystack.includes(q)) visible = false

      if (!this.inRange(rowCost, cMin, cMax)) visible = false
      if (!this.inRange(rowVal,  vMin, vMax)) visible = false
      if (!this.inRange(rowPL,   pMin, pMax)) visible = false
      if (!this.inRange(rowROI,  rMin, rMax)) visible = false

      if (dFrom && rowDate && rowDate < dFrom) visible = false
      if (dTo && rowDate && rowDate > dTo) visible = false

      row.classList.toggle("d-none", !visible)
    })
  }
}
