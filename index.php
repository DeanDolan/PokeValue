?>
<?php
// index.php
session_start();
?>
<?php require __DIR__ . '/require_login.php'; ?>
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial scale=1" />
  <title>PokeValue - Portfolio</title>
  <link rel="stylesheet" href="/styles/styles.css" />
</head>
<body>
  <?php include __DIR__ . '/partials/header.php'; ?>
  <header class="website header">
      <div class="header-content container">
        <a class="logo" href="index.html">
          <img src="images/pokevaluelogo.png" alt="PokeValue logo" />
        </a>

        <nav class="center-nav">
          <a class="nav-link" href="index.html">Portfolio</a>
          <a class="nav-link" href="products.html">Products</a>
          <a class="nav-link" href="marketplace.html">Marketplace</a>
          <a class="nav-link" href="contact.html">Contact Us</a>
        </nav>

        <!-- RIGHT SIDE: EXACTLY ONE opener + one logout button -->
        <div class="header-right">
          <form class="search-bar" action="#" method="get">
            <input
              id="product-search"
              class="search-input"
              type="search"
              name="q"
              placeholder="Search products..."
            />
          </form>

          <!-- The ONLY modal opener -->
          <a class="login-register-btn" href="#">Login/Register</a>

          <!-- Logout (hidden until logged in) -->
          <button id="logout-btn" class="logout-btn" type="button" hidden>
            Logout
          </button>
        </div>
      </div>
    </header>

    <!-- Portfolio summary -->
    <section class="portfolio-summary container">
      <div class="summary-item">
        <div class="summary-label">Total Cost</div>
        <div class="summary-value">
          <span class="summary-symbol">€</span>
          <span class="summary-number" id="summary-total-cost"></span>
        </div>
      </div>

      <div class="summary-item">
        <div class="summary-label">Estimated Value</div>
        <div class="summary-value">
          <span class="summary-symbol">€</span>
          <span class="summary-number" id="summary-estimated-value"></span>
        </div>
      </div>

      <div class="summary-item">
        <div class="summary-label">Unrealised P/L</div>
        <div class="summary-value">
          <span class="summary-symbol">€</span>
          <span class="summary-number" id="summary-unrealised-pl"></span>
        </div>
      </div>

      <div class="summary-item">
        <div class="summary-label">Portfolio ROI</div>
        <div class="summary-value">
          <span class="summary-symbol">%</span>
          <span class="summary-number" id="summary-portfolio-roi"></span>
        </div>
      </div>
    </section>

    <section class="portfolio-charts container">
      <!-- Chart: Total Cost -->
      <article class="chart-sections">
        <div class="chart-header">
          <h3 class="chart-title">Total Cost</h3>
          <div class="range-group">
            <input type="radio" id="tc-1m" name="range-tc" />
            <label for="tc-1m" class="range-btn">1M</label>

            <input type="radio" id="tc-3m" name="range-tc" />
            <label for="tc-3m" class="range-btn">3M</label>

            <input type="radio" id="tc-6m" name="range-tc" />
            <label for="tc-6m" class="range-btn">6M</label>

            <input type="radio" id="tc-1yr" name="range-tc" />
            <label for="tc-1yr" class="range-btn">1YR</label>

            <input type="radio" id="tc-all" name="range-tc" checked />
            <label for="tc-all" class="range-btn">ALL</label>
          </div>
        </div>
        <div class="chart-frame">
          <svg
            class="chart-svg"
            viewBox="0 0 600 260"
            preserveAspectRatio="none"
            aria-hidden="true"
          >
            <rect x="0" y="0" width="600" height="260" fill="#fff" />
            <line x1="0" y1="220" x2="600" y2="220" stroke="#eee" />
            <line x1="0" y1="180" x2="600" y2="180" stroke="#eee" />
            <line x1="0" y1="140" x2="600" y2="140" stroke="#eee" />
            <line x1="0" y1="100" x2="600" y2="100" stroke="#eee" />
            <line x1="0" y1="60" x2="600" y2="60" stroke="#eee" />
            <line x1="0" y1="220" x2="600" y2="220" stroke="#000" />
            <line x1="48" y1="0" x2="48" y2="260" stroke="#000" />
          </svg>
          <div class="chart-empty">No data yet</div>
        </div>
      </article>

      <!-- Chart: Estimated Value -->
      <article class="chart-sections">
        <div class="chart-header">
          <h3 class="chart-title">Estimated Value</h3>
          <div class="range-group">
            <input type="radio" id="ev-1m" name="range-ev" />
            <label for="ev-1m" class="range-btn">1M</label>

            <input type="radio" id="ev-3m" name="range-ev" />
            <label for="ev-3m" class="range-btn">3M</label>

            <input type="radio" id="ev-6m" name="range-ev" />
            <label for="ev-6m" class="range-btn">6M</label>

            <input type="radio" id="ev-1yr" name="range-ev" />
            <label for="ev-1yr" class="range-btn">1YR</label>

            <input type="radio" id="ev-all" name="range-ev" checked />
            <label for="ev-all" class="range-btn">ALL</label>
          </div>
        </div>
        <div class="chart-frame">
          <svg
            class="chart-svg"
            viewBox="0 0 600 260"
            preserveAspectRatio="none"
            aria-hidden="true"
          >
            <rect x="0" y="0" width="600" height="260" fill="#fff" />
            <line x1="0" y1="220" x2="600" y2="220" stroke="#eee" />
            <line x1="0" y1="180" x2="600" y2="180" stroke="#eee" />
            <line x1="0" y1="140" x2="600" y2="140" stroke="#eee" />
            <line x1="0" y1="100" x2="600" y2="100" stroke="#eee" />
            <line x1="0" y1="60" x2="600" y2="60" stroke="#eee" />
            <line x1="0" y1="220" x2="600" y2="220" stroke="#000" />
            <line x1="48" y1="0" x2="48" y2="260" stroke="#000" />
          </svg>
          <div class="chart-empty">No data yet</div>
        </div>
      </article>

      <!-- Chart: Unrealised P/L -->
      <article class="chart-sections">
        <div class="chart-header">
          <h3 class="chart-title">Unrealised P/L</h3>
          <div class="range-group">
            <input type="radio" id="pl-1m" name="range-pl" />
            <label for="pl-1m" class="range-btn">1M</label>

            <input type="radio" id="pl-3m" name="range-pl" />
            <label for="pl-3m" class="range-btn">3M</label>

            <input type="radio" id="pl-6m" name="range-pl" />
            <label for="pl-6m" class="range-btn">6M</label>

            <input type="radio" id="pl-1yr" name="range-pl" />
            <label for="pl-1yr" class="range-btn">1YR</label>

            <input type="radio" id="pl-all" name="range-pl" checked />
            <label for="pl-all" class="range-btn">ALL</label>
          </div>
        </div>
        <div class="chart-frame">
          <svg
            class="chart-svg"
            viewBox="0 0 600 260"
            preserveAspectRatio="none"
            aria-hidden="true"
          >
            <rect x="0" y="0" width="600" height="260" fill="#fff" />
            <line x1="0" y1="220" x2="600" y2="220" stroke="#eee" />
            <line x1="0" y1="180" x2="600" y2="180" stroke="#eee" />
            <line x1="0" y1="140" x2="600" y2="140" stroke="#eee" />
            <line x1="0" y1="100" x2="600" y2="100" stroke="#eee" />
            <line x1="0" y1="60" x2="600" y2="60" stroke="#eee" />
            <line x1="0" y1="220" x2="600" y2="220" stroke="#000" />
            <line x1="48" y1="0" x2="48" y2="260" stroke="#000" />
          </svg>
          <div class="chart-empty">No data yet</div>
        </div>
      </article>

      <!-- Chart: Portfolio ROI -->
      <article class="chart-sections">
        <div class="chart-header">
          <h3 class="chart-title">Portfolio ROI</h3>
          <div class="range-group">
            <input type="radio" id="roi-1m" name="range-roi" />
            <label for="roi-1m" class="range-btn">1M</label>

            <input type="radio" id="roi-3m" name="range-roi" />
            <label for="roi-3m" class="range-btn">3M</label>

            <input type="radio" id="roi-6m" name="range-roi" />
            <label for="roi-6m" class="range-btn">6M</label>

            <input type="radio" id="roi-1yr" name="range-roi" />
            <label for="roi-1yr" class="range-btn">1YR</label>

            <input type="radio" id="roi-all" name="range-roi" checked />
            <label for="roi-all" class="range-btn">ALL</label>
          </div>
        </div>
        <div class="chart-frame">
          <svg
            class="chart-svg"
            viewBox="0 0 600 260"
            preserveAspectRatio="none"
            aria-hidden="true"
          >
            <rect x="0" y="0" width="600" height="260" fill="#fff" />
            <line x1="0" y1="220" x2="600" y2="220" stroke="#eee" />
            <line x1="0" y1="180" x2="600" y2="180" stroke="#eee" />
            <line x1="0" y1="140" x2="600" y2="140" stroke="#eee" />
            <line x1="0" y1="100" x2="600" y2="100" stroke="#eee" />
            <line x1="0" y1="60" x2="600" y2="60" stroke="#eee" />
            <line x1="0" y1="220" x2="600" y2="220" stroke="#000" />
            <line x1="48" y1="0" x2="48" y2="260" stroke="#000" />
          </svg>
          <div class="chart-empty">No data yet</div>
        </div>
      </article>
    </section>

    <!-- Holdings Section -->
    <h2 class="holdings-title container">Holdings</h2>

    <!-- Holdings Filters -->
    <section class="portfolio-filters container">
      <div class="filter-row">
        <!-- Search Product -->
        <div class="filter-field">
          <label for="filter-search" class="form-label">Search Product</label>
          <input id="filter-search" class="form-input" type="search" placeholder="Search…" />
        </div>

        <!-- Era -->
        <div class="filter-field">
          <label for="filter-era" class="form-label">Era</label>
          <select id="filter-era" class="form-select">
            <option value="">All</option>
            <option>Mega Evolutions</option>
            <option>Scarlet & Violet</option>
          </select>
        </div>

        <!-- Set -->
        <div class="filter-field">
          <label for="filter-set" class="form-label">Set</label>
          <select id="filter-set" class="form-select">
            <option value="">All</option>
            <option>Phantasmal Flames</option>
            <option>Mega Evolution</option>
            <option>White Flare</option>
            <option>Black Bolt</option>
            <option>Destined Rivals</option>
            <option>Journey Together</option>
            <option>Prismatic Evolutions</option>
            <option>Surging Sparks</option>
            <option>Stellar Crown</option>
            <option>Shrouded Fable</option>
            <option>Twilight Masquerade</option>
            <option>Temporal Forces</option>
            <option>Paldean Fates</option>
            <option>Paradox Rift</option>
            <option>151</option>
            <option>Obsidian Flames</option>
            <option>Paldea Evolved</option>
            <option>Scarlet & Violet Base</option>
          </select>
        </div>

        <!-- Type -->
        <div class="filter-field">
          <label for="filter-type" class="form-label">Type</label>
          <select id="filter-type" class="form-select">
            <option value="">All</option>
            <option>Booster Box</option>
            <option>Elite Trainer Box</option>
            <option>Pokemon Center Elite Trainer Box</option>
            <option>Booster Bundle</option>
            <option>Booster Bundle Display</option>
            <option>UPC/SPC</option>
          </select>
        </div>

        <!-- Condition -->
        <div class="filter-field">
          <label for="filter-condition" class="form-label">Condition</label>
          <select id="filter-condition" class="form-select">
            <option value="">All</option>
            <option>Sealed</option>
            <option>Dented</option>
            <option>Tear</option>
          </select>
        </div>

        <!-- ROI% -->
        <div class="filter-field">
          <label for="filter-roi" class="form-label">ROI%</label>
          <input id="filter-roi" class="form-input" type="number" inputmode="numeric" placeholder="e.g 10" />
        </div>

        <!-- From -->
        <div class="filter-field">
          <label for="filter-from" class="form-label">From</label>
          <input id="filter-from" class="form-input" type="date" />
        </div>

        <!-- To -->
        <div class="filter-field">
          <label for="filter-to" class="form-label">To</label>
          <input id="filter-to" class="form-input" type="date" />
        </div>
      </div>
    </section>

    <!-- Add Product button under the filters -->
    <div class="filters-actions">
      <button class="add-product-btn" type="button">+ Add Product</button>
    </div>

    <!-- Holdings table -->
    <section class="holdings container">
      <div class="holdings-table-wrap">
        <table class="holdings-table">
          <thead>
            <tr>
              <th>Product</th>
              <th>Era</th>
              <th>Set</th>
              <th>Type</th>
              <th>Condition</th>
              <th>Qty</th>
              <th>Purchase Date</th>
              <th>Cost/Unit</th>
              <th>Total Cost</th>
              <th>Est. Value</th>
              <th>P/L</th>
              <th>ROI%</th>
              <th>Actions</th>
            </tr>
          </thead>
          <tbody>
            <!-- Empty state (no products yet) -->
            <tr class="empty-row">
              <td colspan="13">
                <div class="holdings-empty">
                  <p>No products in your holdings yet.</p>
                  <button class="add-product-btn" type="button">+ Add Product</button>
                </div>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </section>

    <footer class="website footer">
      <div class="footer-inner">
        <a class="logo" href="index.html">
          <img src="images/pokevaluelogo.png" alt="PokeValue logo" href="index.html" />
        </a>
        <p class="footer-tagline">Pokemon investing since 2025.</p>
        <div class="footer-copy">© 2025 PokeValue</div>
      </div>
    </footer>

    <!-- Auth dialog -->
    <dialog id="auth-dialog" class="auth-dialog">
      <form id="auth-form" method="dialog" class="auth-form">
        <h3 class="auth-title">Login or Register</h3>

        <label class="auth-label" for="auth-username">Username</label>
        <input id="auth-username" class="auth-input" type="text" autocomplete="username" required />

        <label class="auth-label" for="auth-password">Password</label>
        <input id="auth-password" class="auth-input" type="password" autocomplete="current-password" required />

        <div id="auth-error" class="auth-error" hidden></div>

        <div class="auth-actions">
          <button type="button" class="auth-btn ghost" data-action="cancel">Cancel</button>
          <button type="button" class="auth-btn secondary" data-action="login">Login</button>
          <button type="button" class="auth-btn primary" data-action="register">Register</button>
        </div>
      </form>
    </dialog>
  
  
  
  
  
  
  
  
  <?php include __DIR__ . '/partials/footer.php'; ?>
</body>
</html>
