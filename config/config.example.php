<?php
declare(strict_types=1);

// Update these values for your local MySQL setup.
define('DB_HOST', 'localhost');
define('DB_NAME', 'online_bookstore');
define('DB_USER', 'bookstore_user');
define('DB_PASS', 'YOUR_LOCAL_DATABASE_PASSWORD');

date_default_timezone_set('Asia/Karachi');

// Login session limits (enforced against the user_sessions table on every request).
const SESSION_IDLE_MINUTES = 120;   // sign out after 2 hours of inactivity
const SESSION_MAX_DAYS     = 7;     // sign out 7 days after login, regardless of activity
const LOGIN_MAX_FAILS_EMAIL = 5;    // failed attempts per email in 15 minutes
const LOGIN_MAX_FAILS_IP    = 20;   // failed attempts per IP in 15 minutes

// Use HTTPS in production. These settings are suitable for local development.
ini_set('session.use_strict_mode', '1');
ini_set('session.use_only_cookies', '1');
session_name('bookstore_session');
session_set_cookie_params([
    'lifetime' => 0,
    'path' => '/',
    'secure' => !empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off',
    'httponly' => true,
    'samesite' => 'Lax'
]);
if (session_status() !== PHP_SESSION_ACTIVE) session_start();

function db(): PDO {
    static $pdo = null;
    if ($pdo === null) {
        $pdo = new PDO('mysql:host='.DB_HOST.';dbname='.DB_NAME.';charset=utf8mb4', DB_USER, DB_PASS, [
            PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
            PDO::ATTR_EMULATE_PREPARES => false,
        ]);
    }
    return $pdo;
}
function json_response(array $data, int $status = 200): never {
    http_response_code($status);
    header('Content-Type: application/json; charset=utf-8');
    echo json_encode($data, JSON_UNESCAPED_UNICODE);
    exit;
}
function request_data(): array {
    $raw = file_get_contents('php://input');
    $data = json_decode($raw ?: '{}', true);
    return is_array($data) ? $data : $_POST;
}
function require_login(): array {
    if (empty($_SESSION['user'])) json_response(['ok'=>false,'message'=>'Please log in first.'], 401);
    return $_SESSION['user'];
}
function require_permission(string $permission): array {
    $user = require_login();
    $stmt = db()->prepare('SELECT 1 FROM role_permissions rp JOIN permissions p ON p.id=rp.permission_id JOIN roles r ON r.id=rp.role_id WHERE r.id=? AND p.permission_key=?');
    $stmt->execute([$user['role_id'], $permission]);
    if (!$stmt->fetchColumn()) json_response(['ok'=>false,'message'=>'You do not have permission to perform this action.'], 403);
    return $user;
}
function csrf_check(): void {
    $token = $_SERVER['HTTP_X_CSRF_TOKEN'] ?? '';
    if (empty($_SESSION['csrf_token']) || !hash_equals($_SESSION['csrf_token'], $token)) {
        json_response(['ok'=>false,'message'=>'Invalid security token. Refresh the page and try again.'], 419);
    }
}
function require_method(string $method): void {
    if (strtoupper($_SERVER['REQUEST_METHOD'] ?? 'GET') !== strtoupper($method)) json_response(['ok'=>false,'message'=>'Method not allowed.'], 405);
}

// ---------------------------------------------------------------------------
// Login sessions + permissions
// ---------------------------------------------------------------------------
function client_ip(): string {
    return substr($_SERVER['REMOTE_ADDR'] ?? '0.0.0.0', 0, 45);
}
function session_fingerprint(): string {
    return hash('sha256', session_id());
}
/** Permissions granted to a role, read from role_permissions (the single source of truth). */
function user_permissions(int $roleId): array {
    $stmt = db()->prepare('SELECT p.permission_key AS `key`, p.description FROM role_permissions rp JOIN permissions p ON p.id=rp.permission_id WHERE rp.role_id=? ORDER BY p.permission_key');
    $stmt->execute([$roleId]);
    return $stmt->fetchAll();
}
/** The logged-in user as sent to the browser (never includes the password hash). */
function public_user(): ?array {
    $u = $_SESSION['user'] ?? null;
    if (!$u) return null;
    try { $u['permissions'] = user_permissions((int)$u['role_id']); } catch (Throwable $e) { $u['permissions'] = []; }
    return $u;
}
function revoke_current_session(): void {
    if (session_status() !== PHP_SESSION_ACTIVE || session_id() === '') return;
    try { db()->prepare('UPDATE user_sessions SET revoked_at=NOW() WHERE session_hash=? AND revoked_at IS NULL')->execute([session_fingerprint()]); } catch (Throwable $e) {}
}
/** Create a fresh login session for a user row (id, full_name, email, role_id, role_name). */
function start_login_session(array $u): array {
    revoke_current_session();                    // a previous login on this browser ends here
    session_regenerate_id(true);                 // prevents session fixation
    $_SESSION['user'] = ['id'=>(int)$u['id'], 'full_name'=>$u['full_name'], 'email'=>$u['email'], 'role_id'=>(int)$u['role_id'], 'role_name'=>$u['role_name']];
    $_SESSION['csrf_token'] = bin2hex(random_bytes(32));
    $pdo = db();
    $pdo->prepare('INSERT INTO user_sessions(user_id,session_hash,ip_address,user_agent,expires_at) VALUES(?,?,?,?,DATE_ADD(NOW(), INTERVAL '.SESSION_MAX_DAYS.' DAY))')
        ->execute([(int)$u['id'], session_fingerprint(), client_ip(), substr($_SERVER['HTTP_USER_AGENT'] ?? '', 0, 255)]);
    $pdo->prepare('UPDATE users SET last_login_at=NOW() WHERE id=?')->execute([(int)$u['id']]);
    return public_user();
}
function end_login_session(): void {
    revoke_current_session();
    $_SESSION = [];
    if (ini_get('session.use_cookies')) {
        $p = session_get_cookie_params();
        setcookie(session_name(), '', time() - 42000, $p['path'], $p['domain'] ?? '', $p['secure'], $p['httponly']);
    }
    session_destroy();
}
/**
 * Runs on every request. A PHP session only counts as "logged in" while its row in user_sessions
 * is unrevoked, unexpired, recently active, and the account is still enabled. The role is re-read
 * from the database, so promoting/demoting a user takes effect immediately.
 */
function validate_login_session(): void {
    if (empty($_SESSION['user'])) return;
    try {
        $stmt = db()->prepare('SELECT s.id, u.full_name, u.email, u.role_id, r.role_name FROM user_sessions s JOIN users u ON u.id=s.user_id JOIN roles r ON r.id=u.role_id
            WHERE s.session_hash=? AND s.user_id=? AND s.revoked_at IS NULL AND s.expires_at>NOW()
              AND s.last_activity>(NOW() - INTERVAL '.SESSION_IDLE_MINUTES.' MINUTE) AND u.is_active=1');
        $stmt->execute([session_fingerprint(), (int)$_SESSION['user']['id']]);
        $row = $stmt->fetch();
        if (!$row) { unset($_SESSION['user']); return; }
        $_SESSION['user']['full_name'] = $row['full_name'];
        $_SESSION['user']['email']     = $row['email'];
        $_SESSION['user']['role_id']   = (int)$row['role_id'];
        $_SESSION['user']['role_name'] = $row['role_name'];
        db()->prepare('UPDATE user_sessions SET last_activity=NOW() WHERE id=? AND last_activity < (NOW() - INTERVAL 1 MINUTE)')->execute([(int)$row['id']]);
    } catch (Throwable $e) {
        // Database unavailable: fail closed so nobody is treated as logged in.
        unset($_SESSION['user']);
    }
}
validate_login_session();
