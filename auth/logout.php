?>
<?php
session_start();                 // must start to destroy — W3Schools
session_unset();                 // clear all session vars — W3Schools  :contentReference[oaicite:16]{index=16}
session_destroy();               // destroy session — W3Schools        :contentReference[oaicite:17]{index=17}
header('Location: /index.php');  // redirect — W3Schools header()      :contentReference[oaicite:18]{index=18}
exit;

<?php