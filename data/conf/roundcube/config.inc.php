<?php

$config['temp_dir'] = '/tmp';
$config['log_driver'] = 'stdout';

if (getenv('DBUSER') !== false && getenv('DBPASS') !== false && getenv('DBNAME') !== false) {
  $config['db_dsnw'] = 'mysql://' . getenv('DBUSER') . ':' . getenv('DBPASS') . '@mysql/' . getenv('DBNAME');
  $config['db_prefix'] = 'rc_';
} else {
  $config['db_dsnw'] = 'sqlite:////app/sqlite.db?mode=0640';
}
$config['db_dsnr'] = '';

$config['smtp_conn_options'] = array(
  'ssl' => array(
    'verify_peer' => false,
    'verfify_peer_name' => false,
    'allow_self_signed' => true
  )
);

$config['imap_conn_options'] = array(
  'ssl' => array(
    'verify_peer' => false,
    'verfify_peer_name' => false,
    'allow_self_signed' => true
  )
);

$config['managesieve_conn_options'] = array(
  'ssl' => array(
    'verify_peer' => false,
    'verfify_peer_name' => false,
    'allow_self_signed' => true
  )
);

$config['db_prefix'] = 'rc_';
$config['default_host'] = 'tls://' . getenv('MAILCOW_HOSTNAME');
$config['default_port'] = getenv('IMAP_PORT');
$config['smtp_server'] = 'tls://' . getenv('MAILCOW_HOSTNAME');
$config['smtp_port'] = getenv('SUBMISSION_PORT');
$config['smtp_user'] = '%u';
$config['smtp_pass'] = '%p';
$config['product_name'] = 'Webmail';
$config['des_key'] = (getenv('DES_KEY') !== false) ? getenv('DES_KEY') : 'rcmail-!24ByteDESkey*Str';
$config['plugins'] = array(
    'archive',
    'zipdownload',
    'userinfo',
    'managesieve'
);
$config['managesieve_port'] = getenv('SIEVE_PORT');
$config['managesieve_host'] = 'tls://' . getenv('MAILCOW_HOSTNAME');
$config['log_driver'] = 'stdout';
$config['temp_dir'] = '/tmp/roundcube-temp';
$config['zipdownload_selection'] = true;

$config['debug_level'] = 1;

if (filter_var(getenv('DEBUG'), FILTER_VALIDATE_BOOLEAN)) {
  $config['debug_level'] = 4;
  $config['sql_debug'] = true;
  $config['imap_debug'] = true;
  $config['ldap_debug'] = true;
  $config['smtp_debug'] = true;
  $config['log_dir'] = '/app/logs';
  $config['log_driver'] = "file";
}
