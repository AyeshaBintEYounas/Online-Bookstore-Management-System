-- Upgrade for an EXISTING online_bookstore database (do not run on a fresh import of schema.sql).
-- Safe to run more than once.
USE online_bookstore;

-- users.last_login_at (portable "add column if missing" for MySQL and MariaDB)
SET @c = (SELECT COUNT(*) FROM information_schema.COLUMNS
          WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='users' AND COLUMN_NAME='last_login_at');
SET @s = IF(@c=0, 'ALTER TABLE users ADD COLUMN last_login_at TIMESTAMP NULL DEFAULT NULL', 'SELECT 1');
PREPARE st FROM @s; EXECUTE st; DEALLOCATE PREPARE st;

CREATE TABLE IF NOT EXISTS user_sessions (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  user_id INT NOT NULL,
  session_hash CHAR(64) NOT NULL UNIQUE,
  ip_address VARCHAR(45) NULL,
  user_agent VARCHAR(255) NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  last_activity TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  expires_at DATETIME NOT NULL,
  revoked_at DATETIME NULL DEFAULT NULL,
  FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE,
  INDEX idx_sessions_user_active (user_id, revoked_at)
);

CREATE TABLE IF NOT EXISTS login_attempts (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  email VARCHAR(190) NOT NULL,
  ip_address VARCHAR(45) NOT NULL,
  success TINYINT(1) NOT NULL,
  attempted_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  INDEX idx_attempts_email (email, attempted_at),
  INDEX idx_attempts_ip (ip_address, attempted_at)
);

-- New permissions (existing ones keep their keys; descriptions are refreshed)
INSERT INTO permissions(permission_key,description) VALUES
 ('profile.manage','View your account and manage your signed-in devices'),
 ('admin.access','Open the admin panel'),
 ('sessions.manage','View and revoke active login sessions of all users')
ON DUPLICATE KEY UPDATE description=VALUES(description);

-- Customer gets profile.manage; admin gets everything.
INSERT IGNORE INTO role_permissions(role_id,permission_id)
SELECT r.id,p.id FROM roles r JOIN permissions p
WHERE r.role_name='customer' AND p.permission_key='profile.manage';

INSERT IGNORE INTO role_permissions(role_id,permission_id)
SELECT r.id,p.id FROM roles r JOIN permissions p WHERE r.role_name='admin';
