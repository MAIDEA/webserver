<?php
// Smoke-test probe: reports what the image provides when PHP runs inside Apache
header('Content-Type: application/json');
$key = 'probe_' . mt_rand();
$apcu = function_exists('apcu_store') && apcu_store($key, 42) && apcu_fetch($key) === 42;
$decimal = class_exists('Decimal\Decimal')
    ? (string) (new Decimal\Decimal('0.1'))->add(new Decimal\Decimal('0.2'))
    : null;
echo json_encode(array(
    'sapi' => PHP_SAPI,
    'php' => PHP_VERSION,
    'apcu_roundtrip' => $apcu,
    'decimal' => $decimal,
    'imap' => function_exists('imap_open'),
    'upload_progress' => ini_get('session.upload_progress.enabled'),
    'post_max_size' => ini_get('post_max_size'),
    'upload_max_filesize' => ini_get('upload_max_filesize'),
    'max_input_nesting_level' => ini_get('max_input_nesting_level'),
    'memory_limit' => ini_get('memory_limit'),
    'memory_limit_overridable' => @ini_set('memory_limit', '256M') !== false,
)), "\n";
