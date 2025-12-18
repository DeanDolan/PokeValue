?>
<?php
if (session_status() === PHP_SESSION_NONE) { session_start(); } // W3Schools sessions
?>
<header class="website header" role="banner">
  <div class="header-left">
    <a class="logo" href="/index.php">
      <img src="/images/logo.svg" alt="PokeValue logo" />
    </a>
    <nav class="center-nav">
      <a class="nav-link" href="/index.php">Portfolio</a>
      <a class="nav-link" href="/products.html">Products</a>
      <a class="nav-link" href="/marketplace.html">Marketplace</a>
      <a class="nav-link" href="/contact.html">Contact Us</a>
    </nav>
    <div class="header-right">
      <form class="search-bar" action="#" method="get">
        <input id="product-search" class="search-input" type="search" name="q" placeholder="Search products..." />
      </form>

      <?php if (!empty($_SESSION['user_id'])): ?>
        <span class="login-register-btn" style="pointer-events:none;opacity:.8">Hi, <?php echo htmlspecialchars($_SESSION['username']); ?></span>
        <a class="login-register-btn" href="/auth/logout.php">Logout</a>
      <?php else: ?>
        <a class="login-register-btn" href="/auth/login.php">Login/Register</a>
      <?php endif; ?>
    </div>
  </div>
</header>
<hr class="header-rule" />

<?php