<?php
// Smoke-test probe: the extensions PHP loads inside Apache, lowercased, one per line
header('Content-Type: text/plain');
echo implode("\n", array_map('strtolower', get_loaded_extensions())), "\n";
