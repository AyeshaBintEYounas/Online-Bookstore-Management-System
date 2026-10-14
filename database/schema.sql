CREATE DATABASE IF NOT EXISTS online_bookstore CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE online_bookstore;

CREATE TABLE roles (
  id INT AUTO_INCREMENT PRIMARY KEY,
  role_name VARCHAR(40) NOT NULL UNIQUE
);
CREATE TABLE permissions (
  id INT AUTO_INCREMENT PRIMARY KEY,
  permission_key VARCHAR(80) NOT NULL UNIQUE,
  description VARCHAR(180) NOT NULL
);
CREATE TABLE role_permissions (
  role_id INT NOT NULL,
  permission_id INT NOT NULL,
  PRIMARY KEY(role_id, permission_id),
  FOREIGN KEY(role_id) REFERENCES roles(id) ON DELETE CASCADE,
  FOREIGN KEY(permission_id) REFERENCES permissions(id) ON DELETE CASCADE
);
CREATE TABLE users (
  id INT AUTO_INCREMENT PRIMARY KEY,
  role_id INT NOT NULL,
  full_name VARCHAR(100) NOT NULL,
  email VARCHAR(190) NOT NULL UNIQUE,
  password_hash VARCHAR(255) NOT NULL,
  is_active TINYINT(1) NOT NULL DEFAULT 1,
  last_login_at TIMESTAMP NULL DEFAULT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY(role_id) REFERENCES roles(id)
);

-- One row per login. The PHP session ID is stored only as a SHA-256 hash, so a database leak
-- cannot be used to hijack a live session. Rows can be revoked (logout, disabled account, admin action).
CREATE TABLE user_sessions (
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

-- Failed/successful login attempts, used to slow down password guessing.
CREATE TABLE login_attempts (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  email VARCHAR(190) NOT NULL,
  ip_address VARCHAR(45) NOT NULL,
  success TINYINT(1) NOT NULL,
  attempted_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  INDEX idx_attempts_email (email, attempted_at),
  INDEX idx_attempts_ip (ip_address, attempted_at)
);
CREATE TABLE categories (
  id INT AUTO_INCREMENT PRIMARY KEY,
  name VARCHAR(100) NOT NULL UNIQUE,
  description VARCHAR(255) NULL
);
CREATE TABLE books (
  id INT AUTO_INCREMENT PRIMARY KEY,
  category_id INT NULL,
  title VARCHAR(180) NOT NULL,
  author VARCHAR(140) NOT NULL,
  isbn VARCHAR(30) UNIQUE NULL,
  description TEXT NULL,
  price DECIMAL(10,2) NOT NULL DEFAULT 0,
  stock INT NOT NULL DEFAULT 0,
  cover_url VARCHAR(500) NULL,
  is_active TINYINT(1) NOT NULL DEFAULT 1,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY(category_id) REFERENCES categories(id) ON DELETE SET NULL,
  CHECK(price >= 0), CHECK(stock >= 0)
);
CREATE TABLE orders (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  user_id INT NOT NULL,
  total_amount DECIMAL(10,2) NOT NULL,
  status ENUM('Pending','Processing','Shipped','Delivered','Cancelled') NOT NULL DEFAULT 'Pending',
  shipping_address VARCHAR(500) NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY(user_id) REFERENCES users(id)
);
CREATE TABLE order_items (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  order_id BIGINT NOT NULL,
  book_id INT NULL,
  title_at_purchase VARCHAR(180) NOT NULL,
  quantity INT NOT NULL,
  unit_price DECIMAL(10,2) NOT NULL,
  FOREIGN KEY(order_id) REFERENCES orders(id) ON DELETE CASCADE,
  FOREIGN KEY(book_id) REFERENCES books(id) ON DELETE SET NULL,
  CHECK(quantity > 0), CHECK(unit_price >= 0)
);

INSERT INTO roles(role_name) VALUES ('customer'), ('admin');
INSERT INTO permissions(permission_key,description) VALUES
 ('books.read','Browse and search the book catalogue'),
 ('orders.create','Place orders at checkout'),
 ('orders.read_own','View your own orders'),
 ('profile.manage','View your account and manage your signed-in devices'),
 ('admin.access','Open the admin panel'),
 ('books.manage','Add, edit and remove books'),
 ('categories.manage','Manage book categories'),
 ('users.manage','Enable or disable customer accounts'),
 ('orders.manage','View all orders and update their status'),
 ('sessions.manage','View and revoke active login sessions of all users');

-- Customer: shopping + own account only.
INSERT INTO role_permissions(role_id,permission_id)
SELECT r.id,p.id FROM roles r JOIN permissions p
WHERE r.role_name='customer'
  AND p.permission_key IN ('books.read','orders.create','orders.read_own','profile.manage');

-- Admin: every permission (looked up by name, so it never depends on row ids).
INSERT INTO role_permissions(role_id,permission_id)
SELECT r.id,p.id FROM roles r JOIN permissions p WHERE r.role_name='admin';

INSERT INTO categories(name,description) VALUES
 ('Fiction','Novels and short stories'), ('Technology','Computing and technology'),
 ('Business','Business and management'), ('Education','Learning and reference');
INSERT INTO books(category_id,title,author,isbn,description,price,stock,cover_url) VALUES
 (1,'The Secret Garden','Frances Hodgson Burnett','9780141321062','A classic story about discovery and friendship.',850.00,12,'https://covers.openlibrary.org/b/isbn/9780141321062-L.jpg'),
 (2,'Clean Code','Robert C. Martin','9780132350884','A practical guide to writing readable code.',3200.00,7,'https://covers.openlibrary.org/b/isbn/9780132350884-L.jpg'),
 (3,'The Lean Startup','Eric Ries','9780307887894','Ideas for building and growing a business.',1900.00,9,'https://covers.openlibrary.org/b/isbn/9780307887894-L.jpg');
