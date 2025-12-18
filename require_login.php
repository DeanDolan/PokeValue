<?php
session_start();                        // W3Schools: sessions
if (empty($_SESSION['user_id'])) {      // not logged in → redirect
  header('Location: /auth/login.php');  // W3Schools: header redirect
  exit;
}