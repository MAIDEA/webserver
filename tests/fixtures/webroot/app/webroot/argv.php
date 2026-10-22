<?php
// pearcmd.php vector: a query string must not populate $_SERVER['argv'] in prod
echo isset($_SERVER['argv']) ? 'argv-populated' : 'argv-absent';
