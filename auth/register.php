?>
<?php
session_start(); // W3Schools sessions
require __DIR__ . '/../config.php';

$errors = [];
$username = '';

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    // Basic sanitization
    $username = trim($_POST['username'] ?? '');
    $password = $_POST['password'] ?? '';
    $confirm  = $_POST['confirm'] ?? '';

    // Validate username (letters, numbers, underscore, 3-20 chars) — regex per W3Schools validation approach
    if (!preg_match('/^[A-Za-z0-9_]{3,20}$/', $username)) { // :contentReference[oaicite:7]{index=7}
        $errors[] = 'Username must be 3-20 chars, letters/numbers/_ only.';
    }

    // Validate password length/complexity (match W3Schools password-validation idea)
    $lenOK = strlen($password) >= 8;                         // min length like howto password guide
    $hasLower = preg_match('/[a-z]/', $password);
    $hasUpper = preg_match('/[A-Z]/', $password);
    $hasDigit = preg_match('/\d/', $password);
    if (!($lenOK && $hasLower && $hasUpper && $hasDigit)) {  // :contentReference[oaicite:8]{index=8}
        $errors[] = 'Password needs 8+ chars with upper, lower, digit.';
    }

    if ($password !== $confirm) {
        $errors[] = 'Passwords do not match.';
    }

    if (!$errors) {
        // Check if username exists (prepared SELECT)
        $stmt = $pdo->prepare('SELECT id FROM users WHERE username = :u'); // W3Schools PDO prepare/bind pattern
        $stmt->bindParam(':u', $username, PDO::PARAM_STR);                 // :contentReference[oaicite:9]{index=9}
        $stmt->execute();
        if ($stmt->fetchColumn()) {
            $errors[] = 'Username is taken.';
        } else {
            // Securely hash password (official PHP manual)
            $hash = password_hash($password, PASSWORD_DEFAULT);            // :contentReference[oaicite:10]{index=10}

            // Insert user (prepared INSERT)
            $ins = $pdo->prepare('INSERT INTO users (username, password_hash) VALUES (:u, :p)'); // :contentReference[oaicite:11]{index=11}
            $ins->bindParam(':u', $username, PDO::PARAM_STR);
            $ins->bindParam(':p', $hash, PDO::PARAM_STR);
            $ins->execute();

            // Auto login
            $_SESSION['user_id']  = (int)$pdo->lastInsertId();
            $_SESSION['username'] = $username;

            header('Location: /index.php'); // must send before output
            exit;                           // :contentReference[oaicite:12]{index=12}
        }
    }
}
?>
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <title>PokeValue - Register</title>
  <link rel="stylesheet" href="/styles/styles.css" />
</head>
<body>
  <?php include __DIR__ . '/../partials/header.php'; ?>
  <main class="container" style="max-width:560px;padding:24px 16px;">
    <h1 class="section-title">Create Account</h1>

    <?php if ($errors): ?>
      <div class="form-errors" style="border:1px solid #000;padding:12px;margin:12px 0;">
        <ul><?php foreach ($errors as $e) echo '<li>'.htmlspecialchars($e).'</li>'; ?></ul>
      </div>
    <?php endif; ?>

    <form method="post" action="">
      <label class="form-label" for="username">Username</label>
      <input class="form-input" id="username" name="username" type="text"
             required pattern="[A-Za-z0-9_]{3,20}" value="<?php echo htmlspecialchars($username); ?>" />

      <label class="form-label" for="password">Password</label>
      <input class="form-input" id="password" name="password" type="password"
             required pattern="(?=.*\d)(?=.*[a-z])(?=.*[A-Z]).{8,}" /> <!-- W3Schools pattern idea → client-side --> <!-- :contentReference[oaicite:13]{index=13} -->

      <label class="form-label" for="confirm">Confirm Password</label>
      <input class="form-input" id="confirm" name="confirm" type="password" required />

      <div style="margin-top:12px;">
        <button class="add-product-btn" type="submit">Register</button>
      </div>
    </form>
    <p style="margin-top:10px;">Already have an account? <a class="footer-link" href="/auth/login.php">Login</a></p>
  </main>
  <?php include __DIR__ . '/../partials/footer.php'; ?>
</body>
</html>

<?php