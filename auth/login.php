?>
<?php
session_start();
require __DIR__ . '/../config.php';

$errors = [];
$username = '';

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $username = trim($_POST['username'] ?? '');
    $password = $_POST['password'] ?? '';

    if ($username === '' || $password === '') {
        $errors[] = 'Please fill in both fields.';
    } else {
        // Prepared SELECT to get stored hash
        $stmt = $pdo->prepare('SELECT id, password_hash FROM users WHERE username = :u'); // :contentReference[oaicite:14]{index=14}
        $stmt->bindParam(':u', $username, PDO::PARAM_STR);
        $stmt->execute();
        $row = $stmt->fetch(PDO::FETCH_ASSOC);

        if ($row && password_verify($password, $row['password_hash'])) { // official manual
            $_SESSION['user_id']  = (int)$row['id'];
            $_SESSION['username'] = $username;
            header('Location: /index.php');                                // :contentReference[oaicite:15]{index=15}
            exit;
        } else {
            $errors[] = 'Invalid username or password.';
        }
    }
}
?>
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <title>PokeValue - Login</title>
  <link rel="stylesheet" href="/styles/styles.css" />
</head>
<body>
  <?php include __DIR__ . '/../partials/header.php'; ?>
  <main class="container" style="max-width:560px;padding:24px 16px;">
    <h1 class="section-title">Login</h1>

    <?php if ($errors): ?>
      <div class="form-errors" style="border:1px solid #000;padding:12px;margin:12px 0;">
        <ul><?php foreach ($errors as $e) echo '<li>'.htmlspecialchars($e).'</li>'; ?></ul>
      </div>
    <?php endif; ?>

    <form method="post" action="">
      <label class="form-label" for="username">Username</label>
      <input class="form-input" id="username" name="username" type="text" required value="<?php echo htmlspecialchars($username); ?>" />

      <label class="form-label" for="password">Password</label>
      <input class="form-input" id="password" name="password" type="password" required />

      <div style="margin-top:12px;">
        <button class="add-product-btn" type="submit">Login</button>
      </div>
    </form>
    <p style="margin-top:10px;">No account? <a class="footer-link" href="/auth/register.php">Register</a></p>
  </main>
  <?php include __DIR__ . '/../partials/footer.php'; ?>
</body>
</html>

<?php